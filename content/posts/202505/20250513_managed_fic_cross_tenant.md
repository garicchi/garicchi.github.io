---
title: '[Azure] Managed IdentityとWorkload Identity Feferationで別ディレクトリにあるリソースにアクセスする'
date: 2025-05-13T16:56:17+09:00
draft: false
categories:
  - computer
tags:
  - azure
---

Azureで、ディレクトリAにあるリソース(blob storageなど)をディレクトリBにあるアプリ(app serviceなど)から参照したいということがあります

この時、認証をどうするかが課題となりますが、
オーソドックスなやり方だと、下記のようになるかなと思います

1. アクセスしたいリソースのあるテナントAにアプリ登録でアプリケーションを作る
1. 作ったアプリケーションをアクセスしたいリソースにロール割り当てをする
1. アプリケーションでクライアントシークレットを発行する
1. そのクライアントシークレットを使って、ディレクトリBにあるサーバーから、リソースのAPIを呼び出す

この場合、2点の課題が存在します

1. 長期間有効なシークレットを発行することになり、シークレットが漏洩する危険がある
1. シークレットの有効期限の上限が2年間であり、2年ごとにシークレットを更新する作業が発生する

## managed identityとworkload identity federation

近年のAzureは長期間有効なシークレットは使用せず、
短時間の間のみ有効な一時トークンを認証サーバーに発行してもらい、
それを使ってリソースにアクセスするというのがメジャーかと思います。

これをAzureディレクトリ内のリソース同士で容易に使用できるようにするために、
managed identityという仕組みが存在します。

さらに、クラウド間(別の認証サーバー間)で同じようなことを実現するために
workload identity federationというものが存在します。

このように、managed identityとworkload identity federationを使用すれば、
長期間有効なシークレットを発行せずとも、サーバー間の認証が可能になります。

本稿では、managed identityとworkload identity federationを利用して
異なるAzureディレクトリ間で、2年ごとにローテーションする必要のない、
Entra IDベースの認証の検証結果を記載します

## 構築例

今回、例として下図のような構成を作ります

![1](../img/workload-identity-architecture.png)

まず、説明をわかりやすくするために、APIを呼び出す側のサーバーが所属するディレクトリをDirectory Appと呼ぶことにします。
今回は、APIを呼び出す側のサーバーとして、Azure App Serviceを使用しますが、managed identityに対応していれば他の物でも大丈夫だと思います。

次に、APIを呼び出されるリソースが所属する側のディレクトリをDirectory Resourceと呼ぶことにします。
今回はStorage Accountとしましたが、大抵のAPIを呼び出せるAzureリソースなら大丈夫だと思います。

Directory Appにはユーザー割り当てのManaged IDを作り、App Serviceにアサインします。

{{< details summary="システム割り当てのManaged IDではダメのか？" >}}
公式ドキュメントに下記の記載があるため、ユーザー割り当てのManaged IDでないと認証が通りません。
システム割り当てのManaged IDも試しましたが、エラーになりました。

> Only user-assigned managed identities can be used as a federated credential for apps. system-assigned identities aren't supported.
> https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity?tabs=microsoft-entra-admin-center#important-considerations-and-restrictions

{{< /details >}}

次に、Directory Appにはアプリ登録からアプリケーションを1つ作る必要があります。
アプリ登録から作ったアプリケーションは、フェデレーション資格情報というものを登録できます。
これがworkload identity federationの設定になります。

このフェデレーション資格情報に、先ほどのユーザー割り当てのManaged IDを指定することができます。

こうすることで、App ServiceからManaged Identity Credentialでユーザー割り当てのmanaged idのtokenを取得でき、
さらにそのtokenをアプリケーションの権限になるtokenへとworkload identity federationで交換することができます。

次に、Directory Appに作ったアプリケーションを、Directory Resourceに所属させます。

これは、サービスプリンシパルを作成することでDirectory AppのアプリケーションをDirectory Resourceに所属させることができます。

{{< details summary="Managed IDのアプリケーションIDをDirectory Resourceにサービスプリンシパルとして登録できないか？" >}}
試したのですが、エラーになりました
{{< /details >}}

{{< details summary="アプリ登録をDirectory Resourceで行うことはできないか？" >}}
アプリ登録をDirectory Appではなく、Directory Resourceですることは試したのですが、
Directory Appで発行されたmanaged id tokenをDirectory Resourceのtokenへと変換することが出来ず、エラーになりました
{{< /details >}}

次に、Directory Resourceに所属させたサービルプリンシパルを、ストレージアカウントにロール割り当てします。

