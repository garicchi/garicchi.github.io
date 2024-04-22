---
title: "WSLgでグラフィックが壊れる場合がある"
date: 2024-04-23T08:32:05+09:00
slug: 2024-04-23-wsl-glitch
type: posts
draft: false
categories:
  - computer
tags:
  - wsl
---

WSLgでGUIアプリを起動していると、
画像のグラフィックが崩壊しているときがあります。

これはPCによって再現するものとしないものがありました。

調べているとどうもGPUサポートに問題がありそうでした

https://github.com/microsoft/wslg/issues/1148

そこで、windows側の `~/.wslconfig` に下記を書いて再起動すれば解決しました。
```
[wsl2]
gpuSupport=false
```