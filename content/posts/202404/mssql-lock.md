---
title: "Azure SQL Databaseで行ロックの挙動を調べてみる"
date: 2024-04-26T09:07:30+09:00
slug: 2024-04-26-mssql-lock
type: posts
draft: true
categories:
  - computer
tags:
  - azure
  - mssql
---

Azure SQL DatabaseやSQL Serverを利用したシステムを作るとき、
同じレコードを複数のプロセスが同時に更新しようとしたとき、
うまく排他制御や競合解決をしなければ更新データが紛失する可能性があります。

例えば2つのアプリから同時に1つのレコードにある値をインクリメントしたい場合、
Amountの初期値が0であれば、2つのアプリから1回ずつインクリメントしたので
結果はAmount = 2になるはずですが、
トランザクション分離レベルが Read Committedであれば、下図のようにAmount = 1になってしまいます。
![alt](../img/concurrency.png)

これがもし注文システムであり、Amount = 在庫数であったならば、
在庫数が最後の1個で、複数のユーザーが同時に同じ商品を購入したとき、
在庫数が足りないにもかかわらず、両方のユーザーが注文できてしまうことになります。

こういうことを防止するために、DBMSには排他制御や競合解決という概念があって、
MySQLやPostgresなどでは、 `更新ロック(select for update)` で防ぐことが一般的かと思います。

一方、Azure SQL DatabaseやSQL Serverでは `select for update` の構文は直接的には存在せず、
トランザクションを貼れば行がロックされる というような情報があったり、
何が正しいのかよくわからなかったので、挙動を調査してみます。

## ロック挙動の調べ方

ロックの挙動を調べるために、select、update、commitの操作、各状態でのロック情報の表示
などを実現する必要があります。

まず、テーブルを作ります。

```sql
create table dbo.Items
(
    Id     int identity constraint PK_Items primary key,
    Amount int default 0 not null
)
```

そして、下記のことができるdotnetのconsoleアプリを作ってターミナルを2つ同時に立ち上げて
確認することとします。

- トランザクションの開始 (DatabaseFacade.BeginTransactionAsyncを使用)
- selectクエリで行取得
- ロック情報の表示
- Amount++
- updateクエリ発行
- ロック情報の表示
- commit

SQL Serverでロック情報は、下記sqlで表示できました。

```sql
SELECT resource_type, request_mode
FROM sys.dm_tran_locks
where resource_database_id = DB_ID('{db name}')
and resource_description <> ''
```

各ランタイムやパッケージのバージョンは以下です。

- dotnet core: 8.0.4
- EntityFrameworkCore: 9.0.0-preview.3.24172.4

## Read Commited Snapshotの場合
まず、トランザクション分離レベルがRead Commited Snapshotの場合の挙動を調べます。
Read Commited SnapshotはAzure SQL DatabaseやSQL Serverのデフォルトの分離レベルなので、
何も設定をいじらず、 `DatabaseFacade.BeginTransactionAsync` を使用してトランザクションを貼った場合は
Read Commited Snapshotになるかと思います。

### ロックの挙動の確認
まずは各クエリ発行前に、ロックがどのような状態になるのかを調査しました。

```
[LOCK INFO BEFORE SELECT]: []
ここでSelect
[READ DATA BEFORE UPDATE]: {"Id":1,"Amount":0}
[LOCK INFO BEFORE UPDATE]: []
ここでUpdate
[LOCK INFO BEFORE COMMIT]: [{"resource_type":"XACT","request_mode":"X"}]
ここでCommit
[LOCK INFO AFTER COMMIT]: []
[READ DATA AFTER COMMIT]: {"Id":1,"Amount":1}
```

このことから、Read Commited Snapshotでは下記のロック挙動があることがわかります。

- Selectでは何もロックをしない
- Updateを発行すると、Xロックを取る
- Commitをするとロックが解放される

#### db_tran_locks.request_modeについて

