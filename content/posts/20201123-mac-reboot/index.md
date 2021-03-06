---
title: "Macの再起動時にリモートから繋がらなくなることがある"
date: 2020-11-23T18:54:52+09:00
draft: false
---

コロナウイルスの影響により、在宅勤務の必須化とオフィスへの出社困難な状態が続いている。

モバイルアプリ開発界隈の皆さんはアプリビルドのためにオフィスにMac miniなどのサーバーを置いて、リモートから接続しているのではないだろうか。

しかしリモートからMacをサーバーとして使うには1つ問題がある。ビルドマシンの電源ボタン問題だ。

たとえばふいにオフィスに置いているMacをVNCでリモートから停止してしまうと、電源ボタンを押すために出社しなければならない。

とはいえ、Macを適切に再起動すれば、電源ボタンをおす機会などそう無いはずだ。

しかし、自分の周りでは、確実に再起動ボタンを押したはずなのに、VNCで繋がらなくなった、sshで接続できなくなった、などの問題が多発していた。

再起動中に、OSのアップデートなどが走って、停止してしまったならまだわかるが、ほぼ毎回、再起動をするとVNCで繋がらなくなるのだ。

これはなにかおかしいと思い、調査してみたところ、どうやらFile Vault(ディスク暗号化)が問題だったようだ。

ディスク暗号化されたMacは、再起動後、正しく起動するのだが、通常のログイン画面ではなく、File Vaultのロック解除画面に行くらしい。

この画面は、通常のログイン画面と非常に似ているが、まだディスク暗号化が解除されていないため、Launch Daemonが動いていない。

Launch Daemonが動かないと、VNC Serverもssh serverも動かないので、リモートから繋がらなくなる仕組みだ。

File Vaultのログイン画面で、手動でログインを行うことで、初めてVNC Serverが立ち上がる。

これは、ディスク暗号化されたMacでのみ発生する。File Vault無効化したMacは、再起動後も正しくVNC接続できた。
しかし、ビルドサーバーなんておそらく大抵会社管理であり、情シスがしっかりしていればディスク暗号化を必須にしているはずだ。

ではどうすれば、リモートからディスク暗号化されたMacを再起動し、再起動後もVNCでつながるようにするかというと、
下記コマンドを実行すれば良いらしい。

```sh
sudo fdesetup authrestart
```

このコマンドを実行後、Macは自動的に再起動をする。
その後、ディスク暗号化を解除した状態で起動してくれるので、起動後はVNC Serverが起動している。

つまり、ディスク暗号化したMacに対し、リモートから再起動を行う場合は、MacのGUIの再起動ボタンやrebootコマンドを使用してはいけない。

fdesetup authrestartコマンドを使用し、再起動をしないと、再起動後繋がらなくなる。

## 参考
- [Remote into Mac Mini after a reboot](https://apple.stackexchange.com/questions/233853/remote-into-mac-mini-after-a-reboot/233861)