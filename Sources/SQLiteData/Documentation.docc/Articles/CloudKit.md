# Getting started with CloudKit

Learn how to seamlessly add CloudKit synchronization to your SQLiteData application.

## Overview

SQLiteData allows you to seamlessly synchronize your SQLite database with CloudKit. After a few
steps to set up your project and a ``SyncEngine``, your database can be automatically synchronized
to CloudKit. However, distributing your app's schema across many devices is an impactful decision
to make, and so an abundance of care must be taken to make sure all devices remain consistent
and capable of communicating with each other. Please read the documentation closely and thoroughly
to make sure you understand how to best prepare your app for cloud synchronization.

  - [Setting up your project](#Setting-up-your-project)
  - [Setting up a SyncEngine](#Setting-up-a-SyncEngine)
  - [Designing your schema with synchronization in mind](#Designing-your-schema-with-synchronization-in-mind)
    - [Globally unique primary keys](#Globally-unique-primary-keys)
    - [Primary keys on every table](#Primary-keys-on-every-table)
    - [Foreign key relationships](#Foreign-key-relationships)
    - [Uniqueness constraints](#Uniqueness-constraints)
    - [Avoid reserved CloudKit keywords](#Avoid-reserved-CloudKit-keywords)
  - [Backwards compatible migrations](#Backwards-compatible-migrations)
    - [Adding tables](#Adding-tables)
    - [Adding columns](#Adding-columns)
    - [Disallowed migrations](#Disallowed-migrations)
  - [Record conflicts](#Record-conflicts)
  - [Sharing records with other iCloud users](#Sharing-records-with-other-iCloud-users)
  - [Assets](#Assets)
  - [Accessing CloudKit metadata](#Accessing-CloudKit-metadata)
  - [Unit testing and Xcode previews](#Unit-testing-and-Xcode-previews)
  - [Preparing an existing schema for synchronization](#Preparing-an-existing-schema-for-synchronization)
  - [Tips and tricks](#Tips-and-tricks)
    - [Updating triggers to be compatible with synchronization](#Updating-triggers-to-be-compatible-with-synchronization)
    - [Developing in the simulator](#Developing-in-the-simulator)

## Setting up your project

The steps to set up your SQLiteData project for CloudKit synchronization are the
[same for setting up][setup-cloudkit-apple] any other kind of project for CloudKit:

  * Follow the [Configuring iCloud services] guide for enabling iCloud entitlements in your project.
  * Follow the [Configuring background execution modes] guide for adding the "Background Modes"
    capability to your project and turning on "Remote notifications".
  * If you want to enable sharing of records with other iCloud users, be sure to add a
    `CKSharingSupported` key to your Info.plist with a value of `true`. This is subtly documented
    in [Apple's documentation for sharing].
  * Once you are ready to deploy your app be sure to read Apple's documentation on
    [Deploying an iCloud Container’s Schema].

With those steps completed, you are ready to configure a ``SyncEngine`` that will facilitate
synchronizing your database to and from CloudKit.

[Deploying an iCloud Container’s Schema]: https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema
[Apple's documentation for sharing]: https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users#Create-and-Share-a-Topic
[setup-cloudkit-apple]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices#Add-the-iCloud-and-Background-Modes-capabilities
[Configuring iCloud services]: https://developer.apple.com/documentation/Xcode/configuring-icloud-services
[Configuring background execution modes]: https://developer.apple.com/documentation/Xcode/configuring-background-execution-modes

## Setting up a SyncEngine

The foundational tool used to synchronize your SQLite database to CloudKit is a ``SyncEngine``.
This is a wrapper around CloudKit's `CKSyncEngine` and performs all the necessary work to listen
for changes in your database to play them back to CloudKit, and listen for changes in CloudKit to
play them back to SQLite.

Before constructing a ``SyncEngine`` you must have already created and migrated your app's local
SQLite database as detailed in <doc:PreparingDatabase>. Immediately after that is done in the
`prepareDependencies` of the entry point of your app you will override the
``Dependencies/DependencyValues/defaultSyncEngine`` dependency with a sync engine that specifies
the database to synchronize, as well as the tables you want to synchronize:

```swift
@main
struct MyApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        for: $0.defaultDatabase,
        tables: RemindersList.self, Reminder.self
      )
    }
  }

  // ...
}
```

The `SyncEngine`
[initializer](<doc:SyncEngine/init(for:tables:privateTables:containerIdentifier:defaultZone:startImmediately:delegate:logger:)>)
has more options you may be interested in configuring.

> Important: You must explicitly provide all tables that you want to synchronize. We do this so that
> you can have the option of having some local tables that are not synchronized to CloudKit, such as
> full-text search indices, cached data, etc.

Once this work is done the app should work exactly as it did before, but now any changes made
to the database will be synchronized to CloudKit. You will still interact with your local SQLite
database the same way you always have. You can use ``FetchAll`` to fetch data to be used in a view
or `@Observable` model, and you can use the `defaultDatabase` dependency to write to the database.

There is one additional step you can optionally take if you want to gain access to the underlying
CloudKit metadata that is stored by the library. When constructing the connection to your database
you can use the `prepareDatabase` method on `Configuration` to attach the metadatabase:

```swift
func appDatabase() -> any DatabaseWriter {
  var configuration = Configuration()
  configuration.prepareDatabase { db in
    try db.attachMetadatabase()
    …
  }
}
```

This will allow you to query the ``SyncMetadata`` table, which gives you access to the `CKRecord`
stored for each of your records, as well as the `CKShare` for any shared records.

See the ``GRDB/Database/attachMetadatabase(containerIdentifier:)`` for more information, as well
as <doc:CloudKit#Accessing-CloudKit-metadata> below.

## Designing your schema with synchronization in mind

Distributing your app's schema across many devices is a big decision to make for your app, and
care must be taken. It is not true that you can simply take any existing schema, add a
``SyncEngine`` to it, and have it magically synchronize data across all devices and across all
versions of your app. There are a number of principles to keep in mind while designing and evolving
your schema to make sure every device can synchronize changes to every other device, no matter the
version.

#### Globally unique primary keys

> TL;DR: Primary keys must be globally unique identifiers, such as UUID, and cannot be an
> autoincrementing integer. Further, a `NOT NULL` constraint must be specified with an
> `ON CONFLICT REPLACE` action.

Primary keys are an important concept in SQL schema design, and SQLite makes it easy to add a
primary key by using an `AUTOINCREMENT` integer. This makes it so that newly inserted rows get
a unique ID by simply adding 1 to the largest ID in the table. However, that does not play nicely
with distributed schemas. That would make it possible for two devices to create a record with
`id: 1`, and when those records synchronize there would be an irreconcilable conflict.

For this reason, primary keys in SQLite tables should be _globally_ unique, such as a UUID. The
easiest way to do this is to store your table's ID in a `TEXT` column, adding a
default with a freshly generated UUID, and further adding a `ON CONFLICT REPLACE` constraint:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  …
)
```

> Tip: The `ON CONFLICT REPLACE` clause must be placed directly after `NOT NULL`.

This allows you to insert a row with a NULL value for the primary key and SQLite will compute
the primary key from the default value specified. This kind of pattern is commonly used with the
`Draft` type generated for primary keyed tables:

```swift
try database.write { db in
  try Reminder.upsert {
    // ℹ️ Omitting 'id' allows the database to initialize it for you.
    Reminder.Draft(title: "Get milk")
  }
  .execute(db)
}
```

If you would like to use a unique identifier other than the `UUID` provided by Foundation, you can
conform your identifier type to ``IdentifierStringConvertible``. We still recommend using
`NOT NULL ON CONFLICT REPLACE` on your column, as well as a default, but the default will need
to be provided outside of SQLite. You can do this by registering a function in SQLite and calling
out to it for the default value of your column:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (customUUIDv7()),
  …
)
```

Registering custom database functions for ID generation also makes it possible to generate
deterministic IDs for tests, making it easier to test your queries.

> Important: The primary key of a row is encoded into the `recordName` of a `CKRecord`, along with
> the table name. There are [restrictions][CKRecord.ID] on the value of `recordName`:
>
> * It may only contain ASCII characters
> * It must be less than 255 characters
> * It must not begin with an underscore
>
> If your primary key violates any of these rules, a `DatabaseError` will be thrown with a message
> of ``SyncEngine/invalidRecordNameError``.

[CKRecord.ID]: https://developer.apple.com/documentation/cloudkit/ckrecord/id

#### Primary keys on every table

> TL;DR: Each synchronized table must have a single, non-compound primary key to aid in
> synchronization, even if it is not used by your app.

_Every_ table being synchronized must have a single primary key and cannot have compound primary
keys. This includes join tables that typically only have two foreign keys pointing to the two
tables they are joining. For example, a `ReminderTag` table that joins reminders to tags should be
designed like so:

```sql
CREATE TABLE "reminderTags" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
  "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
) STRICT
```

Note that the `id` column might not be needed for your application's logic, but it is necessary to
facilitate synchronizing to CloudKit.

#### Foreign key relationships

> TL;DR: Foreign key constraints can be enabled and you can use `ON DELETE` actions to
> cascade deletions.

Foreign keys are a SQL feature that allow one to express relationships between tables. This library
uses that information to correctly implement synchronization behavior, such as knowing what order
to syncrhonize records (parent first, then children), and knowing what associated records to
share when sharing a root record.

To express a foreign key relationship between tables you use the `REFERENCES` clause in the table's
schema, along with optional `ON DELETE` and `ON UPDATE` qualifiers:

```sql
CREATE TABLE "reminders"(
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "title" TEXT NOT NULL DEFAULT '',
  "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
) STRICT
```

> Tip: See SQLite's documentation on [foreign keys](https://sqlite.org/foreignkeys.html) for more information. 

SQLiteData can synchronize many-to-one and many-to-many relationships to CloudKit,
and you can enforce foreign key constraints in your database connection. While it is possible for
the sync engine to receive records in an order that could cause a foreign key constraint failure,
such as receiving a child record before its parent, the sync engine will cache the child record
until the parent record has been synchronized, at which point the child record will also be
synchronized.

Currently the only actions supported for `ON DELETE` are `CASCADE`, `SET NULL` and `SET DEFAULT`.
In particular, `RESTRICT` and `NO ACTION` are not supported, and if you try to use those actions
in your schema an error will be thrown when constructing ``SyncEngine``.

#### Uniqueness constraints

> TL;DR: SQLite tables cannot have `UNIQUE` constraints on their columns in order to allow
> for distributed creation of records.

Tables with unique constraints on their columns, other than on the primary key, cannot be
synchronized. As an example, suppose you have a `Tag` table with a unique constraint on the
`title` column. It is not clear how the application should handle if two different devices create
a tag with the title "Family" at the same time. When the two devices synchronize their data
they will have a conflict on the uniqueness constraint, but it would not be correct to
discard one of the tags.

For this reason uniqueness constraints are not allowed in schemas, and this will be validated
when a ``SyncEngine`` is first created. If a uniqueness constraint is detected an error will be
thrown.

Sometimes it is possible to make the column that you want to be unique into the primary key of
your table. For example, if you wanted to associate a `RemindersListAsset` type to a
`RemindersList` type, you can make the primary key of the former also act as the foreign key:

```swift
@Table
struct RemindersListAsset {
  @Column(primaryKey: true)
  let remindersListID: RemindersList.ID
  let image: Data
}
```

This will make it so that at least one asset can be associated with a reminders list.

#### Avoid reserved CloudKit keywords

In the process of sending data from your database to CloudKit, the library turns rows into
`CKRecord`s, which is loosely a `[String: Any]` dictionary. However, certain key names are used
internally by CloudKit and are reserved for their use only. This means those keys cannot be used
as field names in your Swift data types or SQLite tables.

While Apple has not published an exhaustive list of reserved keywords, the following should cover
most known cases:

* `creationDate`
* `creatorUserRecordID`
* `etag`
* `lastModifiedUserRecordID`
* `modificationDate`
* `modifiedByDevice`
* `recordChangeTag`
* `recordID`
* `recordType`

## Backwards compatible migrations

> TL;DR: Database migrations should be done carefully and with full backwards compatibility
> in mind in order to support multiple devices running with different schema versions.

Migrations of a distributed schema come with even more complications than what is mentioned above.
If you ship a 1.0 of your app, and then in 1.1 you add a column to a table, you will need to
contend with the fact that users of the 1.0 will be creating records without that column. This can
cause problems if your migration is not designed correctly.

#### Adding tables

Adding new tables to a schema is perfectly safe thing to do in a CloudKit application. If a record
from a device is synchronized to a device that does not have that table it will cache the record
for later use. Then, when a device updates to the newest version of the app and detects a new table
has been added to the schema, it will populate the table with the cached records it received.

#### Adding columns

> TL;DR: When adding columns to a table that has already been deployed to users' devices, you will
either need to make the column nullable, or a default value must be provided with an
`ON CONFLICT REPLACE` clause.

As an example, suppose the 1.0 of your app shipped a table for a reminders list:

```swift
@Table
struct RemindersList {
  let id: UUID
  var title = ""
}
```

…and you created the SQL table for this like so:

```sql
CREATE TABLE "remindersLists" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "title" TEXT NOT NULL DEFAULT ''
) STRICT
```

Next suppose in 1.1 you want to add a column to the `RemindersList` type:

```diff
 @Table
 struct RemindersList {
   let id: UUID
   var title = ""
+  var position = 0
 }
```

…with the corresponding SQL migration:

```sql
ALTER TABLE "remindersLists"
ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0
```

Unfortunately this schema is problematic for synchronization. When a device running the 1.0 of the
app creates a record, it will not have the `position` field. And when that synchronizes to devices
running the 1.1 of the app, the ``SyncEngine`` will attempt to run a query that is essentially this:

```sql
INSERT INTO "remindersLists"
("id", "title", "position")
VALUES
(NULL, 'Personal', NULL)
```

This will generate a SQL error because the "position" column was declared as `NOT NULL`, and so this
record will not properly synchronize to devices running a newer version of the app.

The fix is to allow for inserting `NULL` values into `NOT NULL` columns by using the default of the
column. This can be done like so:

```sql
ALTER TABLE "remindersLists"
ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
```

> Important: The `ON CONFLICT REPLACE` clause must come directly after `NOT NULL` because it
> modifies that constraint.

Now when this query is executed:

```sql
INSERT INTO "remindersLists"
("id", "title", "position")
VALUES
(NULL, 'Personal', NULL)
```

…it will use 0 for the `position` column.

Sometimes it is not possible to specify a default for a newly added column. Suppose in version 1.2
of your app you add groups for reminders lists. This can be expressed as a new field on the
`RemindersList` type:

```diff
 @Table
 struct RemindersList {
   let id: UUID
   var title = ""
   var position = 0
+  var remindersListGroupID: RemindersListGroup.ID
 }
```

However, there is no sensible default that can be used for this schema. But, if you migrate your
table like so:

```sql
ALTER TABLE "remindersLists"
ADD COLUMN "remindersListGroupID" TEXT NOT NULL
REFERENCES "remindersListGroups"("id")
```

…then this will be problematic when older devices create reminders lists with no
`remindersListGroupID`. In this situation you have no choice but to make the field optional in
the type:

```diff
 @Table
 struct RemindersList {
   let id: UUID
   var title = ""
   var position = 0
-  var remindersListGroupID: RemindersListGroup.ID
+  var remindersListGroupID: RemindersListGroup.ID?
 }
```

And your migration will need to add a nullable column to the table:

```diff
 ALTER TABLE "remindersLists"
-ADD COLUMN "remindersListGroupID" TEXT NOT NULL
+ADD COLUMN "remindersListGroupID" TEXT
 REFERENCES "remindersListGroups"("id")
```

It may be disappointing to have to weaken your domain modeling to accommodate synchronization, but
that is the unfortunate reality of a distributed schema. In order to allow multiple versions of your
schema to be run on devices so that each device can create new records and edit existing records
that all devices can see, you will need to make some compromises.

#### Disallowed migrations

Certain kinds of migrations are simply not allowed when synchronizing your schema to multiple
devices. They are:

  * Removing columns
  * Renaming columns
  * Renaming tables

## Record conflicts

> TL;DR: Conflicts are handled automatically using a "last edit wins" strategy for each
> column of the record.

Conflicts between record edits will inevitably happen, and it's just a fact of dealing with
distributed data. The library handles conflicts automatically, but does so with a single strategy
that is currently not customizable. When a column is edited on a record, the library keeps track
of the timestamp for that particular column. When merging two conflicting records, each column
is analyzed, and the column that was most recently edited will win over the older data.

We do not employ more advanced merge conflict strategies, such as CRDT synchronization. We may
allow for these kinds of strategies in the future, but for now "field-wise last edit wins" is
the only strategy available and we feel serves the needs of the most number of people.

## Sharing records with other iCloud users

SQLiteData provides the tools necessary to share a record with another iCloud user so that
multiple users can collaborate on a single record. Sharing a record with another user brings
extra complications to an app that go beyond the existing complications of sharing a schema
across many devices. Please read the documentation carefully and thoroughly to understand
how to best situate your app for sharing that does not cause problems down the road.

See <doc:CloudKitSharing> for more information.

## Assets

> TL;DR: The library packages all `BLOB` columns in a table into `CKAsset`s and seamlessly decodes
> `CKAsset`s back into your tables. We recommend putting large binary blobs of data in their own
> tables.

All BLOB columns in a table are automatically turned into `CKAsset`s and synchronized to CloudKit.
This process is completely seamless and you do not have to take any explicit steps to support
assets.

However, general database design guidelines still apply. In particular, it is not recommended to
store large binary blobs in a table that is queried often. If done naively you may accidentally
large amounts of data into memory when querying your table, and further large binary blobs can
slow down SQLite's ability to efficiently access the rows in your tables.

It is recommended to hold binary blobs in a separate, but related, table. For example, if you are
building a reminders app that has lists, and you allow your users to assign an image to a list.
One way to model this is a table for the reminders list data, without the image, and then another
table for the image data associated with a reminders list. Further, the primary key of the cover
image table can be the foreign key pointing to the associated reminders list:

```swift
@Table
struct RemindersList: Identifiable {
  let id: UUID
  var title = ""
}

@Table
struct RemindersListCoverImage {
  @Column(primaryKey: true)
  let remindersListID: RemindersList.ID
  var image: Data
}
/*
CREATE TABLE "remindersListCoverImages" (
  "remindersListID" TEXT PRIMARY KEY NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
  "image" BLOB NOT NULL
)
*/
```

This allows you to efficiently query `RemindersList` while still allowing you to load the image
data for a list when you need it.

## Accessing CloudKit metadata

While the library tries to make CloudKit synchronization as seamless and hidden as possible,
there are times you will need to access the underlying CloudKit types for your tables and records.
The ``SyncMetadata`` table is the central place where this data is stored, and it is publicly
exposed for you to query it in whichever way you want.

> Important: In order to query the `SyncMetadata` table from your database connection you will need
to attach the metadatabase to your database connection. This can be done with the
``GRDB/Database/attachMetadatabase(containerIdentifier:)`` method defined on `Database`. See
<doc:CloudKit#Setting-up-a-SyncEngine> for more information on how to do this.

With that done you can use the ``StructuredQueriesCore/PrimaryKeyedTable/syncMetadataID`` property
to construct a SQL query for fetching the metadata associated with one of your records.

For example, if you want to retrieve the `CKRecord` that is associated with a particular row in
one of your tables, say a reminder, then you can use ``SyncMetadata/lastKnownServerRecord`` to
retrieve the `CKRecord` and then invoke a CloudKit database function to retrieve all of the details:

```swift
let lastKnownServerRecord = try database.read { db in
  try SyncMetadata
    .find(remindersList.syncMetadataID)
    .select(\.lastKnownServerRecord)
    .fetchOne(db)
    ?? nil
}
guard let lastKnownServerRecord
else { return }

let ckRecord = try await container.privateCloudDatabase
  .record(for: lastKnownServerRecord.recordID)
```

> Important: In the above snippet we are explicitly using `privateCloudDatabase`, but that is
> only appropriate if the user is the owner of the record. If the user is only a participant in
> a shared record, which can be determined from [SyncMetadata.share](<doc:SyncMetadata/share>),
> then you must use `sharedCloudDatabase` to fetch the newest record.

You are free to invoke any CloudKit functions you want with the `CKRecord` retrieved from
``SyncMetadata``. Any changes made directly with CloudKit will be automatically synced to your
SQLite database by the ``SyncEngine``.

It is also possible to fetch the `CKShare` associated with a record if it has been shared, which
will give you access to the most current list of participants and permissions for the shared record:

```swift
let share = try database.read { db in
  try RemindersList
    .find(remindersList.syncMetadataID)
    .select(\.share)
    .fetchOne(db)
}
guard let share
else { return }

let ckRecord = try await container.sharedCloudDatabase
  .record(for: share.recordID)
```

> Important: In the above snippet we are using the `sharedCloudDatabase` and this is always
appropriate to use when fetching the details of a `CKShare` as they are always stored in the
shared database.

It is also possible to join the ``SyncMetadata`` table directly to your tables so that you can
select this additional information on a per-record basis. For example, if you want to select all
reminders lists, along with a boolean that determines if it is shared or not, you can do the
following:

```swift
@Selection struct Row {
  let remindersList: RemindersList
  let isShared: Bool
}

@FetchAll(
  RemindersList
    .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($1.id) }
    .select {
      Row.Columns(
        remindersList: $0,
        isShared: $1.isShared ?? false
      )
    }
)
var rows
```

Here we have used the ``StructuredQueriesCore/PrimaryKeyedTableDefinition/syncMetadataID`` helper
that is defined on all primary key tables so that we can join ``SyncMetadata`` to `RemindersList`.

<!--
## How SQLiteData handles distributed schema scenarios

todo: finish
-->

## Unit testing and Xcode previews

It is possible to run your features in tests and previews even when using the ``SyncEngine``. You
will need to prepare it for dependencies exactly as you do in the entry point of your app. This
can lead to some code duplication, and so you may want to extract that work to a mutating
`bootstrapDatabase` method on `DependencyValues` like so:

```swift
extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    defaultDatabase = try Reminders.appDatabase()
    defaultSyncEngine = try SyncEngine(
      for: defaultDatabase,
      tables: RemindersList.self,
      RemindersListAsset.self,
      Reminder.self,
      Tag.self,
      ReminderTag.self
    )
  }
}
```

Then in your app entry point you can use it like so:

```swift
@main
struct MyApp: App {
  init() {
    try! prepareDependencies {
      try! $0.bootstrapDatabase()
    }
  }

  // ...
}
```

In tests you can use it like so:

```swift
@Suite(.dependencies { try! $0.bootstrapDatabase() })
struct MySuite {
  // ...
}
```

And in previews you can use it like so:

```swift
#Preview {
  try! prepareDependencies {
    try! $0.bootstrapDatabase()
  }
  // ...
}
```

> Tip: If you configure your ``SyncEngine`` with a ``SyncEngineDelegate``, you can pass it to the
> bootstrap function for configuration:
>
> ```diff
>  extension DependencyValues {
>    mutating func bootstrapDatabase(
> +    syncEngineDelegate: (any SyncEngineDelegate)? = nil
>    ) throws {
>      defaultDatabase = try Reminders.appDatabase()
>      defaultSyncEngine = try SyncEngine(
>        for: defaultDatabase,
>        tables: // ...
> +      delegate: syncEngineDelegate
>      )
>    }
>  }
> ```

## Preparing an existing schema for synchronization

If you have an existing app deployed to the app store using SQLite, then you may have to perform
a migration on your schema to prepare it for synchronization. The most important requirement
detailed above in <doc:CloudKit#Designing-your-schema-with-synchronization-in-mind> is that
all tables _must_ have a primary key, and all primary keys must be globally unique identifiers 
such as UUID, and cannot be simple auto-incrementing integers.

The steps required to perform such a process are quite lengthy (the SQLite docs describe it in 
[12 parts]), and those steps are easy to get wrong, which can either result in the migration
failing or your app accidentally corrupting your user's data.

SQLiteData provides a tool called ``SyncEngine/migratePrimaryKeys(_:tables:uuid:)`` that 
makes it possible to perform this migration in just 2 steps:

  * Update your Swift data types (then used annotated with `@Table`) to use UUID identifiers instead
  of `Int`, and fix all of the resulting compiler errors in your features.
  * Create a new migration and invoke ``SyncEngine/migratePrimaryKeys(_:tables:uuid:)`` with the 
  database handle from your migration and a list of all of your tables:

    ```swift
    try SyncEngine.migratePrimaryKeys(
      db,
      tables: Reminder.self, RemindersList.self, Tag.self
    )
    ```

That will perform the many step process of migrating each table from integer-based primary keys
to UUIDs.

This migration tool tries to be conservative with its efforts so that if it ever detects a 
schema it does not know how to handle properly, it will throw an error. If this happens, then
you must migrate your tables manually using the introduces in <doc:ManuallyMigratingPrimaryKeys>.

## Tips and tricks

### Updating triggers to be compatible with synchronization

If you have triggers installed on your tables, then you may want to customize their definitions
to behave differently depending on whether a write is happening to your database from your own
code or from the sync engine. For example, if you have a trigger that refreshes an `updatedAt`
timestamp on a row when it is edited, it would not be appropriate to do that when the sync engine
updates a row from data received from CloudKit. But, if you have a trigger that updates a local
[FTS] index, then you would want to perform that work regardless if your app is updating the data
or CloudKit is updating the data.

[FTS]: https://sqlite.org/fts5.html

To customize this behavior you can use the ``SyncEngine/isSynchronizingChanges()`` SQL expression.
It represents a custom database function that is installed in your database connection, and it will
return true if the write to your database originates from the sync engine. You can use it in a
trigger like so:

```swift
#sql(
  """
  CREATE TEMPORARY TRIGGER "…"
  AFTER DELETE ON "…"
  FOR EACH ROW WHEN NOT \(SyncEngine.isSynchronizingChanges())
  BEGIN
    …
  END
  """
)
```

Or if you are using the trigger building tools from [StructuredQueries] you can use it like so:

[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries

```swift
Model.createTemporaryTrigger(
  after: .insert { new in
    // ...
  } when: { _ in
    !SyncEngine.isSynchronizingChanges()
  }
)
```

This will skip the trigger's action when the row is being updated due to data being synchronized
from CloudKit.

### Developing in the simulator

It is possible to develop your app with CloudKit synchronization using the iOS simulator, but
you must be aware that simulators do not support push notifications, and so changes do not
synchronize from CloudKit to simulator automatically. Sometimes you can simply close and re-open
the app to have the simulator sync with CloudKit, but the most certain way to force synchronization
is to kill the app and relaunch it fresh.
