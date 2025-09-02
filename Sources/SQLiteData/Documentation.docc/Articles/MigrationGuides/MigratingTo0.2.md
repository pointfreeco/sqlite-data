# Migrating to 0.2

Update your code to make use of powerful new querying capabilities.

## Overview

SQLiteData is under constant development, and we are always looking for ways to
simplify the library, and make it more powerful. As such, we often need to deprecate certain APIs
in favor of newer ones. We recommend people update their code as quickly as possible to the newest
APIs, and these guides contain tips to do so.

* [@FetchAll, @FetchOne, @Fetch](#)
* [fetchAll, fetchOne, fetch: soft-deprecated](#)
* [Avoiding the cost of macros](#)

## @FetchAll, @FetchOne, @Fetch

SQLiteData 0.2.0 comes with 3 brand new property wrappers that largely replace the need for
SwiftData and its `@Query` macro. In 0.1.0, one would perform queries as either a hard coded SQL
string:

```swift
@SharedReader(.fetchAll(sql: "SELECT * FROM reminders WHERE isCompleted ORDER BY title"))
var completedReminders: [Reminder]
```

Or by defining a ``FetchKeyRequest`` conformance to perform a query using GRDB's query builder:

```swift
struct CompletedReminders: FetchKeyRequest {
  func fetch(_ db: Database) throws -> [Reminder] {
    Reminder.all()
      .where(Column("isCompleted"))
      .order(Column("title"))
  }
}

@SharedReader(.fetch(CompletedReminders()))
var completedReminders
```

Each of these are cumbersome, and version 0.2.0 of SQLiteData fixes things thanks to our newly
released [StructuredQueries][] library. You can now describe the query for your data in a type-safe
manner, and directly inline:

```swift
@FetchAll(Reminder.where(\.isCompleted).order(by: \.title))
var completedReminders: [Reminder]
```

Read <doc:Fetching> for more information on how to use these new property wrappers.

[StructuredQueries]: http://github.com/pointfreeco/swift-structured-queries

## fetchAll, fetchOne, fetch: soft-deprecated

The [`.fetchAll`](<doc:Sharing/SharedReaderKey/fetchAll(sql:arguments:database:)>),
[`.fetchOne`](<doc:Sharing/SharedReaderKey/fetchOne(sql:arguments:database:)>),
and [`.fetch`](<doc:Sharing/SharedReaderKey/fetch(_:database:)>) APIs have been soft-deprecated
in favor of the more modern tools described above and in <doc:Fetching>. They will be hard
deprecated in a future release of SQLiteData, and removed in 1.0.

## Avoiding the cost of macros

SQLiteData introduces a macro in version 0.2.0 (in particular, the `@Table` macro), and
unfortunately macros currently come with an unfortunate cost in that you have to compile SwiftSyntax
from scratch, which can take time. If the cost of macros is too high for you, then you can depend
on the SQLiteDataCore module instead of the full SQLiteData module. This will give you access to
only a subset of tools provided by SQLiteData, but you will have access to all tools that were
available in version 0.1.0 of the library.
