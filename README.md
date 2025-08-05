> [!IMPORTANT]
> We are currently running a [public beta] to preview our upcoming CloudKit synchronization tools. Get all the details [here](https://www.pointfree.co/blog/posts/181-a-swiftdata-alternative-with-sqlite-cloudkit-public-beta) and let us know if you have any feedback!

[public beta]: https://github.com/pointfreeco/sharing-grdb/pull/112

# SharingGRDB

A [fast](#Performance), lightweight replacement for SwiftData, powered by SQL.

[![CI](https://github.com/pointfreeco/sharing-grdb/actions/workflows/ci.yml/badge.svg)](https://github.com/pointfreeco/sharing-grdb/actions/workflows/ci.yml)
[![Slack](https://img.shields.io/badge/slack-chat-informational.svg?label=Slack&logo=slack)](https://www.pointfree.co/slack-invite)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpointfreeco%2Fsharing-grdb%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/pointfreeco/sharing-grdb)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fpointfreeco%2Fsharing-grdb%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/pointfreeco/sharing-grdb)

  * [Learn more](#Learn-more)
  * [Overview](#Overview)
  * [Quick start](#Quick-start)
  * [Performance](#Performance)
  * [SQLite knowledge required](#SQLite-knowledge-required)
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

<a href="https://www.pointfree.co/collections/modern-persistence">
  <img alt="video poster image" src="https://d3rccdn33rt8ze.cloudfront.net/episodes/0325.jpeg" width="600">
</a>

## Overview

SharingGRDB is a [fast](#performance), lightweight replacement for SwiftData that deploys all the
way back to the iOS 13 generation of targets. To populate data from the database you can use
the `@FetchAll` property wrapper, which is similar to SwiftData's `@Query` macro:

<table>
<tr>
<th>SharingGRDB</th>
<th>SwiftData</th>
</tr>
<tr valign=top>
<td width=415>
      
```swift
@FetchAll
var items: [Item]

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
but SharingGRDB is powered directly by SQLite using [Sharing][], [StructuredQueries][], and
[GRDB][], and is usable from UIKit, `@Observable` models, and more.

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
[`@FetchAll`][fetchall-docs] and [`@FetchOne`][fetchone-docs], which are similar to SwiftData's
`@Query` macro, but more powerful:

<table>
<tr>
<th>SharingGRDB</th>
<th>SwiftData</th>
</tr>
<tr valign=top>
<td width=415>

```swift
@FetchAll
var items: [Item]

@FetchAll(Item.order(by: \.title))
var items

@FetchAll(Item.where(\.isInStock))
var items



@FetchOne(Item.count())
var inStockItemsCount = 0

```

</td>
<td width=415>

```swift
@Query
var items: [Item]

@Query(sort: [SortDescriptor(\.title)])
var items: [Item]

@Query(filter: #Predicate<Item> {
  $0.isInStock
})
var items: [Item]

// No @Query equivalent of counting
// entries in database without loading
// all entries.
```

</td>
</tr>
</table>

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
    
let newItem = Item(/* ... */)
try database.write { db in
  try Item.insert(newItem)
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

[observing-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/observing
[dynamic-queries-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/dynamicqueries
[articles]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore#Essentials
[comparison-swiftdata-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/comparisonwithswiftdata
[fetching-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/fetching
[preparing-db-article]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/preparingdatabase
[fetchall-docs]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/fetchall
[fetchone-docs]: https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/fetchone

## Performance

SharingGRDB leverages high-performance decoding from [StructuredQueries][] to turn fetched data into
your Swift domain types, and has a performance profile similar to invoking SQLite's C APIs directly.

See the following benchmarks against
[Lighter's performance test suite](https://github.com/Lighter-swift/PerformanceTestSuite) for a
taste of how it compares:

```
Orders.fetchAll                          setup    rampup   duration
  SQLite (generated by Enlighter 1.4.10) 0        0.144    7.183
  Lighter (1.4.10)                       0        0.164    8.059
  SharingGRDB (0.2.0)                    0        0.172    8.511
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
[StructuredQueries][] to build queries, either using its type-safe, discoverable
[query building APIs][], or using its `#sql` macro for writing [safe SQL strings][].

[Sharing]: https://github.com/pointfreeco/swift-sharing
[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries
[GRDB]: https://github.com/groue/GRDB.swift
[query building APIs]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueriescore
[safe SQL strings]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueriescore/safesqlstrings

## Demos

This repo comes with _lots_ of examples to demonstrate how to solve common and complex problems with
Sharing. Check out [this](./Examples) directory to see them all, including:

  * [Case Studies](./Examples/CaseStudies): A number of case studies demonstrating the built-in
    features of the library.

  * [SyncUps](./Examples/SyncUps): We also rebuilt Apple's [Scrumdinger][] demo application using
    modern, best practices for SwiftUI development, including using this library to query and
    persist state using SQLite.
    
  * [Reminders](./Examples/Reminders): A rebuild of Apple's [Reminders][reminders-app-store] app
    that uses a SQLite database to model the reminders, lists and tags. It features many advanced
    queries, such as searching, and stats aggregation.

[Scrumdinger]: https://developer.apple.com/tutorials/app-dev-training/getting-started-with-scrumdinger
[reminders-app-store]: https://apps.apple.com/us/app/reminders/id1108187841

## Documentation

The documentation for releases and `main` are available here:

  * [`main`](https://swiftpackageindex.com/pointfreeco/sharing-grdb/main/documentation/sharinggrdbcore/)
  * [0.x.x](https://swiftpackageindex.com/pointfreeco/sharing-grdb/~/documentation/sharinggrdbcore/)

## Installation

You can add SharingGRDB to an Xcode project by adding it to your project as a package…

> https://github.com/pointfreeco/sharing-grdb

…and adding the `SharingGRDB` product to your target.

> [!TIP]
> SharingGRDB's primary product is the `SharingGRDB` module, which includes all of the library's
> functionality, including the `@Fetch` family of property wrappers, the `@Table` macro, and tools
> for driving StructuredQueries using GRDB. This is the module that most library users should depend
> on.
>
> If you are a library author that wishes to extend SharingGRDB with additional functionality, you
> may want to depend on a different module:
>
>   * `SharingGRDBCore`: This product includes everything in `SharingGRDB` _except_ the macros
>     (`@Table`, `#sql`, _etc._). This module can be imported to extend SharingGRDB with additional
>     functionality without forcing the heavyweight dependency of SwiftSyntax on your users.
>   * `StructuredQueriesGRDB`: This product includes everything in `SharingGRDB` _except_ the
>     `@Fetch` family of property wrappers. It can be imported if you want to extend
>     StructuredQueries' GRDB driver but do not need access to observation tools provided by
>     Sharing.
>   * `StructuredQueriesGRDBCore`: This product includes everything in `StructuredQueriesGRDB`
>     _except_ the macros. This module can be imported to extend StructuredQueries' GRDB driver with
>     additional functionality without forcing the heavyweight dependency of SwiftSyntax on your
>     users.

If you want to use SharingGRDB in a [SwiftPM](https://swift.org/package-manager/) project, it's as
simple as adding it to your `Package.swift`:

``` swift
dependencies: [
  .package(url: "https://github.com/pointfreeco/sharing-grdb", from: "0.5.0")
]
```

And then adding the following product to any target that needs access to the library:

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
