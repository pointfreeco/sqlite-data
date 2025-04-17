# ``StructuredQueriesGRDBCore``

The core functionality of interfacing Structured Queries with GRDB. This module is automatically
imported when you `import StructuredQueriesGRDB`.

## Overview

This library can be used to directly execute queries built using the [Structured Queries][sq-gh]
library and a [GRDB][grdb-gh] database.

While the `SharingGRDB` module provides tools to observe queries using the `@SharedReader` property
wrapper, you will also want to execute one-off queries directly, without Sharing's APIs, especially
when it comes to `INSERT`, `UPDATE`, and `DELETE` statements. This module extends Structured
Queries' `Statement` type with `execute`, `fetchAll`, `fetchOne`, and `fetchCount` methods that
execute the query on a given GRDB database.

```swift
@Table
struct Player {
  let id: Int
  var name = ""
  var score = 0
}

try #sql(
  """
  CREATE TABLE players (
    id INTEGER PRIMARY KEY,
    name TEXT,
    score INTEGER
  )
  """
)
.execute(db)

let players = Player
  .where { $0.score > 10 }
  .fetchAll(db)
// SELECT … FROM "players"
// WHERE "players"."score" > 10

let averageScore = try Player
  .select { $0.score.avg() }
  .fetchOne(db)
// SELECT avg("players"."score") FROM "players"
```

For more information on how to build queries, see the [Structured Queries documentation][sq-spi].

[sq-gh]: https://github.com/pointfreeco/swift-structured-queries
[sq-spi]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueries
[grdb-gh]: https://github.com/groue/GRDB.swift

## Topics

### Executing statements

- ``StructuredQueriesCore/Statement/execute(_:)``
- ``StructuredQueriesCore/Statement/fetchAll(_:)-4glz5``
- ``StructuredQueriesCore/Statement/fetchOne(_:)-3mdmq``
- ``StructuredQueriesCore/Statement/fetchCursor(_:)-5bk5y``
- ``StructuredQueriesCore/SelectStatement/fetchCount(_:)``

### Iterating over rows

- ``QueryCursor``

### Seeding data

- ``GRDB/Database/seed(_:)``
