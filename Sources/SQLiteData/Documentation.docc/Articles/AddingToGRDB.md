# Adding to an existing GRDB application

Learn how to add SQLiteData to an existing app that uses GRDB.

## Overview

[GRDB] is a powerful SQLite library for Swift applications, and it is what is used by SQLiteData
to interact with SQLite under the hood, such as performing queries and observing changes to the
database. If you have an existing application using GRDB, and would like to use the tools of this
library, such as [`@FetchAll`](<doc:FetchAll>), the SQL query builder, and
[CloudKit synchronization](<doc:CloudKit>), then there are a few steps you must take.

## Replace PersistableRecord and FetchableRecord with @Table

The `PersistableRecord` and `FetchableRecord` protocols in GRDB facilitate saving data to the
database and querying for data in the database. In SQLiteData, the `@Table` macro is responsible
for this functionality.

```diff
-struct Reminder: MutablePersistableRecord, Encodable {
+@Table("reminder")
+struct Reminder {
   …
 }
```

> Note: The `"reminder"` argument is provided to `@Table` due to a naming convention difference
> between SQLiteData and GRDB. More details below.

> Tip: For an incremental migration you can use all 3 of `PersistableRecord`, `FetchableRecord`
> _and_ `@Table`. That will allow you to use the query building tools from both GRDB and SQLiteData
> as you transition.

Once that is done you will be able to make use of the type-safe and schema-safe query building
tools of this library:

```swift
RemindersList
  .group(by: \.id)
  .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) }
  .select {
    ($0.title, $1.count())
  }
}
```

And you can use the various property wrappers for fetching data from the database in your views
and observable models:

```swift
@Observable
class RemindersModel {
  @ObservationIgnored
  @FetchAll(Reminder.order(by: \.isCompleted)) var reminders
}
```

> Note: Due to the fact that macros and property wrappers do not play nicely together, we are forced
> to use `@ObservationIgnored`. However, [`@FetchAll`](<doc:FetchAll>) handles all of its own
> observation internally and so this does not affect observation.

There are 3 main things to be aware of when applying `@Table` to an existing schema:

  * The `@Table` macro infers the name of the SQL table from the name of the type by lowercasing the
    first letter and attempting to pluralize the type. This differs from GRDB's naming conventions,
    which only lowercases the first letter of the type name. So, you will need to override `@Table`'s
    default behavior by providing a string argument to the macro:

    ```swift
    @Table("reminder")
    struct Reminder {
      // ...
    }
    @Table("remindersList")
    struct RemindersList {
      // ...
    }
    ```

  * If the column names of your SQLite table do not match the name of the fields in your Swift type,
    then you can provide custom names _via_ the `@Column` macro:

    ```swift
    @Table
    struct Reminder {
      let id: UUID
      var title = ""
      @Column("is_completed")
      var isCompleted = false
    }
    ```

  * If your tables use UUID then you will need to add an extra decoration to your Swift data type
    to make it compatible with SQLiteData. This is due to the fact that by default GRDB encodes UUIDs
    as bytes whereas SQLiteData encodes UUIDs as text. To keep this compatibility you will need to use
    `@Column(as:)` on any fields holding UUIDs:

    ```swift
    @Table
    struct Reminder {
      @Column(as: UUID.BytesRepresentation.self)
      let id: UUID
      // ...
    }
    ```

    And if your table has an optional UUID, then you will handle that similarly:

    ```swift
    @Table
    struct ChildReminder {
      @Column(as: UUID?.BytesRepresentation.self)
      let parentID: UUID?
      // ...
    }
    ```

## Non-optional primary keys

Some of your data types may have an optional primary key and a `didInsert` callback for setting the
ID after insert:

```swift
struct Reminder: MutablePersistableRecord, Encodable {
  var id: Int?
  var title = ""
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}
```

These can be updated to use non-optional types for the primary key, and the field can be bound as
an immutable `let`:

```swift
@Table
struct Reminder {
  let id: Int
  var title = ""
}
```

The `@Table` macro automatically generates a `Draft` type that can be used when you want to be
able to construct a value without the ID specified:

```swift
let draft = Reminder.Draft(title: "Get milk")
```

Then when this draft value is inserted its ID will be determined by the database:

```swift
try Reminder.insert {
  Reminder.Draft(title: "Get milk")
}
.execute(db)
```

You can even use a `RETURNING` clause to grab the ID of the freshly inserted record:

```swift
try Reminder.insert {
  Reminder.Draft(title: "Get milk")
}
.returning(\.id)
.fetchOne(db)
```

## CloudKit synchronization

The library's [CloudKit](<doc:CloudKit>) synchronization tools require that the tables being
synchronized have a primary key, and this is enforced through the `PrimaryKeyedTable` protocol.
The `@Table` macro automatically applies this protocol for you when your type has an `id` field,
but if you use a different name for your primary key you will need to use the `@Column` macro
to specify that:

```swift
@Table struct Reminder {
  @Column(primaryKey: true)
  let identifier: String
  …
}
```

The library further requires your tables use globally unique identifiers (such as UUID) for their 
primary keys, and in particular auto-incrementing integer IDs do _not_ work. You will need to 
migrate your tables to use UUIDs, see 
<doc:CloudKit#Preparing-an-existing-schema-for-synchronization> for more information.

[GRDB]: http://github.com/groue/GRDB.swift
