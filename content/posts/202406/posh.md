---
title: "Powershellを使いやすくしたい"
date: 2024-06-02T15:16:01+09:00
slug: 2024-06-02-posh
type: posts
draft: false
categories:
  - computer
tags:
  - powershell
---

最近はWSLでずっと生活しているのですが、
結局書いているコードはdotnet(C#)で、
ssh接続もあまりしなくなり、
Linux特有のこともしなくなってきました。

ので、自分の開発範囲では、IDEがあれば実はどのOSもそんなに開発体験はかわらないのでは
と思い始めました。

ただ、ターミナルはEmacsキーバインド + 履歴補完 + git branch表示は譲れないので
これをpowershellで実現できたらそれらしく生活できる気がします。

長らくPowershellに苦手意識もあったので、これを機にPowershellの環境整備をしてみます。

## Windows Powershellを捨てる

Powershellの環境整備、それはWindows Powershellを捨てるところから始めます。
なぜかというと、Windows11に標準で搭載されているPowershellは
正式にはWindows Powershellで、メジャーバージョンは5系です。

最新のPowershell (Windowsに依存しなくなったやつ？)のメジャーバージョンは7系なので
アップグレード、というよりPowershellのインストールをしましょう。

ここら辺を見て、wingetとかでPowershellをインストールします

https://learn.microsoft.com/ja-jp/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.4

インストールして再ログインとかしてると、Windows Terminalに
Windows PowershellではないPowershellが出てくるので、
今後はこれを使うこととします。 

## Profileをいじる

bashでいう、 `~/.bash_profile` と同じようにpowershellにもprofileが存在するのでそれを作ります。

ただし、ホームディレクトリではなく、 `$profile` 変数に格納されているところにprofileがあります。
```sh
Write-Host $profile
```

ここに以下のprofileを書き込みましょう。

```ps1
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
Set-PSReadlineOption -EditMode Emacs
Set-PSReadLineOption -BellStyle None
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
```

profileでexecution policyをRemoteSignedにしてあげることでbashと同じように、
ローカルで書かれたスクリプトはデジタル署名なしで実行できるようになります。
ただし、怪しいスクリプトを実行するのはよくないので自己責任でお願いします。

-EditModeをEmacsにすると念願のEmacs Keybindが手に入ります。

あとは -PredictionSourdce Historyとかをすると、履歴補完ができるようになります。

## Promptをいじる

これで履歴補完とemacs keybindは手に入りました。
次にプロンプトをいじって、git branchを表示しましょう。

以下をProfileに追記します。

```ps1
function prompt {
    $ESC = [char]27
    if (Get-Command "git" -errorAction SilentlyContinue) {
        $BRANCH = "[$ESC[43mgit:$(git branch --show-current)$ESC[0m]"
    }

    if (Get-Command "az" -errorAction SilentlyContinue) {
        $SUBSC = $(az account show --query 'name')
        if ($null -ne $SUBSC){
            $AZ = "[$ESC[46maz: $(${SUBSC}.Substring(0, 10)) $ESC[0m]"
        }
    }

    Write-Output "${PWD} ${BRANCH} ${AZ} >"
}
```

powershellユーザーにはazureユーザーが多いと思うので、azureのsubscriptionも表示してみました。
fzfみたいに履歴候補がでてきて素敵ですね。

![alt](../img/posh.png)

おわり