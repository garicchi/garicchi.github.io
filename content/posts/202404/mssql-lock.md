---
title: "SQL ServerとPostgreSQLで行ロックの挙動を調べてみる"
date: 2024-04-26T09:07:30+09:00
slug: 2024-04-26-mssql-lock
type: posts
draft: true
categories:
  - computer
tags:
  - azure
  - mssql
  - postgresql
---

DBMSを利用したシステムを作っていると、
同じレコードを複数のシステムが同時に更新しようとしたとき、
うまく排他制御や競合解決をしなければ更新データが紛失する可能性があります。

例えば2つのアプリから同時に1つのレコードにある値をインクリメントしたい場合、
Amountの初期値が0であれば、2つのアプリから1回ずつインクリメントしたので
結果はAmount = 2になるはずですが、
トランザクション分離レベルが Read Committedであれば、下図のようにAmount = 1になってしまいます。
![alt](../img/concurrency.png)

これがもし注文システムであり、Amount = 在庫数であったならば、
在庫数が最後の1個で、複数のユーザーが同時に同じ商品を購入したとき、
在庫数が足りないにもかかわらず、両方のユーザーが注文できてしまうことになります。

こういうことを防止するために、DBMSには排他制御や競合解決という概念がありますが、
DBMSによって挙動が異なったり、結構理解していないところがあったので、挙動を調査してみます。

## ロック挙動の調べ方

ロックの挙動を調べるために、select、update、commitの操作、各状態でのロック情報の表示
などを実現する必要があります。

まず、テーブルを作ります。
下記ではSQL Serverを例として示します。

```sql
create table dbo.Items
(
    Id     int identity constraint PK_Items primary key,
    Amount int default 0 not null
)
```

そして、下記のことができるdotnetのconsoleアプリを作ってターミナルを2つ同時に立ち上げて
確認することとします。
DBMSとの接続はEntity Framework Coreを使用することとします。

- トランザクションの開始 (DatabaseFacade.BeginTransactionAsyncを使用)
- selectクエリで行取得
- Amount++
- updateクエリで行更新
- commit

↑を2つのターミナル(tx1、tx2とする)から同時に実行

- Amountの更新が消失していないか調査
  - 正しく排他制御ができているならAmount = 2になるはず

各ランタイムやパッケージのバージョンは以下です。

- dotnet core: 8.0.4
- EntityFrameworkCore: 8.0.4
- SQL Server: 2019
- PostgreSQL: 16

なお、トランザクション分離レベルについては、Read CommittedとSerialziedについて調査することとします。

## SQL Server、Read Committed、tx2がtx1のupdateよりも前にselectする場合

DBMSはSQL Server、Isolation LevelはRead Committedで、
tx1がselectした後、updateをする前にtx2がselectした場合の挙動を確認してみます。

なぜRead Committedかというと、SQL Serverのデフォルトのトランザクション分離レベルだからです。

![alt](../img/readcommited_select_q.png)

- tx1がselect、tx2がselectをし、成功する
  - tx1、tx2が共有ロックをとる
  - tx2のselectはブロックされない
- tx1がupdateをすると排他ロックをとる
- tx1が排他ロックをとると、tx2がupdateをしてもブロックされる
- tx1がcommitをすると、tx1の排他ロックは解除され、tx2が排他ロックを取得し、updateクエリを発行できる
- tx2がcommitをすることができる
- 最終的にAmount = 1となり、tx1の更新がtx2に上書きされ、消失した

ということで、この条件の場合、2つのトランザクションが同時に発行されると、更新が消失する可能性があることがわかりました。

## SQL Server、Read Committed、tx2がtx1のupdateより後にselectする場合

次にtx1がselectした後、updateをした後にtx2がselectした場合の挙動を確認してみます。

![alt](../img/readcommited_update_q.png)

- tx1がselect、updateをし、排他ロックをとる
- tx2がselectをしようとして、ブロックされる
- tx1がcommitをすると、tx1の排他ロックが解除され、tx2のselectが動き始める
- tx2がupdateとcommitをすることができる
- 最終的にAmount = 2となり、正しく排他制御ができた

ということで、この条件の場合、2つのトランザクションが同時に発行されると、更新が消失しないことがわかりました。

## SQL Server、Serialized、tx2がtx1のupdateよりも前にselectする場合

