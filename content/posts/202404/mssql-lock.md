---
title: "SQL ServerとPostgreSQLでロストアップデートの挙動を調査する"
date: 2024-04-26T09:07:30+09:00
slug: 2024-04-26-mssql-lock
type: posts
draft: false
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

このように複数のシステムから同時に更新を行ったときに、更新データが消失してしまうことを[ロストアップデート](https://sakapon.wordpress.com/2011/07/11/lostupdate/)と呼びます。

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
- selectクエリで1行取得
- Amount++
- updateクエリで1行更新
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

したがって、SQL Serverを使用されている方は、更新がデフォルトのまま使っていると、ロストアップデートが発生する可能性があるということに留意する必要があるかと考えます。
(※楽観排他制御をしない場合)

## SQL Serverでロストアップデートを防ぐ
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

## PostgreSQL、Read Committed、tx2がtx1のupdateよりも前にselectする場合
つづいてPostgreSQLの場合です。

- tx1がselectをし、共有ロックをとる
- tx2がselectをし、共有ロックをとる
  - tx2のselectはブロックされない
- tx1がupdateをすると、排他ロックをとる
- tx1が排他ロックをとると、tx2がupdateで排他ロックをとれず、tx2のupdateがブロックされる
- tx1がcommitをすると、排他ロックがはずれ、tx2のupdateが動く
- tx2がcommitできる
- 最終的にAmount = 1となり、更新が消失する

## PostgreSQL、Read Committed、tx2がtx1のupdateよりも後にselectする場合

- tx1がselectをして共有ロック、updateをして排他ロックをとる
- tx2がselectをし、共有ロックをとる
  - tx2のselectはブロックされない
- tx1がcommitをし、tx2がupdateとcommitを実行できる
- 最終的にAmount = 1となり、tx1の更新が消失する

## PostgreSQL、Serialized、tx2がtx1のupdateよりも前にselectする場合

- tx1がselectをし、共有ロックをとる
- tx2がselectをし、共有ロックをとる
  - tx2のselectはブロックされない
- tx1がupdateをすると、排他ロックがとられ、tx2がupdateできなくなる
- tx1がcommitをすると、tx2がupdateできるようになる。しかし `could not serialize access due to concurrent update` となってupdateできない
- 最終的に Amount = 1となり、tx2の更新がエラーになって終わる

## PostgreSQL、Serialized、tx2がtx1のupdateよりも後にselectする場合

- tx1がselectをし、共有ロック、updateを行い、排他ロックを取得する
- tx2がselectを行い、共有ロックをとる
  - tx2のselectはブロックされない
- tx1がcommitをすると、tx2のupdateがエラーになる `could not serialize access due to concurrent update`
- 最終的に、Amount = 1となり、tx2がエラーになって終わる

### PostgreSQLのcould not serialize access due to concurrent updateについて

ドキュメントによると、PostgreSQLでserializedの場合、他のトランザクションによってupdateされたことを検知できるようです

> UPDATE、DELETE、SELECT FOR UPDATE、およびSELECT FOR SHAREコマンドでは、SELECTと同じように対象行を検索します。 これらのコマンドでは、トランザクションが開始された時点でコミットされている対象行のみを検出します。 しかし、その対象行は、検出されるまでに、同時実行中の他のトランザクションによって、既に更新（もしくは削除あるいはロック）されている可能性があります。 このような場合、シリアライザブルトランザクションは、最初の更新トランザクションが（それらがまだ進行中の場合）コミットもしくはロールバックするのを待ちます。 最初の更新処理がロールバックされると、その結果は無視され、シリアライザブルトランザクションでは元々検出した行の更新を続行することができます。 しかし、最初の更新処理がコミット（かつ、単にロックされるだけでなく、実際に行が更新または削除）されると、シリアライザブルトランザクションでは、以下のようなメッセージを出力してロールバックを行います。
> ERROR:  could not serialize access due to concurrent update
> https://www.postgresql.jp/document/8.3/html/transaction-iso.html

## PostgreSQLの挙動まとめ

ここまでの挙動をまとめると、下記になります。

|分離レベル|tx2がいつselectを行うか|結果|
|:---:|:---:|:---:|
|Read Committed|tx1のupdateより前|更新が消失する可能性あり|
|Read Committed|tx1のupdateより後|更新が消失する可能性あり|
|Serialized|tx1のupdateより前|tx2がcould not serialize access due to concurrent updateエラー|
|Serialzied|tx1のupdateより後|tx2がcould not serialize access due to concurrent updateエラー|

というような挙動になりました

## PostgreSQLでロストアップデートを防ぐ

PostgreSQLでロストアップデートを防ぐには `select for update` を使って、
更新対象の行をほかのトランザクションからselectできないようにします。

select for updateを使ったときの挙動は以下になります。

- tx1がselect for updateをすると、RowShareLockをとる
- tx2がselectしようとするが、ブロックされる
- tx1がupdateをすると、RowShareLockに加え、RowExclusiveLockをとる
- tx1がcommitをすると、tx2のselectが開始される
- tx2のupdateとcommitが通る
- 最終的にAmount = 2となり、更新が消失していない

## トランザクションをまたぐロストアップデート
ということで、ロストアップデートの可能性があるときは、`with(updlock)` や `select for update` を使って更新ロックを取得するのがよさそうです。

しかし、この場合でも防げないロストアップデートがあります。

例えば、updateを行うシステムが、管理画面など画面遷移があるものの場合、

1. HTTP GET(select)してデータを取得
2. 画面上で新しいデータを入力
3. HTTP POST (update)してデータを更新

のような流れになると思います。

その場合、selectをした画面とupdateをした画面では別のトランザクションなので、
select for updateをして更新ロックを取得したとしても、ロストアップデートが発生する恐れがあります。

![alt](../img/lostupdate_page.png)

## 楽観的排他制御

ではどうすればいいかというと、悲観的排他制御を行う場合は、DMBS以外のところ(アプリケーションレイヤーやredisなど)で自前の排他制御を実装するか、もしくは楽観的排他制御を使うことができます。

aspdotnetの例だと、timestamp型の行バージョン番号カラムを用意しておけば、EntityFrameworkが更新の競合を検知し、 `DbUpdateConcurrencyException` をthrowしてくれます。

[コンカレンシーの競合の処理](https://learn.microsoft.com/ja-jp/ef/core/saving/concurrency?tabs=data-annotations)

PostgreSQLの場合は、`xmin` というシステムカラムが行バージョン番号として用いれそうです (未検証)

[Concurrency Tokens](https://www.npgsql.org/efcore/modeling/concurrency.html?tabs=data-annotations) 

楽観的排他制御であれば、先勝ちにはなってしまいますが、更新が競合したときは確実にエラーになるので、
意図せず更新が消失するような障害が起きにくくなるかと思います。

また、トランザクションをまたいで競合解決できるので、複数の画面を遷移するような場合でも競合解決ができると思われます。

