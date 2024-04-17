---
title: "WSLでVPNに接続したとき、MTUを自動で切り替える"
date: 2024-04-17T14:05:27+09:00
slug: 2024-04-17-wsl-vpn
type: posts
draft: true
categories:
  - default
tags:
  - wsl
---

最近、仕事環境をネイティブのUbuntuからWSLに切り替えました。

しかし、WSLはVPN周りで問題があることがよく知られており、
自分の知っている範囲だと、以下の2点がよく話題になっているように見えます。

1. WindowsでVPNに接続するとdnsがおかしくなる
2. WindowsでVPNに接続するとMTU値が反映されなく、通信ができなくなる

そこで、最新のWSLではどうなっているのか試してみました。

## MTU値の問題はまだある

Windows側でVPNに接続し、WSLで通信テストをしてみました。

テキトーなサーバーにping、dig、curl等を試してみた結果、digだけ通りました。

digが通ったということはdnsが正しく引けているはずなので、上述の1.の問題は解決していそうです。

pingが通らないというのは、MTU値に問題がある可能性があるので、 `-s` オプションで徐々にMTU値をいじって通信テストをしてみました。

すると、自分の環境ではMTU値が1372あたりを下回ったとき、通信ができました。

Windows側でMTU値を確認したところ、VPNのインターフェースはMTU値が1400であり、WSL側のeth0のMTU値は1500のままで、パケットがロストしていたようです。

そこで、下記コマンドでWSL側のMTU値を変更したところ、pingは通りました。

```sh
sudo ip link set dev eth0 mtu 1372
```

## TLSのMTU値はさらに低い

しかし、curlでhttpsのサーバーに通信をしようとしたところ、timeoutになってしまいました。

`curl -v`を試してみたところ、下記部分で処理が止まっており、TLSのコネクションで問題が発生していそうでした。

```
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
```

そこで、MTU値を変更しながら、curlでの通信テストをしていると、1257あたりで、TLSが通るようになりました。(この値はお使いのVPNサーバーに依存すると思われます)

したがって、VPNに接続した状態でWSLからhttps通信をするためには、かなりMTU値をさげないといけないことがわかりました。

## VPNに接続したときにMTU値を自動で切り替えたい

とりあえずVPNに接続した状態でもWSLから通信をしたいのであれば、下記コマンドでMTU値を設定してあげればよいです。
```
sudo ip link set dev eth0 mtu {curlが通ったmtu値}
```

しかし、VPNに接続していないときに低いMTU値を使ってしまうと、通信速度の低下を招いてしまう恐れがあります。

そこで、なんとかしてWindows側のVPN接続を検知して、MTU値を切り替えれないか試してみることにしてみます。

## NetworkChangeイベント

ネットワークが切り替わったタイミングを検知するためには、dotnetの [System.Net.NetworkInformation.NetworkChange](https://learn.microsoft.com/ja-jp/dotnet/api/system.net.networkinformation.networkchange.networkaddresschanged?view=net-8.0)を使えばよさそうです。

これをWSLからWindowsを経由して呼び出せれば、WSLからWindowsのVPN接続変更を検知できそうです。

powershellはdotnetのオブジェクトを呼び出せるので、下記のようなpowershellコードで、NetworkChangeイベントを受け取ることができます。

```ps1
$onChangeNetwork = {
    Write-Host "Network Changed"
}

$networkChange = [System.Net.NetworkInformation.NetworkChange]
Register-ObjectEvent `
    -InputObject $networkChange `
    -EventName NetworkAddressChanged `
    -Action $onChangeNetwork | Out-Null

Wait-Event
```

WSLはexeを呼び出してWindows側のプロセスを起動できるので、あとは上記のようなpowershellをWSLで起動し、ネットワークの変更を検知したら `ip link set` でMTUを自動変更するsystemd unitを作ればよさそうです。

## wsl-vpn-agent
ということで、作ってみました。

[wsl-vpn-agent](https://github.com/garicchi/wsl-vpn-agent)

sudoでsubprocessを呼び出したりしているので自己責任でご使用ください。

## おわりに
WSLでVPN問題はもう治ってたかと思ってましたが、治ってませんでした。

なぜWSL上ではMTU値がWindowsより低いのか、自分ではわからなかったので有識者の人教えてもらえるとうれしいです。

VPNに接続したとき、MTU値が自動で設定されるようにWSLのアップデートに期待したいですね
