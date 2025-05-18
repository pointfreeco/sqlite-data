# Fetching model data

Learn about the various tools for fetching data from a SQLite database.

## Overview

All data fetching happens by using the `@FetchAll`, `@FetchOne`, or `@Fetch` property wrappers.
The primary difference between these choices is whether if you want to fetch a collection of
rows, or fetch a single row (_e.g._, an aggregate computation), or if you want to execute multiple
queries in a single transaction.

  * [`@FetchAll`](#FetchAll)
  * [`@FetchOne`](#FetchOne)
  * [`@Fetch`](#Fetch)

### @FetchAll

The [`@FetchAll`](<doc:FetchAll>) property wrapper allows you to fetch a collection of results from
your database using a SQL query. The query is created using our 
[StructuredQueries][structured-queries-gh] library, which can build type-safe queries that safely
and performantly decode into Swift data types.

To get access to these tools you must apply the `@Table` macro to your data type that represents 
your table:

```swift
@Table
struct Reminder {
  let id: Int 
  var title = ""
  @Column(as: Date.ISO8601Representation?.self)
  var dueAt: Date?
  var isCompleted = false
}
```

> Note: The `@Column` macro determines how to store the date in SQLite, which does not have a native
> date data type. The `Date.ISO8601Representation` strategy stores dates as text formatted with the
> ISO-8601 standard. See [Defining your schema] for more info.

[Defining your schema]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/main/documentation/structuredqueriescore/definingyourschema

With that done you can already fetch all records from the `Reminder` table in their default order by
simply doing:

```swift
@FetchAll var reminders: [Reminder]
```

If you want to execute a more complex query, such as one that sorts the results by the reminder's 
title, then you can use the various query building APIs on `Reminder`: 

```swift
@FetchAll(Reminder.order(by: \.title))
var reminders
```

Or if you want to only select the completed reminders, sorted by their titles in a descending 
fashion:

```swift
@FetchAll(
  Reminder.where(\.isCompleted).order { $0.title.desc() }
)
var completedReminders
```

This is only the basics of what you can do with the query building tools of this library. To
learn more, be sure to check out the [documentation][structured-queries-docs] of StructuredQueries.

You can even execute a SQL string to populate the data in your features:

```swift
@FetchAll(#sql("SELECT * FROM reminders where isCompleted ORDER BY title DESC"))
var completedReminders: [Reminder]
```

This uses the `#sql` macro for constructing [safe SQL strings][sq-safe-sql-strings]. You are 
automatically protected from SQL injection attacks, and it is even possible to use the static
description of your schema to prevent accidental typos:

```swift
@FetchAll(
  #sql(
    """
    SELECT \(Reminder.columns)
    FROM \(Reminder.self)
    WHERE \(Reminder.isCompleted)
    ORDER BY \(Reminder.title) DESC
    """
  )
)
var completedReminders: [Reminder]
```

These interpolations are completely safe to do because they are statically known at compile time,
and it will minimize your risk for typos. Be sure to read the [documentation][sq-safe-sql-strings]
of StructuredQueries to see more of what `#sql` is capable of.

It is also possible to join tables together and query for multiple pieces of data at once. For
example, suppose we have another table for lists of reminders, and each reminder belongs to
exactly one list:

```swift
@Table
struct Reminder {
  let id: Int 
  var title = ""
  @Column(as: Date.ISO8601Representation?.self)
  var dueAt: Date?
  var isCompleted = false
  var remindersListID: RemindersList.ID
}
@Table
struct RemindersList: Identifiable {
  let id: Int 
  var title = ""
}
```

And further suppose we have a feature that wants to load the title of every reminder, along with
the title of its associated list. Rather than loading all columns of all rows of both tables, which
is inefficient, we can select just the data we need. First we define a data type to hold just that
data, and decorate it with the `@Selection` macro:

```swift
@Selection
struct Record {
  let reminderTitle: String
  let remindersListTitle: String
}
```

And then we construct a query that joins the `Reminder` table to the `RemindersList` table and 
selects the titles from each table:

```swift
@FetchAll(
  Reminder
    .join(RemindersList.all) { $0.remindersListID.eq($1.id) }
    .select {
      Record.Columns(
        reminderTitle: $0.title, 
        remindersListTitle: $1.title
      )
    }
)
var records
```

This is a very efficient query that selects only the bare essentials of data that the feature
needs to do its job. This kind of query is a lot more cumbersome to perform in SwiftData because
you must construct a dedicated `FetchDescriptor` value and set its `propertiesToFetch`.

[sq-safe-sql-strings]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/~/documentation/structuredqueriescore/safesqlstrings
[structured-queries-gh]: https://github.com/pointfreeco/swift-structured-queries
[structured-queries-docs]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/main/documentation/structuredqueriescore/

### @FetchOne

The [`@FetchOne`](<doc:FetchOne>) property wrapper works similarly to `@FetchAll`, but fetches
only a single record from the database and you must provide a default for when no record is found.
This tool can be handy for computing aggregate data, such as the number of reminders in the
database:

```swift
@FetchOne(Reminder.count())
var remindersCount = 0
```

You can perform any query you want in `@FetchOne`, including "where" clauses:

```swift
@FetchOne(Reminder.where(\.isCompleted).count())
var completedRemindersCount = 0
```

You can use the `#sql` macro with `@FetchOne` to execute a safe SQL string:

```swift
@FetchOne(#sql("SELECT count(*) FROM reminders WHERE isCompleted"))
var completedRemindersCount = 0
```

### @Fetch

It is also possible to execute multiple database queries to fetch data for your features. This can
be useful for performing several queries in a single database transaction:

Each instance of `@FetchAll` in a feature executes their queries in a separate transaction. So, if
we wanted to query for all completed reminders, along with a total count of reminders (completed and
uncompleted), we could do so like this:

```swift
@FetchOne(Reminder.count())
var remindersCount = 0

@FetchAll(Reminder.where(\.isCompleted)))
var completedReminders
```

…this is technically 2 queries run in 2 separate database transactions.

Often this can be just fine, but if you have multiple queries that tend to change at the same time
(_e.g._, when reminders are created or deleted, `remindersCount` and `completedReminders` will
change at the same time), then you can bundle these two queries into a single transaction.

To do this, one simply defines a conformance to our ``FetchKeyRequest`` protocol, and in that
conformance one can use the builder tools to query the database:

```swift
struct Reminders: FetchKeyRequest {
  struct Value {
    var completedReminders: [Reminder] = []
    var remindersCount = 0
  }
  func fetch(_ db: Database) throws -> Value {
    try Value(
      completedReminders: Reminder.where(\.isCompleted).fetchAll(db),
      remindersCount: Reminder.fetchCount(db)
    )
  }
}
```

Here we have defined a ``FetchKeyRequest/Value`` type inside the conformance that represents all the
data we want to query for in a single transaction, and then we can construct it and return it from
the ``FetchKeyRequest/fetch(_:)`` method.

With this conformance defined we can use the 
[`@Fetch`](<doc:Fetch>) property wrapper to execute the query specified by
the `Reminders` type, and we can access the `completedReminders` and `remindersCount` properties 
to get to the queried data:

```swift
@Fetch(Reminders()) var reminders = Reminders.Value()
reminders.completedReminders  // [Reminder(/* ... */), /* ... */]
reminders.remindersCount      // 100
```

> Note: A default must be provided to `@Fetch` since it is querying for a custom data type
> instead of a collection of data.

Typically the conformances to ``FetchKeyRequest`` can even be made private and nested inside
whatever type they are used in, such as SwiftUI view, `@Observable` model, or UIKit view controller.
The only time it needs to be made public is if it's shared amongst many features.