最後に、Directory AppにあるApp ServiceからDirectory ResourceにあるリソースのAPIを呼び出すことで、永続シークレットなしの認証が実現します。

## 構築手順

### サーバーとリソースを作る

まず、Directory App (APIをコールするサーバーがあるディレクトリ)に、App Serviceを作ります。

そして、Directory Resource (APIをコールされる側のリソースがあるディレクトリ)にStorage Accountを作ります。

### ユーザー割り当てManaged IDを作る

次に、Directory Appに、ユーザー割り当てのManaged IDを作ります。

そして、作成されたManaged IDをApp Serviceに割り当てます。

### Directory Appにアプリケーションを作る

Directory App (APIをコールするサーバーがあるディレクトリ)にアプリケーションを作ります。

ポータルのEntra IDのメニューから、 `アプリ登録` を行い、アプリケーションを作ります。

この時、アプリケーションの種類を `任意の組織ディレクトリ内のアカウント (任意の Microsoft Entra ID テナント - マルチテナント)` にする必要があります。

アプリを作ったら、 `APIのアクセス許可` からデフォルトでできている `User.Read` のスコープを消します。
これは、今回のケースでは特にAPIスコープが必要ないからです。

### アプリケーションのフェデレーション資格情報にManaged IDを追加する

Directory Appのアプリケーションの `証明書とシークレット` を開き、 `フェデレーション資格情報` を追加します。

シナリオは `Managed Identity` で、先ほど作ったユーザー割り当てのManaged Idを指定します。

### Directory Resourceにサービスプリンシパルを作る

次に、先ほど作ったDirectory Appのアプリケーションを、Directory Resourceにサービスプリンシパルとして登録します。

この作業はazure cliが必要になります。

az loginやaz account set --subscriptionで、Directory Resourceのサブスクリプションを選択します。

そして、下記コマンドを実行します。

```sh
az ad sp create --id {Direcotry AppのアプリケーションID}
```

すると、Directory Resourceに、アプリケーションがサービスプリンシパルとして登録されます。

Directory Resourceのエンタープライズアプリケーションのメニューから、検索フィルタを外し、アプリケーションの名前で検索すると、サービスプリンシパルができたことを確認できます。

### サービスプリンシパルをリソースにロール割り当てする

先ほど作ったDirectory Resourceのサービスプリンシパルを、アクセスしたいリソースにロール割り当てします。

今回の例では、ストレージアカウントのBlob 共同作成者に割り当てることとします。

### App ServiceでAPIを呼び出す

下記コードをApp Serviceにデプロイします

```cs
var managedIdentityClientId = "{ユーザー割り当てManaged IDのクライアントID}";
var resourceTenantId = "{APIをコールされる側のリソースがあるディレクトリのテナントID}";
var registeredAppId = "{アプリ登録から作ったアプリケーションのID}";

var credential = new ClientAssertionCredential(
    resourceTenantId,
    registeredAppId,
    async cancellationToken =>
    {
        const string scope = "api://AzureADTokenExchange/.default";
        var tokenRequestContext = new Azure.Core.TokenRequestContext([scope]);
        var miCredential = new ManagedIdentityCredential(managedIdentityClientId);
        var accessToken = await miCredential.GetTokenAsync(tokenRequestContext, cancellationToken).ConfigureAwait(false);
        return accessToken.Token;
    });

var storageAccountName = "{ストレージアカウント名}";
var containerName = "{blobコンテナ名}";
var containerClient  = new BlobContainerClient(new Uri($"https://{storageAccountName}.blob.core.windows.net/{containerName}"), credential);
```

これでEntra ID認証のみで別テナントのリソースにアクセスすることができます。

## 参考資料

- [Configure an application to trust a managed identity](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity?tabs=microsoft-entra-admin-center)
  - 単一のディレクトリ内ですが、managed idとworkload identityの一次情報があります
  - マルチテナントについては、 `If you need to access resources in another tenant, your app registration must be a multitenant application and provisioned into the other tenant.` と記載があるので、マルチテナントも公式な使い方のようです
- [Effortlessly access cloud resources across Azure tenants without using secrets](https://devblogs.microsoft.com/identity/access-cloud-resources-across-tenants-without-secrets/)
  - 公式のブログです。こちらでは明確にmulti tenantと書かれています
- [Create an enterprise application from a multitenant application in Microsoft Entra ID](https://learn.microsoft.com/en-us/entra/identity/enterprise-apps/create-service-principal-cross-tenant?pivots=azure-cli)
  - azure cliで実行した、別テナントにサービスプリンシパルを作る方法について記載があります
  - portalにUIが無いのは何故..?

