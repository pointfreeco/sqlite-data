# ``SQLiteData``

A fast, lightweight replacement for SwiftData, powered by SQL and supporting CloudKit
synchronization.

## Overview

SQLiteData is a [fast](#Performance), lightweight replacement for SwiftData, supporting CloudKit
synchronization (and even CloudKit sharing), built on top of the popular 
[GRDB](https://github.com/groue/GRDB.swift) library.

@Row {
  @Column {
    ```swift
    // SQLiteData
    @FetchAll
    var items: [Item]

    @Table
    struct Item {
      let id: UUID
      var title = ""
      var isInStock = true
      var notes = ""
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Query
    var items: [Item]

    @Model
    class Item {
      var title: String
      var isInStock: Bool
      var notes: String
      init(
        title: String = "",
        isInStock: Bool = true,
        notes: String = ""
      ) {
        self.title = title
        self.isInStock = isInStock
        self.notes = notes
      }
    }
    ```
  }
}

Both of the above examples fetch items from an external data store using Swift data types, and both
are automatically observed by SwiftUI so that views are recomputed when the external data changes,
but SQLiteData is powered directly by SQLite and is usable from anywhere, including UIKit,
`@Observable` models, and more.

> Note: For more information on SQLiteData's querying capabilities, see <doc:Fetching>.

## Quick start

Before SQLiteData's property wrappers can fetch data from SQLite, you need to provide---at
runtime---the default database it should use. This is typically done as early as possible in your
app's lifetime, like the app entry point in SwiftUI, and is analogous to configuring model storage
in SwiftData:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @main
    struct MyApp: App {
      init() {
        prepareDependencies {
          // Create/migrate a database connection
          let db = try! DatabaseQueue(/* ... */)
          $0.defaultDatabase = db
        }
      }
      // ...
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @main
    struct MyApp: App {
      let container = {
        // Create/configure a container
        try! ModelContainer(/* ... */)
      }()

      var body: some Scene {
        WindowGroup {
          ContentView()
            .modelContainer(container)
        }
      }
    }
    ```
  }
}

> Note: For more information on preparing a SQLite database, see <doc:PreparingDatabase>.

This `defaultDatabase` connection is used implicitly by SQLiteData's property wrappers, like
``FetchAll``, which are similar to SwiftData's `@Query` macro, but more powerful:

@Row {
  @Column {
    ```swift
    @FetchAll
    var items: [Item]

    @FetchAll(Item.order(by: \.title))
    var items

    @FetchAll(Item.where(\.isInStock))
    var items



   @FetchAll(Item.order(by: \.isInStock))
   var items

    @FetchOne(Item.count())
    var itemsCount = 0
    ```
  }
  @Column {
    ```swift
    @Query
    var items: [Item]

    @Query(sort: [SortDescriptor(\.title)])
    var items: [Item]

    @Query(filter: #Predicate<Item> {
      $0.isInStock
    })
    var items: [Item]

    // No @Query equivalent of ordering
    // by boolean column.

    // No @Query equivalent of counting
    // entries in database without loading
    // all entries.
    ```
  }
}

And you can access this database throughout your application in a way similar to how one accesses
a model context, via a property wrapper:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Dependency(\.defaultDatabase) var database

    try database.write { db in
      try Item.insert { Item(/* ... */) }
      .execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Environment(\.modelContext) var modelContext

    let newItem = Item(/* ... */)
    modelContext.insert(newItem)
    try modelContext.save()
    ```
  }
}