つづいて、IsolationLevelをSerializedにした場合の挙動を見てみます。
なぜSerializedを見るかというと、[System.Transactions.TransactionScope](https://learn.microsoft.com/ja-jp/dotnet/api/system.transactions.transactionscope) のデフォルト分離レベルであり、TransactionScopeをデフォルトのまま使用しているときの挙動を確認できるからです。

- tx1がselect、tx2がselectをし、成功する
  - tx1、tx2が共有ロックをとる
  - tx2のselectはブロックされない
- tx1がupdateをしようとするが共有ロックがとられていて排他ロックをとれず、updateがブロックされる
- tx2がudpateをしようとすると、共有ロックがとられていて排他ロックをとれず、updateがブロックされる
- ここでDBMSによってデッドロックが検知され、tx2がエラーになる
- tx1は排他ロックをとることに成功し、commitできる
- 最終的にAmount = 1となり、tx1の更新だけ通り、tx2はデッドロックエラーになる

ということで、この条件では、デッドロックとなり、tx2だけエラーになりました。

MS公式ドキュメントを読むと、updateをするときに、共有ロックを排他ロックに変換するが、その時すでにほかのトランザクションから共有ロックがとられている場合、ブロックされるらしく、それと同じ挙動を確認できました。

> REPEATABLE READ または SERIALIZABLE のトランザクションは、データを読み取るときにリソースに共有 (S) ロックをかけます。その後、行を変更しますが、そのときにロックを排他 (X) ロックに変換する必要があります。 2 つのトランザクションが 1 つのリソースに対して共有 (S) ロックをかけデータを同時に更新する場合、一方のトランザクションは排他 (X) ロックへの変換を試みます。 一方のトランザクションの排他ロックは、もう一方のトランザクションの共有 (S) ロックとは両立しないので、共有ロックから排他ロックへの変換が待機状態になります。つまり、ロック待機となります。 もう一方のトランザクションも更新のために排他 (X) ロックの取得を試みます。 この場合、2 つのトランザクションが排他 (X) ロックへの変換を行っており、相手方のトランザクションが共有 (S) ロックを解除するのを待っている状態なので、デッドロックが発生します。
https://learn.microsoft.com/ja-jp/sql/relational-databases/sql-server-transaction-locking-and-row-versioning-guide?view=sql-server-ver16#update

## SQL Server、Serialized、tx2がtx1のupdateよりも後にselectする場合

続いて、同じようにtx2が後でselectをした場合の挙動を確認します。

- tx1はselectで共有ロックをとり、updateで排他ロックに変換する
- その後tx2がselectをしようとしても、排他ロックがとられているのでブロックされる
- tx1のcommitが成功すると、tx2のブロックが解除され、selectが動き出す
- tx2のcommitが通る
- 最終的にAmount = 2となり、正しく排他制御ができていることがわかる

ということで、この条件の場合、2つのトランザクションが同時に発行されると、更新が消失しないことがわかりました。

## SQL Serverの挙動まとめ

ここまでの挙動をまとめると、下記になります。

|分離レベル|tx2がいつselectを行うか|結果|
|:---:|:---:|:---:|
|Read Committed|tx1のupdateより前|更新が消失する可能性あり|
|Read Committed|tx1のupdateより後|正しく更新できる|
|Serialized|tx1のupdateより前|tx2がデッドロックエラー|
|Serialzied|tx1のupdateより後|正しく更新できる|

SQL Serverを使用したシステムを使用されている方は、おそらく分離レベル=ReadCommittedを使用されている場合が多いかと思いますし、TransactionScopeを使用されている方は分離レベル=Serializedを使用されている方が多いかと思います。

そしてほとんどの場合において、tx2のselectがtx1のupdateより後になることを保証していることはないかと思います。

したがって、SQL Serverを使用されている方は、更新がデフォルトのまま使っていると、更新が消失する可能性があるということに留意する必要があるかと考えます。
(※楽観排他制御をしない場合)

## SQL Serverで更新の消失を防ぐ
ではどのようにすれば更新の消失が防げるかというと、selectした行はcommitするまで他のトランザクションからselectできなくすればよいです。
これを更新ロックと呼び、MySQLやPostgreSQLでは `select for update` のようなSQLで実現できます。

ただSQL Serverには `select for update` はなく、[クエリヒント](https://learn.microsoft.com/ja-jp/sql/t-sql/queries/hints-transact-sql-query?view=sql-server-ver15)で更新ロックを実現します。

下記のような感じで `with(UPDLOCK)` を書きます

```sql
select * from Items with(UPDLOCK) where Id = 1
```

これで同じように実験をしてみると下記のような挙動になりました。

- tx1がselectを行い、更新ロックを取得する
- tx2がselectをしようとしたとき、更新ロックをとれず、ブロックされる
- tx1がupdateで更新ロックを排他ロックに変換する
- tx1がcommitしたら、排他ロックが解除され、tx2のselectが動き出す
- tx2がupdate、commitできる
- Amount = 2となり、正しい更新となる

ということで、SQL Serverで悲観的排他制御をするのであれば、 `with(UPDLOCK)` を使用するのがよいかと思われます。

