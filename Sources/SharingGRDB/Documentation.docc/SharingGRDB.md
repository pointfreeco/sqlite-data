# ``SharingGRDB``

## Overview

SharingGRDB is lightweight replacement for SwiftData and the `@Query` macro that deploys all the way
back to the iOS 13 generation of targets.

@Row {
  @Column {
    ```swift
    // SharingGRDB
    @SharedReader(.fetch(Item.all))
    var items
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Query
    var items: [Item]
    ```
  }
}

Both of the above examples fetch items from an external data store, and both are automatically
observed by SwiftUI so that views are recomputed when the external data changes, but SharingGRDB is
powered directly by SQLite using [Sharing](#What-is-Sharing) and [GRDB](#What-is-GRDB), and is
usable from UIKit, `@Observable` models, and more.

> Note: It is not required to write queries as a raw SQL string, and a query builder can be used 
> instead. For more information on SharingGRDB's querying capabilities, see <doc:Fetching>.

## Quick start

Before SharingGRDB's property wrappers can fetch data from SQLite, you need to provide---at
runtime---the default database it should use. This is typically done as early as possible in your
app's lifetime, like the app entry point in SwiftUI, and is analogous to configuring model storage
in SwiftData:

@Row {
  @Column {
    ```swift
    // SharingGRDB
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

This `defaultDatabase` connection is used implicitly by SharingGRDB's strategies, like 
 [`fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(sql:arguments:database:animation:)>):

```swift
@SharedReader(.fetch(Item.all))
var items
```

And you can access this database throughout your application in a way similar to how one accesses
a model context, via a property wrapper:

@Row {
  @Column {
    ```swift
    // SharingGRDB
    @Dependency(\.defaultDatabase) var database
    
    try database.write { db in
      let newItem = Item(/* ... */)
      try Item.insert(newItem).execute(db)
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

> Note: For more information on how SharingGRDB compares to SwiftData, see
> <doc:ComparisonWithSwiftData>.

This is all you need to know to get started with SharingGRDB, but there's much more to learn. Read
the [articles](#Essentials) below to learn how to best utilize this library.

## SQLite knowledge required

SQLite is one of the 
 [most established and widely distributed](https://www.sqlite.org/mostdeployed.html) pieces of 
software in the history of software. Knowledge of SQLite is a great skill for any app developer to
have, and this library does not want to conceal it from you. So, we feel that to best wield this
library you should be familiar with the basics of SQLite, including schema design and normalization,
SQL queries, including joins and aggregates, and performance, including indices.

With some basic knowledge you can apply this library to your database schema in order to query
for data and keep your views up-to-date when data in the database changes. You can use GRDB's
[query builder][query-interface] APIs to query your database, or you can use raw SQL queries, 
along with all of the power that SQL has to offer.

[query-interface]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/queryinterface

## What is Sharing?

[Sharing](https://github.com/pointfreeco/swift-sharing) is a universal and extensible solution for
sharing your app's model data across features and with external systems, such as user defaults,
the file system, and more. This library builds upon the tools from Sharing in order to allow for
the [fetching](<doc:Fetching>) and [observing](<doc:Observing>) of data in a SQLite database.

This is all you need to know about Sharing to hit the ground running with SharingGRDB, but it only
scratches the surface of what the library makes possible. It can also act as a replacement to
SwiftUI's `@AppStorage` that works with UIKit and `@Observable` models, and can be integrated
with custom persistence strategies. To learn more, check out
[the documentation](https://swiftpackageindex.com/pointfreeco/swift-sharing/main/documentation/sharing/).

## What is GRDB?

[GRDB](https://github.com/groue/GRDB.swift) is a popular Swift interface to SQLite with a rich
feature set and
[extensive documentation](https://swiftpackageindex.com/groue/GRDB.swift/documentation/grdb).
This library leverages GRDB's' observation APIs to keep the `@SharedReader` property wrapper in
sync with the database and update SwiftUI views.

If you're already familiar with SQLite, GRDB provides thin APIs that can be leveraged with raw SQL
in short order. If you're new to SQLite, GRDB offers a great introduction to a highly portable
database engine. We recommend
([as does GRDB](https://github.com/groue/GRDB.swift?tab=readme-ov-file#documentation)) a familiarity
with SQLite to take full advantage of GRDB and SharingGRDB.

## Topics

### Essentials

- <doc:Fetching>
- <doc:Observing>
- <doc:PreparingDatabase>
- <doc:DynamicQueries>
- <doc:ComparisonWithSwiftData>

### Database configuration and access

- ``Dependencies/DependencyValues/defaultDatabase``

### Fetch strategies

- ``Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)``
- ``Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)``
- ``Sharing/SharedReaderKey/fetch(_:database:)-3qcpd``
