---
title: "Powershellでgit branch表示高速版"
date: 2024-06-10T08:19:23+09:00
slug: 2024-06-10-posh-fast
type: posts
draft: false
categories:
  - computer
tags:
  - powershell
---

[前回](https://blog.garicchi.me/posts/202406/2024-06-02-posh/)、Powershellでgitブランチとazure subsciptionを表示したわけですが、コマンドを利用しているせいで、Powershellのプロファイルロードに1秒ぐらいかかっていたので高速化しました。

gitブランチ情報もazure subscriptionも、ファイル上に記載されているのでそれを読み込みます。

```posh
function prompt {
    $ESC = [char]27
    if (test-path .git\HEAD -pathtype leaf) { 
        $BRANCH= "[$ESC[43mgit:$($(get-content .git/HEAD).split("/") | select-object -last 1)$ESC[0m]"
    }

    if (test-path ~/.azure/azureProfile.json -pathtype leaf) { 
        $AZ = "[$ESC[46maz: $($(get-content -raw ~\.azure\azureProfile.json | convertfrom-json | select-object -expandproperty subscriptions | where-object isDefault | select-object -expandproperty name).Substring(0, 9)) $ESC[0m]"
    }

    Write-Output "${PWD} ${AZ} ${BRANCH}> "
}
```

powershellはデフォルトでjsonを扱えて素敵ですね