> Important: SQLiteData uses [GRDB](https://github.com/groue/GRDB.swift) under the hood for 
> interacting with SQLite, and you will use its tools for creating transactions for writing 
> to the database, such as the `database.write` method above.

For more information on how SQLiteData compares to SwiftData, see <doc:ComparisonWithSwiftData>.

Further, if you want to synchronize the local database to CloudKit so that it is available on
all your user's devices, simply configure a `SyncEngine` in the entry point of the app:

```swift
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
      $0.defaultSyncEngine = SyncEngine(
        for: $0.defaultDatabase,
        tables: /* ... */
      )
    }
  }
  // ...
}
```

> For more information on synchronizing the database to CloudKit and sharing records with iCloud
> users, see <doc:CloudKit>.

This is all you need to know to get started with SQLiteData, but there's much more to learn. Read
the [articles](#Essentials) below to learn how to best utilize this library.

## Performance

SQLiteData leverages high-performance decoding from
[StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) to turn fetched data
into your Swift domain types, and has a performance profile similar to invoking SQLite's C APIs
directly.

See the following benchmarks against
[Lighter's performance test suite](https://github.com/Lighter-swift/PerformanceTestSuite) for a
taste of how it compares:

```
Orders.fetchAll                           setup    rampup   duration
   SQLite (generated by Enlighter 1.4.10) 0        0.144    7.183
   Lighter (1.4.10)                       0        0.164    8.059
┌──────────────────────────────────────────────────────────────────┐
│  SQLiteData (1.0.0)                     0        0.172    8.511  │
└──────────────────────────────────────────────────────────────────┘
   GRDB (7.4.1, manual decoding)          0        0.376    18.819
   SQLite.swift (0.15.3, manual decoding) 0        0.564    27.994
   SQLite.swift (0.15.3, Codable)         0        0.863    43.261
   GRDB (7.4.1, Codable)                  0.002    1.07     53.326
```

## SQLite knowledge required

SQLite is one of the
[most established and widely distributed](https://www.sqlite.org/mostdeployed.html) pieces of
software in the history of software. Knowledge of SQLite is a great skill for any app developer to
have, and this library does not want to conceal it from you. So, we feel that to best wield this
library you should be familiar with the basics of SQLite, including schema design and normalization,
SQL queries, including joins and aggregates, and performance, including indices.

With some basic knowledge you can apply this library to your database schema in order to query
for data and keep your views up-to-date when data in the database changes, and you can use
[StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) to build queries,
either using its type-safe, discoverable query building APIs, or using its `#sql` macro for writing
safe SQL strings.

Further, this library is built on the popular and battle-tested 
[GRDB](https://github.com/groue/GRDB.swift) library for interacting with SQLite, such as executing 
queries and observing the database for changes.

## What is StructuredQueries?

[StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) is a library for
building SQL in a safe, expressive, and composable manner, and decoding results with high
performance. Learn more about designing schemas and building queries with the library by seeing its
[documentation](https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueriescore/).

SQLiteData contains an official StructuredQueries driver that connects it to SQLite _via_ GRDB,
though its query builder and decoder are general purpose tools that can interface with other
databases (MySQL, Postgres, _etc._) and database libraries.

## What is GRDB?

[GRDB](https://github.com/groue/GRDB.swift) is a popular Swift interface to SQLite with a rich
feature set and
[extensive documentation](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb). This
library leverages GRDB's observation APIs to keep the `@FetchAll`, `@FetchOne`, and `@Fetch`
property wrappers in sync with the database and update SwiftUI views.

If you're already familiar with SQLite, GRDB provides thin APIs that can be leveraged with raw SQL
in short order. If you're new to SQLite, GRDB offers a great introduction to a highly portable
database engine. We recommend
([as does GRDB](https://github.com/groue/GRDB.swift?tab=readme-ov-file#documentation)) a familiarity
with SQLite to take full advantage of GRDB and SQLiteData.

## Topics

### Essentials

- <doc:Fetching>
- <doc:Observing>
- <doc:PreparingDatabase>
- <doc:DynamicQueries>
- <doc:AddingToGRDB>
- <doc:ComparisonWithSwiftData>

### Database configuration and access

- ``defaultDatabase(path:configuration:)``
- ``GRDB/Database``
- ``Dependencies/DependencyValues/defaultDatabase``

### Querying model data

- ``StructuredQueriesCore/Statement``
- ``StructuredQueriesCore/SelectStatement``
- ``StructuredQueriesCore/Table``
- ``StructuredQueriesCore/PrimaryKeyedTable``
- ``QueryCursor``

### Observing model data

- ``FetchAll``
- ``FetchOne``
- ``Fetch``
- ``FetchSubscription``

### CloudKit synchronization and sharing

- <doc:CloudKit>
- <doc:CloudKitSharing>
- ``SyncEngine``
- ``SyncEngineDelegate``
- ``Dependencies/DependencyValues/defaultSyncEngine``
- ``IdentifierStringConvertible``
- ``SyncMetadata``
- ``StructuredQueriesCore/PrimaryKeyedTableDefinition/syncMetadataID``
- ``StructuredQueriesCore/PrimaryKeyedTableDefinition/hasMetadata(in:)``
- ``SharedRecord``
