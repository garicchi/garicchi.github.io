---
title: "Denoをシェルスクリプトとして使う"
date: 2024-06-02T11:47:42+09:00
slug: 2024-06-02-deno
type: posts
draft: false
categories:
  - computer
tags:
  - deno,typescript
---

プロジェクトの開発環境を整えていると、どうしても複雑なコマンドを利用する場面が存在します。

例えばdocker composeを利用したローカルサーバーの起動、CLIコマンドによる自動生成、開発環境へのデプロイコマンドなどがあります。

しかし、これらのコマンドをオプションまですべて暗記して普段使いをするのは難しく、
シェルスクリプトなどを書いて使いやすい形にすることがあると思います。

自分はbashのスクリプトを普段書くことが多いのですが、
開発メンバー全員がLinux環境であることは少なく、WindowsやMacのユーザーが多いと思います。

特にWindowsではbashスクリプトを実行するためには、git bashやmsys2などをインストールしなければいけません。
WSL2もありますが、これはWindows側のファイルシステムでスクリプトを実行すると、耐えられないぐらい遅いので
WindowsのユーザーにWSL2側のファイルシステムで開発をすることを強いることになります。

Macではbashのスクリプトがある程度動くと思いますが、sedなど、BSD系とlinux系の細かなオプションの違いなどに困る時があります。

## Denoという選択肢
そこで、goやpythonなど、OSの違いをランタイムで吸収してくれるような言語でコマンドランナーを記載したいところです。
自分の周りではWebフロントエンド開発しているメンバーも多くいるので、node.jsであればメンテもしていけそうです。

しかしシェルスクリプトといえど型は欲しくなるので、TypeScriptを使用するとよさそうです。

そこで、denoがよいのではないかと思い始めました。

denoは、TypeScriptをJavaScriptにトランスパイルしなくてもTypeScriptのまま動きます。(ts-nodeなどが不要)
また、npm installをしなくても、モジュールがキャッシュされていなければ、実行時に自動でダウンロードしてくれます。

denoをインストールしなければいけないという負担はありますが、
windowsでもwingetで提供されているし、気楽にインストールできそうな雰囲気があります。

## Denoでコマンドライン引数を処理する

CLIツールを作るので、コマンドライン引数を処理したいところです。

denoではstdにコマンドライン引数を処理するモジュールがあります。
https://docs.deno.com/examples/command-line-arguments

しかし、ヘルプの生成ができなかったり、機能が足りていないところがあります。

そこで、サードパーティですが [cliffy](https://deno.land/x/cliffy@v1.0.0-rc.4) を導入してみることにします。
denolandでも、Extremely Popularとなっているのである程度信頼できそうです。

詳しい使い方は[ドキュメント](https://cliffy.io/)を読んでもらうとして、簡単にサブコマンドを実装する例だと以下になります。

```ts
import { Command, HelpCommand } from "https://deno.land/x/cliffy@v1.0.0-rc.4/command/mod.ts";

await new Command()
  .name("main")
  .default("help")
  .command(
    "test",
    new Command()
      .option("-t, --test [test:string]", "test option", {
        required: true
      })
      .action(options => {
        console.log(options.test);
      }))
  .command("help", new HelpCommand().global())
  .parse(Deno.args);
```

## Denoでサブプロセスを呼び出す

シェルスクリプトして実行したいので、サブプロセスを飛び出して連携をすることをしたいです。

サブプロセスを呼び出す簡単な例は以下です。

```ts
const c = new Deno.Command("cat", {
  args: ["README.md"],
  stdout: 'piped',
  stderr: 'piped'
});
const p = c.spawn();

const stdout = p.stdout.pipeTo(Deno.stdout.writable, { preventClose: true });
const stderr = p.stderr.pipeTo(Deno.stderr.writable, { preventClose: true });
const status = p.status;
const result = await Promise.all([status, stdout, stderr]);
if (!result[0].success) {
  throw new Error(JSON.stringify(result[0]));
}
```

これで、サブプロセスとして `cat README.md` を呼び出し、
stdout, stderrをターミナルに表示し、
プロセスが終わるまで待機、終わった後エラーステータスなら例外をthrowしてくれます。

`{ preventClose: true }` は指定しなければ、次にDeno.Commandでサブプロセスを呼び出して、
再びターミナルにstdoutなどを表示しようとしたときに、エラーになるのでつけています。

## Denoでサブプロセスを呼び出し、出力を受け取って処理する

シェルスクリプトはコマンド間のstdin、stdoutをパイプで連携することが多いと思います。
( `cat README.md | head -n 2` など )

DenoでもStreamを利用し、stdoutを1行ずつ受け取ってみることにします。

```ts
import * as streams from "https://deno.land/std@0.224.0/streams/mod.ts";

const c = new Deno.Command("cat", {
  args: ["README.md"],
  stdout: 'piped',
  stderr: 'piped'
});
const p = c.spawn();

const stdoutStream = p.stdout.pipeThrough(new TextDecoderStream()).pipeThrough(new streams.TextLineStream());
for await (const line of stdoutStream) {
  console.log(`line -> ${line}`);
}
const status = p.status;
const result = await Promise.all([status, stdout, stderr]);
if (!result[0].success) {
  throw new Error(JSON.stringify(result[0]));
}
```

これでstdoutを1行ずつ処理することができます。

## サブプロセスを呼び出す便利関数を作る

ここまでを踏まえて、シェルスクリプトのようにサブプロセスを呼び出せる便利関数を作ってみます。

```ts
interface CmdOptions {
  cwd?: string;
  pipeThrough: boolean;
}

interface CmdResult {
  process: Deno.ChildProcess;
  stdoutPipe: ReadableStream<string>;
  stderrPipe: ReadableStream<string>;
}

async function cmd(cmd: string, args: string[], options?: CmdOptions): Promise<CmdResult | undefined> {
  const c = new Deno.Command(cmd, {
    args: args,
    cwd: options?.cwd,
    stdout: 'piped',
    stderr: 'piped'
  });
  const p = c.spawn();

  if (!options?.pipeThrough) {
    const stdout = p.stdout.pipeTo(Deno.stdout.writable, { preventClose: true });
    const stderr = p.stderr.pipeTo(Deno.stderr.writable, { preventClose: true });
    const status = p.status;
    const result = await Promise.all([status, stdout, stderr]);
    if (!result[0].success) {
      throw new Error(JSON.stringify(result[0]));
    }
    return undefined;
  }

  return {
    process: p,
    stdoutPipe: p.stdout.pipeThrough(new TextDecoderStream()).pipeThrough(new streams.TextLineStream()),
    stderrPipe: p.stderr.pipeThrough(new TextDecoderStream()).pipeThrough(new streams.TextLineStream())
  };
}
```

あとはこれを以下のように呼び出せばOKです。

```ts
// 出力がいらないとき
await cmd("cat", ["README.md"]);

// 出力がいるとき
const result = await cmd("cat", ["README.md"], {
  pipeThrough: true
});

for await (const line of result!.stdoutPipe) {
  console.log(`line -> ${line}`);
}

await result!.process.status;
```