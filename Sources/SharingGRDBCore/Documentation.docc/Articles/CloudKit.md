# CloudKit synchronization

Learn how to seamlessly add CloudKit synchronization to your SharingGRDB application.

## Overview

SharingGRDB allows you to seamlessly synchronize your SQLite database with CloudKit. After a few
steps to set up your project and a ``SyncEngine``, your database can be automatically synchronized
to CloudKit. However, distributing your app's schema across many devices is an impactful decision
to make, and so an abundance of care must be taken to make sure all devices remain consistent
and capable of communicating with each other. Please read the documentation closely and thoroughly
to make sure you understand how to best prepare your app for cloud synchronization.
  
  - [Setting up your project](#Setting-up-your-project)  
  - [Setting up a SyncEngine](#Setting-up-a-SyncEngine)  
  - [Designing your schema with synchronization in mind](#Designing-your-schema-with-synchronization-in-mind)  
    - [UUID Primary keys](#UUID-Primary-keys)  
    - [Primary keys on every table](#Primary-keys-on-every-table)
    - [Foreign key relationships](#Foreign-key-relationships)  
  - [Record conflicts](#Record-conflicts)  
  - [Backwards compatible migrations](#Backwards-compatible-migrations)  
  - [Sharing records with other iCloud users](#Sharing-records-with-other-iCloud-users)  
  - [Assets](#Assets)  
  - [Accessing CloudKit metadata](#Accessing-CloudKit-metadata)  
  - [How SharingGRDB handles distributed schema scenarios](#How-SharingGRDB-handles-distributed-schema-scenarios)  
  - [Preparing an existing schema for synchronization](#Preparing-an-existing-schema-for-synchronization)  
    - [Convert Int primary keys to UUID](#Convert-Int-primary-keys-to-UUID)  
    - [Add primary key to all tables](#Add-primary-key-to-all-tables)

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
for changes in the database to play them back to CloudKit, and listen for changes in CloudKit to
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
        container: CKContainer(
          identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"
        ),
        database: $0.defaultDatabase,
        tables: [
          RemindersList.self,
          Reminder.self,
        ]
      )
    }
  }
  
  …
}
```

> Important: A few important things to note about this:
> 
> * The CloudKit container identifier must be explicitly provided and unfortunately cannot be 
> extracted from Entitlements.plist automatically. That privilege is only afforded to SwiftData.
> * You must explicitly provide all tables that you want to synchronize. We do this so that you can
> have the option of having some local tables that are not synchronized to CloudKit.

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
    db.attachMetadatabase(containerIdentifier: "iCloud.my.company.MyApp")
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

#### UUID Primary keys

> Important: Primary keys must be UUIDs with a default, and further, we recommend specifying a 
> "NOT NULL" constraint with a "ON CONFLICT REPLACE" action.

Primary keys are an important concept in SQL schema design, and SQLite makes it easy to add a 
primary key by using an "autoincrement" integer. This makes it so that newly inserted rows get
a unique ID by simply adding 1 to the largest ID in the table. However, that does not play nicely
with distributed schemas. That would make it possible for two devices to create a record with 
`id: 1`, and when those records synchronize there would be an irreconcilable conflict.

For this reason, primary keys in SQLite tables should be globally unique, and so SharingGRDB
requires that they be UUIDs. We recommend storing UUIDs in SQLite as a "TEXT" column, adding a 
default with a freshly generated UUID, and further adding a "ON CONFLICT REPLACE" constraint:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  …
)
```

> Tip: The "ON CONFLICT REPLACE" clause must be placed directly after "NOT NULL".

This will make it possible to create new records using the `Draft` type afforded to primary 
keyed tables without needing to specify an `id`:

```swift
try database.write { db in
  try Reminder.upsert {
      // Do not provide 'id', let database initialize it for you.
      Reminder.Draft(title: "Get milk") 
    }
    .execute(db)
}
```

#### Primary keys on every table

> Important: Each synchronized table must have a single, non-compound primary key to aid in 
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

Note that the `id` column may never be used in your application code, but it is necessary to 
facilitate synchronizing to CloudKit.

<!--
TODO: think more about this

#### Default values for columns

> Important: All columns must have a default in order to allow for multiple devices to run your
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

> Important: SQLite tables cannot have "UNIQUE" constraints on their columns in order to allow
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

> Important: Foreign key constraints must be disabled for your SQLite connection, but you can still
> use references with "ON DELETE" and "ON UPDATE" actions.

SharingGRDB can synchronize one-to-one, many-to-one, and many-to-many relationships to CloudKit, 
however one cannot _enforce_ foreign key constraints. Recall that foreign key constraints define 
when one table references a row in another table. For example, a reminder can belong to a 
reminders list, and the following schema expresses this relationship:

```sql
CREATE TABLE "reminders" (
  …
  "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
)
```

This expresses a one-to-many relationship (i.e. one reminders list can have many reminders),
and typically we like to _enforce_ this relationship by not allowing one to create a reminder
with a `remindersListID` that does not exist in the database.

However, this constraint does not play nicely with distributed schemas. We cannot guarantee the 
order that reminders and lists are synchronized to the device, and so there will be times that a
reminder is synchronized to the device without its associated list, and then a few moments later
the list will also be synchronized. We must allow for this intermediate period of inconsistency
as we wait for the system to become eventually consistent.

> Note: It is OK for foreign keys to be "NOT NULL" in your schema, but your queries and UI should
> be built in a way that is resilient to times when the foreign key points to a row
> that does not yet exist. This means that when performing a full join between tables you may
> not get any results until all data has been synchronized, or when performing a left join,
> you will have to deal with optional values.

So, when creating and migrating your database, you must disable foreign key checks. This is done
in GRDB like so:

```diff
 func appDatabase() throws -> any DatabaseWriter {
   let database: any DatabaseWriter
   var configuration = Configuration()
+  configuration.foreignKeysEnabled = false
   …
 }
```

This unfortunately turns off _all_ functionality of foreign keys. But, there are two parts to 
foreign keys: there is the constraint, which prevents creating rows that reference other rows
that do not exist, and there's the action, which allows you to perform an action when a foreign
key is updated (such as cascading deletions). The former is incompatible with distributed schemas,
but the latter is perfectly fine.

For this reason, SharingGRDB recreates foreign key actions so that you can still take advantage of
"ON UPDATE" and "ON DELETE" clauses. This means that you can continue using foreign keys
in your table schema:

```sql
CREATE TABLE "reminders" (
  …
  "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
)
```

…and while the constraint will not be enforced, the "ON DELETE CASCADE" will still be implemented
by triggers created in ``SyncEngine`` setup, i.e. when a reminders list is deleted, all of its
associated reminders will also be deleted, and everything will be synchronized to all devices.

## Record conflicts

> Important: Conflicts are handled automatically by letting most recently edited records overwrite
> older records.

Conflicts between record edits will inevitably happen, and it's just a fact of dealing with 
distributed data. The library handles conflicts automatically, but does so in the most naive way
possible (which is also the strategy of SwiftData). When a record is synchronized to a device,
the ``SyncEngine`` checks a last modified timestamp on the new record and the record it currently
has on device, and it chooses the one with the newest timestamp.

There is no per-field synchronization, nor is there more advanced CRDT synchronization. We may
allow for these kinds of strategies in the future, but for now "last edit wins" is the only
strategy available and we feel serves the needs of the most number of people.

## Backwards compatible migrations

> Important: Database migrations should be done carefully and with full backwards compatibility
> in mind in order to support multiple devices running with different schema versions.

<!-- todo: finish -->

## Sharing records with other iCloud users

SharingGRDB provides the tools necessary to share a record with another iCloud user so that 
multiple users can collaborate on a single record. Sharing a record with another user brings
extra complications to an app that go beyond the existing complications of sharing a schema
across many devices. Please read the documentation carefully and thoroughly to understand
how to best situate your app for sharing that does not cause problems down the road.

See <doc:CloudKitSharing> for more information.

## Assets

<!-- todo: finish -->

## Accessing CloudKit metadata

While the library tries to make CloudKit synchronization as seamless and hidden as possible,
there are times you will need to access the underlying CloudKit types for your tables and records.
The ``SyncMetadata``table is the central place where this data is stored, and it is publicly 
exposed for you to query it in whichever way you want.

> Important: In order to query the `SyncMetadata` table from your database connection you will need 
to attach the metadatabase to your database connection. This can be done with the
``GRDB/Database/attachMetadatabase(containerIdentifier:)`` method defined on `Database`.

For example, if you want to retrieve the `CKRecord` that is associated with a particular row in
one of your tables, say a reminder, then you can use ``SyncMetadata/lastKnownServerRecord`` to
retreive the `CKRecord` and then invoke a CloudKit database function to retreive all of the details: 

```swift
let metadata = try database.read { db in
  try SyncMetadata
    .find(RemindersList.recordName(for: remindersListID))
    .fetchOne(db)
}
guard let metadata 
else { return }

let ckRecord = try await container.privateCloudDatabase
  .record(for: metadata.lastKnownServerRecord.recordID)
```

> Important: In the above snippet we are explicitly using `privateCloudDatabase`, but that is
> only appropriate for unshared records. If your record is shared, which can be determined from
> [SyncMetadata.share](<doc:SyncMetadata/share>), then you must use `sharedCloudDatabase` to
> fetch the newest record.

You are free to invoke any CloudKit functions you want with the `CKRecord` retreived from 
``SyncMetadata``. Any changes made directly with CloudKit will be automatically synced to your
SQLite database by the ``SyncEngine``.

It is also possible to fetch the `CKShare` associated with a record if it has been shared:

```swift
let metadata = try database.read { db in
  try SyncMetadata
    .find(RemindersList.recordName(for: remindersListID))
    .fetchOne(db)
}
guard 
  let metadata,
  let share = metadata.share
else { return }

let ckRecord = try await container.sharedCloudDatabase
  .record(for: share.recordID)
```

> Important: In the above snippet we are using the `sharedCloudDatabase` and this is always 
appropriate to use when fetching the details of a `CKShare` as they are always stored in the 
shared database.

<!-- todo: fact check the above 'important' -->

It is possible to 

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

<!-- todo: finish -->

```swift
#sql("""
  CREATE TEMPORARY TRIGGER "…"
  AFTER DELETE ON "…""
  FOR EACH ROW WHEN NOT \(SyncEngine.isUpdatingRecord())
  BEGIN
    …
  END
  """)
```

```swift
createTemporaryTrigger(
  "…",
  after: .insert { new in
    …
  } when: { _ in
    !SyncEngine.isUpdatingRecord()
  }
)
```

## Topics

### Go deeper

- <doc:ComparisonWithSwiftData>