上記のrequest_modeでは `X` という表示がありますが、これがロックの種類です。
[こちらの記事](https://atmarkit.itmedia.co.jp/fdotnet/entwebapp/entwebapp09/entwebapp09_01.html)がわかりやすいので
少し抜粋します

- S: 共有ロック
  - 他のトランザクションに、データを読み出し中であることを知らせる
- X: 排他ロック
  - 他のトランザクションに、データを更新中であることを知らせる
  - Xをとっているときは、

### 競合解決の挙動の確認
次に、Read Commited Snapshotで、2つのトランザクションから同時に同じ行をselectし、更新してみます。

すべて、Amount = 0から初めて、2つのトランザクションから同時にインクリメントを行うので、Amount = 2となれば
正しく競合解決ができていることになります。

#### tx2がtx1のupdateより先にselectを行った場合
tx2は下図のように、tx1のupdateより前でselectを行うこととします

![alt](..//img/readcommited_select_q.png)

tx1
```
[LOCK INFO BEFORE SELECT]: []
ここでselect
[LOCK INFO AFTER SELECT]: []
[READ DATA BEFORE UPDATE]: {"Id":1,"Amount":0}
[LOCK INFO BEFORE UPDATE]: []
ここでupdate
[LOCK INFO AFTER UPDATE]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198654}]
[LOCK INFO BEFORE COMMIT]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198654},{"resource_type":"XACT","request_mode":"S","request_owner_id":198683}]
ここでcommit
[LOCK INFO AFTER COMMIT]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198683}]
[READ DATA AFTER COMMIT]: {"Id":1,"Amount":1}
```

tx2
```
[LOCK INFO BEFORE SELECT]: []
ここでselect
[LOCK INFO AFTER SELECT]: []
[READ DATA BEFORE UPDATE]: {"Id":1,"Amount":0}
[LOCK INFO BEFORE UPDATE]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198654}]
ここでtx1がcommit終わるまでロック待ちが発生
ここでupdate
[LOCK INFO AFTER UPDATE]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198683}]
[LOCK INFO BEFORE COMMIT]: [{"resource_type":"XACT","request_mode":"X","request_owner_id":198683}]
ここでcommit
[LOCK INFO AFTER COMMIT]: []
[READ DATA AFTER COMMIT]: {"Id":1,"Amount":1}
```

結果、以下のようなことがわかりました

- tx2はtx1がupdateする前であればselectができる
- tx2はtx1がupdateをした(Xロックを取った)あとでupdateしようとすれば、ロック待ちが発生する
- tx1がcommitを行えば、ロックが解放され、tx2がXロックを取得でき、updateを行える
- 最終的なamount = 1となり、tx1の更新した増加分が消失している

ということで、Read Commited Snapshotでtx2がtx1のupdate前にselectを行った場合、
最終結果は意図しないものになってしまうということがわかりました。

#### tx2がtx1のupdateより後にselectを行った場合

次に、tx2がtx1のupdateより後でselectを行った場合の挙動を見てみます

![alt](../img/readcommited_update_q.png)

結果、Amount = 1となり、こちらもtx1の更新分が消失してしまいました

## Serializedの場合
分離レベルがSerializedの場合はどうなるでしょうか

### ロックの挙動の確認

```
[LOCK INFO BEFORE SELECT]: []
ここでselect
[LOCK INFO AFTER SELECT]: [{"resource_type":"KEY","request_mode":"S","request_owner_id":226688},{"resource_type":"PAGE",
"request_mode":"IS","request_owner_id":226688}]
[READ DATA BEFORE UPDATE]: {"Id":1,"Amount":0}
[LOCK INFO BEFORE UPDATE]: [{"resource_type":"KEY","request_mode":"S","request_owner_id":226688},{"resource_type":"PAGE","request_mode":"IS","request_owner_id":226688}]
ここでupdate
[LOCK INFO AFTER UPDATE]: [{"resource_type":"KEY","request_mode":"X","request_owner_id":226688},{"resource_type":"XACT","request_mode":"X","request_owner_id":226688},{"resource_type":"PAGE","request_mode":"IX","request_owner_id":226688}]
[BEFORE COMMIT] waiting for any key...
[LOCK INFO BEFORE COMMIT]: [{"resource_type":"KEY","request_mode":"X","request_owner_id":226688},{"resource_type":"XACT","request_mode":"X","request_owner_id":226688},{"resource_type":"PAGE","request_mode":"IX","request_owner_id":226688}]
ここでcommit
[LOCK INFO AFTER COMMIT]: []
[READ DATA AFTER COMMIT]: {"Id":1,"Amount":1}
```