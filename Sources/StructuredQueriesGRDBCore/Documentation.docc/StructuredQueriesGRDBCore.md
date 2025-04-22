# ``StructuredQueriesGRDBCore``

The core functionality of interfacing StructuredQueries with GRDB. This module is automatically
imported when you `import SharingGRDB` or `StructuredQueriesGRDB`.

## Overview

This library can be used to directly execute queries built using the [StructuredQueries][sq-gh]
library and a [GRDB][grdb-gh] database.

While the `SharingGRDB` module provides tools to observe queries using the `@FetchAll`, `@FetchOne`,
and `@Fetch` property wrappers, you will also want to execute one-off queries directly, especially
when it comes to `INSERT`, `UPDATE`, and `DELETE` statements. This module extends
StructuredQueries' `Statement` type with `execute`, `fetchAll`, `fetchOne`, and `fetchCount` methods
that execute the query on a given GRDB database.

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

For more information on how to build queries, see the [StructuredQueries documentation][sq-spi].

[sq-gh]: https://github.com/pointfreeco/swift-structured-queries
[sq-spi]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueriescore
[grdb-gh]: https://github.com/groue/GRDB.swift

## Topics

### Executing statements

- ``StructuredQueriesCore/Statement/execute(_:)``
- ``StructuredQueriesCore/Statement/fetchAll(_:)``
- ``StructuredQueriesCore/Statement/fetchOne(_:)``
- ``StructuredQueriesCore/Statement/fetchCursor(_:)``
- ``StructuredQueriesCore/SelectStatement/fetchCount(_:)``

### Iterating over rows

- ``QueryCursor``

### Seeding data

- ``GRDB/Database/seed(_:)``
