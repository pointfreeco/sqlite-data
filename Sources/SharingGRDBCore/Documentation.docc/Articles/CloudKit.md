# CloudKit synchronization

Learn how to seamlessly add CloudKit synchronization to your SharingGRDB application.

## Overview

SharingGRDB allows you to seamlessly synchronize your SQLite database with CloudKit. After a few
steps to set up your project and a ``SyncEngine``, your database can be automatically synchronized
to CloudKit. However, distributing your app's schema across many devices is an impactful decision
to make, and so an abundance of care must be taken to make sure all devices remain consistent
and capable of communicating with each other. Please read the documentation closely and thoroughly
to make sure you understand how to best prepare your app for cloud synchronization.

  * [Setting up your project](#Setting-up-your-project)
  * [Setting up a SyncEngine](#Setting-up-a-SyncEngine)
  * [Designing your schema with synchronization in mind](#Designing-your-schema-with-synchronization-in-mind)
      * [Primary keys](#Primary-keys)
      * [Primary keys on every table](#Primary-keys-on-every-table)
      * [Foreign key relationships](#Foreign-key-relationships)
  * [Record conflicts](#Record-conflicts)
  * [Backwards compatible migrations](#Backwards-compatible-migrations)
      * [Adding tables](#Adding-tables)
      * [Adding columns](#Adding-columns)
      * [Disallowed migrations](#Disallowed-migrations)
  * [Sharing records with other iCloud users](#Sharing-records-with-other-iCloud-users)
  * [Assets](#Assets)
  * [Accessing CloudKit metadata](#Accessing-CloudKit-metadata)
  * [How SharingGRDB handles distributed schema scenarios](#How-SharingGRDB-handles-distributed-schema-scenarios)
  * [Unit testing and Xcode previews](#Unit-testing-and-Xcode-previews)
  * [Preparing an existing schema for synchronization](#Preparing-an-existing-schema-for-synchronization)
      * [Convert Int primary keys to UUID](#Convert-Int-primary-keys-to-UUID)
      * [Add primary key to all tables](#Add-primary-key-to-all-tables)
  * [Migrating from Swift Data to SharingGRDB](#Migrating-from-Swift-Data-to-SharingGRDB)
  * [Separating schema migrations from data migrations](#Separating-schema-migrations-from-data-migrations)
  * [Tips and tricks](#Tips-and-tricks)
      * [Updating triggers to be compatible with synchronization](#Updating-triggers-to-be-compatible-with-synchronization)
  * [Topics](#Topics)
      * [Go deeper](#Go-deeper)

## Setting up your project

The steps to set up your SharingGRDB project for CloudKit synchronization are the 
[same for setting up][setup-cloudkit-apple] any other kind of project for CloudKit:

  * Follow the [Configuring iCloud services] guide for enabling iCloud entitlements in your project.
  * Follow the [Configuring background execution modes] guide for adding the Background Modes
    capability to your project.
  * If you want to enable sharing of records with other iCloud users, be sure to add a 
    `CKSharingSupported` key to your Info.plist with a value of `true`. This is subtly documented 
    in [Apple's documentation for sharing].

With those steps completed, you are ready to configure a ``SyncEngine`` that will facilitate
synchronizing your database to and from CloudKit.

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
the CloudKit container to use, the database to synchronize, as well as the tables you want to
synchronize:

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
[initializer](<doc:SyncEngine/init(for:tables:privateTables:containerIdentifier:defaultZone:logger:)>)
has more options you may be interested in configuring.

> Important: You must explicitly provide all tables that you want to synchronize. We do this so that
> you can have the option of having some local tables that are not synchronized to CloudKit.

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
  configuration.prepareDatabase = { db in
    db.attachMetadatabase()
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

#### Primary keys

> TLDR: Primary keys should be globally unique identifiers, such as UUID. We further recommend
> specifying a "NOT NULL" constraint with a "ON CONFLICT REPLACE" action.

Primary keys are an important concept in SQL schema design, and SQLite makes it easy to add a 
primary key by using an "autoincrement" integer. This makes it so that newly inserted rows get
a unique ID by simply adding 1 to the largest ID in the table. However, that does not play nicely
with distributed schemas. That would make it possible for two devices to create a record with 
`id: 1`, and when those records synchronize there would be an irreconcilable conflict.

For this reason, primary keys in SQLite tables should be globally unique, such as a UUID. The 
easiest way to do this is to store your table's ID in a "TEXT" column, adding a 
default with a freshly generated UUID, and further adding a "ON CONFLICT REPLACE" constraint:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  …
)
```

> Tip: The "ON CONFLICT REPLACE" clause must be placed directly after "NOT NULL".

This allows you to insert a row with a NULL value for the primary key and SQLite will compute
the primary key from the default value specified. This kind of pattern is commonly used with the
`Draft` type generated for primary keyed tables:

```swift
try database.write { db in
  try Reminder.upsert {
      // Do not provide 'id', let database initialize it for you.
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

#### Primary keys on every table

> TLDR: Each synchronized table must have a single, non-compound primary key to aid in 
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
)
```

Note that the `id` column might not be needed for your application's logic, but it is necessary to 
facilitate synchronizing to CloudKit.

<!--
TODO: think more about this

#### Default values for columns

> TLDR: All columns must have a default in order to allow for multiple devices to run your
> app with different versions of the schema.

Your tables' schemas should be defined to provide a default for every non-null column. To see why 
this is necessary, consider if device A is running with a schema in which `Reminder` has an 
`isFlagged` column and device B is running with a schema that does not. When device B creates a 
record without the `isFlagged` value, and that record is synchronized to device A, it will fail to 
insert into the database because there is not value for `isFlagged`. 

For this reason all columns in your schema must have a default value, and this will be validated
when a ``SyncEngine`` is first created. If a non-null column without a default is detected,
a ``NonNullColumnMustHaveDefault`` error will be thrown.

#### Unique constraints

> TLDR: SQLite tables cannot have "UNIQUE" constraints on their columns in order to allow
> for distributed creation of records.

Tables with unique constraints on their columns, other than on the primary key, cannot be
synchronized. As an example, suppose you have a `Tag` table with a unique constraint on the 
`title` column. It is not clear how the application should handle if two different devices create
a tag with the title "Family" at the same time. When the two devices synchronize their data
they will have a conflict on the uniqueness constraint, but it would not be correct to 
discard one of the tags.

For this reason uniqueness constraints are not allowed in schemas, and this will be validated
when a ``SyncEngine`` is first created. If a uniqueness constraint is detected a 
``UniqueConstraintDisallowed`` error will be thrown.
-->

#### Foreign key relationships

> TLDR: Foreign key constraints can be enabled and you can use "ON DELETE" actions to
> cascade deletions.

SharingGRDB can synchronize many-to-one and many-to-many relationships to CloudKit, 
and you can enforce foreign key constraints in your database connection. While it is possible for
the sync engine to receive records in an order that could cause a foreign key constraint failure, 
such as receiving a child record before its parent, the sync engine will cache the child record
until the parent record has been synchronized, at which point the child record will also be 
synchronized.

Currently the only actions supported for "ON DELETE" are "CASCADE", "SET NULL" and "SET DEFAULT".
In particular, "RESTRICT" and "NO ACTION" are not supported, and if you try to use those actions
in your schema an ``InvalidParentForeignKey`` error will be thrown when constructing ``SyncEngine``.

## Record conflicts

> TLDR: Conflicts are handled automatically using a "last edit wins" strategy for each
> column of the record.

Conflicts between record edits will inevitably happen, and it's just a fact of dealing with 
distributed data. The library handles conflicts automatically, but does so with a single strategy
that is currently not customizable. When a column is edited on a record, the library keeps track
of the timestamp for that particular column. When merging two conflicting records, each column
is analyzed, and the column that was most recently edited will win over the older data.

We do not employ more advanced merge conflict strategies, such as CRDT synchronization. We may
allow for these kinds of strategies in the future, but for now "field-wise last edit wins" is 
the only strategy available and we feel serves the needs of the most number of people.

## Backwards compatible migrations

> TLDR: Database migrations should be done carefully and with full backwards compatibility
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

> TLDR: When adding columns to a table that has already been deployed to user's devices, you will
either need to make the column nullable, or it can be "NOT NULL" but a default value must be 
provided with an "ON CONFLICT REPLACE" clause.

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

This will generate a SQL error because the "position" column was declared as "NOT NULL", and so this
record will not properly synchronize to devices running a newer version of the app.

The fix is to allow for inserting "NULL" values into "NOT NULL" columns by using the default of the
column. This can be done like so:

```sql
ALTER TABLE "remindersLists" 
ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
```

> Important: The "ON CONFLICT REPLACE" clause must come directly after "NOT NULL" because it 
> modifies that constraint.

Now when this query is executed: 

```sql
INSERT INTO "remindersLists" 
("id", "title", "position")
VALUES 
(NULL, 'Personal', NULL)
```

…it will use 0 for the "position" column.

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

It may be disappointing to have to weaken your domain modeling to accomodate synchronization, but
that is the unfortunate reality of a distributed schema. In order to allow multiple versions of your
schema to be run on devices so that each device can create new records and edit existing records 
that all devices can see, you will need to make some compromises.

#### Disallowed migrations

Certain kinds of migrations are simply not allowed when synchronizing your schema to multiple
devices. They are:

* Removing columns
* Renaming columns
* Renaming tables

## Sharing records with other iCloud users

SharingGRDB provides the tools necessary to share a record with another iCloud user so that 
multiple users can collaborate on a single record. Sharing a record with another user brings
extra complications to an app that go beyond the existing complications of sharing a schema
across many devices. Please read the documentation carefully and thoroughly to understand
how to best situate your app for sharing that does not cause problems down the road.

See <doc:CloudKitSharing> for more information.

## Assets

> TLDR: The library packages all BLOB columns in a table into `CKAsset`s and seamlessly decodes
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
  "remindersListID" TEXT PRIMARY KEY NOT NULL REFERENCES "remindersLists"("id"),
  "image" BLOB NOT NULL
)
*/
```

This allows you to efficiently query `RemindersList` while still allowing you to load the image
data for a list when you need it.

## Accessing CloudKit metadata

While the library tries to make CloudKit synchronization as seamless and hidden as possible,
there are times you will need to access the underlying CloudKit types for your tables and records.
The ``SyncMetadata``table is the central place where this data is stored, and it is publicly 
exposed for you to query it in whichever way you want.

> Important: In order to query the `SyncMetadata` table from your database connection you will need 
to attach the metadatabase to your database connection. This can be done with the
``GRDB/Database/attachMetadatabase(containerIdentifier:)`` method defined on `Database`.

With that done you can use the ``StructuredQueriesCore/PrimaryKeyedTable/metadata(for:)`` method
to construct a SQL query for fetching the meta data associated with one of your records.

For example, if you want to retrieve the `CKRecord` that is associated with a particular row in
one of your tables, say a reminder, then you can use ``SyncMetadata/lastKnownServerRecord`` to
retreive the `CKRecord` and then invoke a CloudKit database function to retreive all of the details: 

```swift
let lastKnownServerRecord = try database.read { db in
  try RemindersList
    .metadata(for: remindersListID)
    .select(\.lastKnownServerRecord)
    .fetchOne(db)
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

You are free to invoke any CloudKit functions you want with the `CKRecord` retreived from 
``SyncMetadata``. Any changes made directly with CloudKit will be automatically synced to your
SQLite database by the ``SyncEngine``.

It is also possible to fetch the `CKShare` associated with a record if it has been shared, which
will give you access to the most current list of paricipants and permissions for the shared record:

```swift
let share = try database.read { db in
  try RemindersList
    .metadata(for: remindersListID)
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

<!--
TODO: finish
* show example of joining tables to SyncMetadata
-->

## How SharingGRDB handles distributed schema scenarios

<!-- todo: finish -->

## Unit testing and Xcode previews

## Preparing an existing schema for synchronization

<!-- todo: finish -->

### Convert Int primary keys to UUID

<!-- todo: finish -->

### Add primary key to all tables

<!-- todo: finish -->

<!-- TODO: talk about simulator push restrictions -->

## Migrating from Swift Data to SharingGRDB

## Separating schema migrations from data migrations

## Tips and tricks

### Updating triggers to be compatible with synchronization

If you have triggers installed on your tables, then you may want to customize their definitions
to behave differently depending on whether a write is happening to your database from your own
code or from the sync engine. For example, if you have a trigger that refreshes an `updatedAt`
timestamp on a row when it is edited, it would not be appropriate to do that when the sync engine
updates a row from data received from CloudKit.

To prevent this you can use the ``SyncEngine/isSynchronizingChanges()`` SQL expression. It 
represents a custom database function that is installed in your database connection, and it will 
return true if the write to your database originates from the sync engine. You can use it in a 
trigger like so:

```swift
#sql("""
  CREATE TEMPORARY TRIGGER "…"
  AFTER DELETE ON "…""
  FOR EACH ROW WHEN NOT \(SyncEngine.isSynchronizingChanges())
  BEGIN
    …
  END
  """)
```

Or if you are using the trigger building tools from [StructuredQueries] you can use it like so:

[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries

```swift
Model.createTemporaryTrigger(
  "…",
  after: .insert { new in
    …
  } when: { _ in
    !SyncEngine.isSynchronizingChanges()
  }
)
```

This will skip the trigger's action when the row is being updated due to data being synchronized
from CloudKit.

## Topics

### Go deeper

- <doc:ComparisonWithSwiftData>
