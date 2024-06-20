---
title: "複数のcsprojがある環境でdocker buildを高速化する"
date: 2024-06-20T19:14:58+09:00
slug: 2024-06-20-dotnet-docker
type: posts
draft: false
categories:
  - computer
tags:
  - docker
  - dotnet
---

Dockerfileを書く時、先にパッケージ定義ファイルだけコピーし、
パッケージのインストール、その後、ソースコードをコピーするというテクニックがあります。

pythonだとベストプラクティスにもあるとおり、以下のようになります。
```
COPY requirements.txt /tmp/
RUN pip install /tmp/requirements.txt
COPY . /tmp/
```

https://docs.docker.jp/develop/develop-images/dockerfile_best-practices.html

こうすることで、ソースコードを変更したあとの2回目以降のdocker buildは
パッケージインストールの部分がレイヤキャッシュされ、スキップされます
結果、高速にビルドすることができます。

これをしない場合、毎回ソースコードを変更してビルドするたびにパッケージのインストールが走るので開発効率が落ちます。

pythonやnode.jsなどはパッケージ定義ファイルが基本的に1つなので、
これが楽にできるのですが、
dotnetの場合はcsprojごとに使用するパッケージが記載されるので
先にすべてのcsprojをコピーしてdotnet restoreをしなければいけません

しかしプロジェクトにかかわるすべてのcsprojをコピーする命令をDockerfileに記載するのはなかなか難しいです。

## Central Package Managementを使う

MSBuildには、各csprojが依存するパッケージバージョンを1つのファイルで管理する機能があります。
https://devblogs.microsoft.com/nuget/introducing-central-package-management/

Directory.Packages.propsというファイルに依存パッケージを定義し、
以下のようなディレクトリ構成にします

TestProj1にDockerfileがあり、このプロジェクトをdockerでbuildすることとします。
```
.
├── Directory.Build.props
├── Directory.Packages.props
├── DotnetDocker.sln
├── TestProj1
│   ├── Dockerfile
│   ├── Program.cs
│   └── TestProj1.csproj
└── TestProj2
    ├── Program.cs
    └── TestProj2.csproj
```

## ダミーcsprojをDockerfile内で作る

その後、TestProj1のDockerfileには以下のように記載をします。

```Dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0

COPY ./Directory.Packages.props ./Directory.Build.props /local/

WORKDIR /local/

# csprojを自動生成してdotnet restore
RUN echo '<Project Sdk="Microsoft.NET.Sdk"><ItemGroup>' > restore.csproj
RUN grep "<PackageVersion Include=" Directory.Packages.props | sed -r "s/<PackageVersion Include=/<PackageReference Include=/g" | sed -r "s/Version=[^ ]+//g" >> restore.csproj
RUN echo '</ItemGroup></Project>' >> restore.csproj

RUN dotnet restore

# ソースコードを変更してもここまではキャッシュされる

COPY . /local/

WORKDIR /local/TestProj1

RUN dotnet build
```

ポイントは、Directory.*.propsをコピーした後、ダミーのcsprojを作って、
全てのパッケージを自動で記載しているところです。

こうすることで、Directory.*.propが変わらない限りは、ソースコードを変更しても
Nugetの再ダウンロードが走りません

あとはslnのあるところで、docker buildをします。

```
docker build -t test -f ./TestProj1/Dockerfile .
```

dotnet restoreがキャッシュされていることが確認できます。
```
 => CACHED [ 7/10] RUN dotnet restore 0.0s
 => [ 8/10] COPY . /local/ 0.1s
 => [ 9/10] WORKDIR /local/TestProj1 0.1s
 => [10/10] RUN dotnet build 
```

## おまけ
まだstableではありませんが、COPYに--excludeオプションが入りそうな感じになってます。
これが入れば、.csをexcludeすることで、同じようなことが実現できるかもしれません

https://docs.docker.com/reference/dockerfile/#copy---exclude