# Fetching model data

Learn about the various tools for fetching data from a SQLite database.

## Overview

All data fetching happens by using the `@FetchAll`, `@FetchOne` or `@Fetch` property wrappers.
The primary difference between these choices is whether if you want to fetch a collection of
rows, or fetch a single row (e.g. an aggegrate computation), or if you want to execute multiple
queries in a single transaction.

* [@FetchAll](#)
* [@FetchOne](#)
* [@Fetch](#)


### FetchAll


----


The primary differences between these choices is whether you want
to build queries with [StructuredQueries][structured-queries-gh], specify your query as a raw SQL
string, or if you want to assemble your value from one or more queries using a raw database
connection.

  * [Querying with StructuredQueries](#Querying-with-Structured-Queries)
  * [Querying with SQL](#Querying-with-SQL)
  * [Querying with custom request](#Querying-with-a-custom-request)

[structured-queries-gh]: https://github.com/pointfreeco/swift-structured-queries

### Querying with StructuredQueries

[StructuredQueries][structured-queries-gh] is a library for building type-safe queries that safely
and performantly decode into Swift data types. To get access to these tools you must apply
the `@Table` macro to your data type that represents the table:

```swift
@Table
struct Item {
  let id: Int 
  var title = ""
  @Column(as: Date.ISO8601Representation.self)
  var createdAt: Date
}
```

> Note: The `@Column` macro determines how to store the date in SQLite, which does not have a native
> date data type. The `Date.ISO8601Representation` strategy stores dates as text formatted with the
> ISO-8601 standard.

Then you can use the various query builder APIs on `Item` to fetch items from the database. For 
example, to fetch all records from the table you can use  
[`fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(_:database:)>):

```swift
@SharedReader(.fetchAll(Item.all)
var items
```

And if you want to sort the results, you can do so with an ordering clause:

```swift
@SharedReader(.fetchAll(Item.order(by: \.title))
var items
```

Or, if you want to only compute an aggregate of the data in a table, such as the count of the rows,
you can do so using the 
[`fetchOne`](<doc:Sharing/SharedReaderKey/fetchOne(_:database:)>) key:

```swift
@SharedReader(.fetchOne(Item.count())) 
var itemsCount = 0
```

While StructuredQueries' builder is powerful, it is also stricter than SQLite, which will happily
coerce any data into any type, and some queries are more conveniently expressed through these
coercions. StructuredQueries should never get in your way, so rather than describe to the Swift
type system every explicit cast and coalesce, you can always embed SQL directly in a query using
the `#sql` macro:

```swift
@SharedReader(
  .fetchAll(
    Item.where { #sql("\($0.createdAt) > date('now', '-7 days')") }
  )
)
var items
```

The `#sql` macro will safely bind any input and even perform basic syntax validation.

You can even use `#sql` to write the entire query:

```swift
@SharedReader(
  #sql(
    """
    SELECT \(Item.columns) FROM \(Item.self)
    WHERE \(Item.createdAt) > date('now', '-7 days')
    """
  )
)
var items: [Item]
```

The choice is up to you for each query or query fragment. To learn more, see the
[StructuredQueries documentation][structured-queries-docs].

[structured-queries-gh]: https://github.com/pointfreeco/swift-structured-queries
[structured-queries-docs]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/main/documentation/structuredqueriescore/

### Querying with custom requests

It is also possible to execute multiple database queries to fetch data for your `@SharedReader`. 
This can be useful for performing several queries in a single database transaction:

Each instance of `@SharedReader` in a feature executes their queries in a separate
transaction. So, if we wanted to query for all in-stock items, as well as the count of all items
(in-stock plus out-of-stock) like so:

```swift
@SharedReader(.fetchOne(Item.count()))
var itemsCount = 0

@SharedReader(.fetchAll(Item.where(\.isInStock)))
var inStockItems
```

…this is technically 2 queries run in 2 separate database transactions.

Often this can be just fine, but if you have multiple queries that tend to change at the same
time (_e.g._, when items are created or deleted, `itemsCount` and `inStockItems` will change
at the same time), then you can bundle these two queries into a single transaction.

To do this, one simply defines a conformance to our ``FetchKeyRequest`` protocol, and in that
conformance one can use the builder tools to query the database:

```swift
struct Items: FetchKeyRequest {
  struct Value {
    var inStockItems: [Item] = []
    var itemsCount = 0
  }
  func fetch(_ db: Database) throws -> Value {
    try Value(
      inStockItems: Item.where(\.isInStock).fetchAll(db),
      itemsCount: Item.fetchCount(db)
    )
  }
}
```

Here we have defined a ``FetchKeyRequest/Value`` type inside the conformance that represents all the
data we want to query for in a single transaction, and then we can construct it and return it from
the ``FetchKeyRequest/fetch(_:)`` method.

With this conformance defined we can use 
[`fetch`](<doc:Sharing/SharedReaderKey/fetch(_:database:)>) key to execute the query specified by
the `Items` type, and we can access the `inStockItems` and `itemsCount` properties to get to the
queried data:

```swift
@SharedReader(.fetch(Items()) var items = Items.Value()
items.inStockItems  // [Item(/* ... */), /* ... */]
items.itemsCount    // 100
```

> Note: A default must be provided to `@SharedReader` since it is querying for a custom data type
> instead of a collection of data.

Typically the conformances to ``FetchKeyRequest`` can even be made private and nested inside
whatever type they are used in, such as SwiftUI view, `@Observable` model, or UIKit view controller.
The only time it needs to be made public is if it's shared amongst many features.

### Querying with raw SQL

SharingGRDB also comes with a more basic set of tools that work directly with GRDB. The primary 
reason you may want to use these tools and not the StructuredQueries tools is that they do not 
require a macro to use (such as `@Table` and `#sql`), and so do not incur the cost of compiling 
SwiftSyntax.

There is a version of [`fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)>) 
key that  takes a raw SQL string:

```swift
@SharedReader(.fetchAll(sql: "SELECT * FROM items")) var items: [Item]
```

As well as a [`fetchOne`](<doc:Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)>) key:

```swift
@SharedReader(.fetchOne(sql: "SELECT count(*) FROM items")) 
var itemsCount = 0
```

These APIs simply feed their data directly to GRDB's equivalent `Database` APIs, which means it is
up to you to safely bind arguments and avoid SQL injection. If you want to write SQL queries by
hand, consider using StructuredQueries' `#sql` macro, instead.

[structured-queries-gh]: https://github.com/pointfreeco/swift-structured-queries
