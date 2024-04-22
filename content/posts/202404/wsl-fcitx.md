---
title: "WSLでfcitx5をsystemdで起動する"
date: 2024-04-23T08:25:34+09:00
slug: 2024-04-23-wsl-fcitx
type: posts
draft: false
categories:
  - computer
tags:
  - wsl
---

WSLgでGUIアプリを起動するとき、imとしてfcitx5を起動するようにしています。

今まではログインシェルのprofileで起動していましたが、systemdで起動したくなったので
unitファイルの例を示します。

まず、環境変数を設定しないといけません。
unitファイルでも環境変数を設定できますが、
自分の環境だとうまく動かなかったので、environment.dに配置します。

```sh
mkdir -p ~/.config/environment.d/

cat << _EOS_ > ~/.config/environment.d/im.conf
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
_EOS_
```

次にこのようなunitファイルを作ります。
WantsとAfterはもしかしたらいらないかもしれません
自分の環境はwaylandをdisableしているので `--disable=wayland` をつけています
```
[Unit]
Description=fcitx5
Wants=default.target
After=default.target

[Service]
ExecStart=/usr/bin/fcitx5 --disable=wayland
Restart=on-failure

[Install]
WantedBy=default.target
```

あとはユーザー権限でインストールします。
root権限だと、HOME環境変数が設定されていないので起動に失敗します

```sh
systemctl --user enable fcitx.service
systemctl --user start fcitx.service
```