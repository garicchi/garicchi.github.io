---
title: "WSL+MSYS2+fishが結構良い"
date: 2024-02-05T16:14:21+09:00
slug: 2024-02-05-wsl
type: posts
draft: false
categories:
  - windows
tags:
  - windows
---

## Windowsのターミナル環境をどうするか
自分は普段からPOSIXベースなターミナル環境で開発するのが好きで、
仕事をするときはThinkPad、Ubuntu、tmux、oh-my-zsh、Jetbrains系、VSCodeを使ってました。

趣味用のPCはSurface Laptop 4で、Windowsが入っているのですが、
Jetbrains系のWSLサポートがちょっともう少しなところがあって、若干文鎮化してました。

そこで、最近SurfaceにUbuntuをネイティブ環境として入れようとしたら、
UbuntuをLVMでディスク暗号化をすると、起動時に暗号化キーを入れるところでキーボードが反応しないという問題にぶち当たりました。

ディスク暗号化は絶対にしたいのでちょっとSurfaceにUbuntuを直接入れるのは厳しいかなーという気持ちになりました。

結局SurfaceにはWindowsを入れるしかなくなったのですが、tmuxが使いたいのと、POSIXが良いということで、
WSLを使わざるを得なくなりました。

しかし、Jetbrains系のエディタをWSLでフルに使うことは難しい。というところで詰んでいたのですが、
[最近WSLでもGUIアプリが動く](https://learn.microsoft.com/ja-jp/windows/wsl/tutorials/gui-apps)
というのを思い出し、使ってみました。

するとこれが意外にもちゃんと動いて、WSLに入れたchromeやJetbrains系エディタがなんのストレスもなく動きました。
これは良いものだということで、せっかくなのでWindowsをちゃんと開発機として使うべく、環境を整えることにしました。

## WSL GUI
WSL上で動くGUIアプリはLinuxの世界なので、デフォルトだと日本語入力ができません。

そこで、fcitx-mozcを入れて、日本語入力環境を整えます。
gnomeならibus-mozcもありますが、WSL GUIだとibus mozcの設定画面でフリーズするのでfcitxのほうが良かったです。

ここらへんを参考にして日本語入力環境を整えます。
https://kazblog.hateblo.jp/entry/2018/05/28/221242

これでWSL上でJetbrains系のエディタを使ってストレスフリーに開発ができます。

## MSYS2を使う
次にWindows側の話なのですが、Windows側でもやはりPOSIX系のターミナルがほしいところです。

以前はgit bashを使っていたのですが、コマンド履歴補完とtmuxのセットアップが難しく、諦めていました。
しかし、MSYS2を使えば、pacmanでtmuxをインストールできるし、oh-my-zshもインストールできるので、
これはWindowsでも快適なPOSIXターミナルが作れるのではと思いました。

しかし、MSYS2でoh-my-zshの環境を整えたところ、かなり挙動が遅く、日常使いは難しいと感じました。

そこで、[fish shell](https://fishshell.com/)を試してみたところ、これがかなり素早く動作し、
しかもコマンド履歴補完もデフォルトでついてくるという嬉しいものでした。

fishはPOSIXと互換のある文法ではないので、bashのスクリプトから変換作業が必要にはなりますが、
それでもだいぶbashに近い感覚でwindowsを操作できます。

ただ、MSYS2+fishでtmuxを立ち上げると、 `tmux open terminal failed: not a terminal` が出てしまいます。
そこで、以下のスクリプトを用意しておいて、これを使用してtmuxを立ち上げることにしました。

```sh
#!/bin/bash -e

script -c tmux /dev/null
```

これでWindowsでもPOSIX(っぽい)ターミナル + tmux + コマンド履歴補完 を手に入れることができました。

## 終わりに
MSYS2とWSL GUIとfishを使うことで、WindowsとWSLのターミナルの操作性をかなり近づけることができ、だいぶストレスフリーになりました。

WSL GUIは、こんなにもちゃんと動くと思っていなかったので、Jetbrains系がWindowsPCでPOSIX系ターミナルと合わせて使えて大変満足です。