# SharingGRDB

A fast, lightweight replacement for SwiftData, powered by SQL.

[![CI](https://github.com/pointfreeco/sharing-grdb/workflows/CI/badge.svg)](https://github.com/pointfreeco/sharing-grdb/actions?query=workflow%3ACI)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpointfreeco%2Fsharing-grdb%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/pointfreeco/sharing-grdb)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpointfreeco%2Fsharing-grdb%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/pointfreeco/sharing-grdb)

  * [Learn more](#Learn-more)
  * [Overview](#Overview)
  * [Demos](#Demos)
  * [Documentation](#Documentation)
  * [Installation](#Installation)
  * [Community](#Community)
  * [License](#License)

## Learn more

This library was motivated and designed over the course of many episodes on
[Point-Free](https://www.pointfree.co), a video series exploring advanced programming topics in the
Swift language, hosted by [Brandon Williams](https://twitter.com/mbrandonw) and
[Stephen Celis](https://twitter.com/stephencelis). To support the continued development of this
library, [subscribe today](https://www.pointfree.co/pricing).

<a href="https://www.pointfree.co/collections/sqlite/sharing-with-sqlite">
  <img alt="video poster image" src="https://d3rccdn33rt8ze.cloudfront.net/episodes/0309.jpeg" width="600">
</a>

## Overview

SharingGRDB is a [fast](#performance), lightweight replacement for SwiftData that deploys all the
way back to the iOS 13 generation of targets.

<table>
<tr>
<th>SharingGRDB</th>
<th>SwiftData</th>
</tr>
<tr valign=top>
<td width=415>
      
```swift
@SharedReader(.fetchAll(Item.all))
var items

@Table
struct Item {
  let id: Int
  var title = ""
  var isInStock = true
  var notes = ""
}
```

</td>
<td width=415>

```swift
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

</td>
</tr>
</table>

Both of the above examples fetch items from an external data store using Swift data types, and both
are automatically observed by SwiftUI so that views are recomputed when the external data changes,
but SharingGRDB is powered directly by SQLite using
[Sharing](https://github.com/pointfreeco/swift-sharing),
[StructuredQueries](https://github.com/pointfreeco/swift-structured-queries), and
[GRDB](https://github.com/groue/GRDB.swift), and is usable from UIKit, `@Observable` models, and
more.

For more information on SharingGRDB's querying capabilities, see
[Fetching model data][fetching-article].

## Quick start

Before SharingGRDB's property wrappers can fetch data from SQLite, you need to provide–at
runtime–the default database it should use. This is typically done as early as possible in your
app's lifetime, like the app entry point in SwiftUI, and is analogous to configuring model storage
in SwiftData:

<table>
<tr>
<th>SharingGRDB</th>
<th>SwiftData</th>
</tr>
<tr valign=top>
<td width=415>

```swift
@main
struct MyApp: App {
  init() {
    prepareDependencies {
      let db = try! DatabaseQueue(
        // Create/migrate a database 
        // connection
      )
      $0.defaultDatabase = db
    }
  }
  // ...
}
```

</td>
<td width=415>

```swift
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

</td>
</tr>
</table>

> [!NOTE]
> For more information on preparing a SQLite database, see
> [Preparing a SQLite database][preparing-db-article].

This `defaultDatabase` connection is used implicitly by SharingGRDB's strategies, like 
[`fetchAll`][fetchall-docs]:

```swift
@SharedReader(.fetchAll(Item.all))
var items: [Item]
```

And you can access this database throughout your application in a way similar to how one accesses
a model context, via a property wrapper:

<table>
<tr>
<th>SharingGRDB</th>
<th>SwiftData</th>
</tr>
<tr valign=top>
<td width=415>

```swift
@Dependency(\.defaultDatabase) 
var database
    
var newItem = 
try database.write { db in
  try Item.insert(Item(/* ... */))
    .execute(db))
}
```

</td>
<td width=415>

```swift
@Environment(\.modelContext) 
var modelContext
    
let newItem = Item(/* ... */)
modelContext.insert(newItem)
try modelContext.save()
```

</td>
</tr>
</table>

> [!NOTE]
> For more information on how SharingGRDB compares to SwiftData, see
> [Comparison with SwiftData][comparison-swiftdata-article].

This is all you need to know to get started with SharingGRDB, but there's much more to learn. Read
the [articles][articles] below to learn how to best utilize this library:

  * [Fetching model data][fetching-article]
  * [Observing changes to model data][observing-article]
  * [Preparing a SQLite database][preparing-db-article]
  * [Dynamic queries][dynamic-queries-article]
  * [Comparison with SwiftData][comparison-swiftdata-article]

[observing-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/observing
[dynamic-queries-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/dynamicqueries
[articles]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb#Essentials
[comparison-swiftdata-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/comparisonwithswiftdata
[fetching-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/fetching
[preparing-db-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/preparingdatabase 
 [fetchall-docs]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/sharing/sharedreaderkey/fetchall(sql:arguments:database:animation:)

## Performance

SharingGRDB leverages high-performance decoding from
[StructuredQueries][StructuredQueries](https://github.com/pointfreeco/swift-structured-queries) to
turn fetched data into your Swift domain types, and has a performance profile similar to invoking
SQLite's C APIs directly.

See the following benchmarks from
[Lighter's performance test suite](https://github.com/Lighter-swift/PerformanceTestSuite) for a
taste of how it compares:

```
Orders.fetchAll                          setup    rampup   duration
  SQLite (Enlighter-generated)           0        0.144    7.183
  Lighter (1.4.10)                       0        0.164    8.059
  SharingGRDB (0.2.0)                    0        0.172    8.511
  GRDB (7.4.0, manual decoding)          0        0.376    18.819
  SQLite.swift (0.15.3, manual decoding) 0        0.564    27.994
  SQLite.swift (0.15.3, Codable)         0        0.863    43.261
  GRDB (7.4.0, Codable)                  0.002    1.07     53.326
```

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
[sharing-gh]: https://github.com/pointfreeco/swift-sharing
[structured-queries-gh] https://github.com/pointfreeco/swift-structured-queries
[grdb]: https://github.com/groue/GRDB.swift
[swift-nav-gh]: https://github.com/pointfreeco/swift-navigation
[observe-docs]: https://swiftpackageindex.com/pointfreeco/swift-navigation/main/documentation/swiftnavigation/objectivec/nsobject/observe(_:)-94oxy

## Demos

This repo comes with _lots_ of examples to demonstrate how to solve common and complex problems with
Sharing. Check out [this](./Examples) directory to see them all, including:

  * [Case Studies](./Examples/CaseStudies):
    A number of case studies demonstrating the built-in features of the library.

  * [SyncUps](./Examples/SyncUps): We also rebuilt Apple's [Scrumdinger][scrumdinger] demo
    application using modern, best practices for SwiftUI development, including using this library
    to query and persist state using SQLite.
    
  * [Reminders](./Examples/Reminders): A rebuild of Apple's [Reminders][reminders-app-store] app
    that uses a SQLite database to model the reminders, lists and tags. It features many advanced
    queries, such as searching, and stats aggregation.

[scrumdinger]: https://developer.apple.com/tutorials/app-dev-training/getting-started-with-scrumdinger
[reminders-app-store]: https://apps.apple.com/us/app/reminders/id1108187841

## Documentation

The documentation for releases and `main` are available here:

  * [`main`](https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdb/)
  * [0.1.x](https://swiftpackageindex.com/pointfreeco/sharing-grdb/~/documentation/sharinggrdb/)

## Installation

You can add SharingGRDB to an Xcode project by adding it to your project as a package.

> https://github.com/pointfreeco/sharing-grdb

If you want to use SharingGRDB in a [SwiftPM](https://swift.org/package-manager/) project, it's as
simple as adding it to your `Package.swift`:

``` swift
dependencies: [
  .package(url: "https://github.com/pointfreeco/sharing-grdb", from: "0.1.0")
]
```

And then adding the product to any target that needs access to the library:

```swift
.product(name: "SharingGRDB", package: "sharing-grdb"),
```

## Community

If you want to discuss this library or have a question about how to use it to solve a particular
problem, there are a number of places you can discuss with fellow
[Point-Free](http://www.pointfree.co) enthusiasts:

  * For long-form discussions, we recommend the
    [discussions](http://github.com/pointfreeco/sharing-grdb/discussions) tab of this repo.

  * For casual chat, we recommend the
    [Point-Free Community Slack](http://www.pointfree.co/slack-invite).

## License

This library is released under the MIT license. See [LICENSE](LICENSE) for details.
