# CloudKit synchronization

Learn how to seamlessly add CloudKit synchronization and record sharing to your SharingGRDB
application.

## Overview

SharingGRDB allows you to seamlessly synchronize your SQLite database with CloudKit. After a few
steps to set up your project and a ``SyncEngine`` your database can be automatically synchronized
to CloudKit. However, distributing your app's schema across many devices is an impactful decision
to make, and so an abundance of care must be taken to make sure all devices remain consistent
and capable of communicating with each other. Please read the documentation closely and thoroughly
to make sure you understand how to best prepare your app for cloud synchronization.

## Setting up your project

The steps to set up your SharingGRDB project for CloudKit synchronization are the 
[same for setting up][setup-cloudkit-apple] any other kind of project for CloudKit:

* Follow the [Configuring iCloud services] guide for enabling iCloud entitlements in your project.
* Follow the [Configuring background execution modes] guide for adding the Background Modes
capability to your project.
* If you want enable sharing of records with other iCloud users, be sure to add a 
`CKSharingSupported` key to your Info.plist with a value of `true`. This is subtly documented 
in [Apple's documentation for sharing].

With those steps completed you are ready to configure a ``SyncEngine`` that will facilitate
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
> * The CloudKit container identifier must be explicitly provided and unfortuantely cannot be 
> extracted from Entitlements.plist automatically. That priviledge is only afforded to SwiftData.
> * You must explicitly provide all tables that you want to synchronize. We do this so that you can
> have the option of having some local tables that are not synchronized to CloudKit.

Once this work is done the app should work exactly as it did before, but now any changes made
to the database will be synchronized to CloudKit. You will still interact with your local SQLite
database in the same as you always do. You can use ``FetchAll`` to fetch data to be used in a view
or `@Observable` model, and you can use the `defaultDatabase` dependency to write to the database.

## Designing your schema with synchronization in mind

Distributing your app's schema across many devices is a big decision to make for your app, and
care must be taken. It is not true that you can simply take any existing schema, add a 
``SyncEngine`` to it, and have it magically synchronize data across all devices and across all
versions of your app. There are a number of principals to keep in mind while designing and evolving
your schema to make sure every device can synchronize changes to every other device, no matter the
version.

#### Primary keys

> Important: Primary keys must be UUIDs with a default, and further we recommend specifying a "NOT NULL"
> constraint with a "ON CONFLICT REPLACE" action.

Primary keys are an important concept in SQL schema design, and SQLite makes it easy to add a 
primary key by using an "autoincrement" integer. This makes it so that newly inserted rows get
a unique ID by simply adding 1 to the largest ID in the table. However, that does not play nicely
with distributed schemas. That would make it possible for two devices to create a record with 
`id: 1`, and when those records synchronize there would be an irreconcilable conflict.

For this reason, primary keys in SQLite tables should be globally unique, and so SharingGRDB
requires that they be UUIDs. We recommend stores UUIDs in SQLite a "TEXT" column, adding a default
with a freshly generated UUID, and further adding a "ON CONFLICT REPLACE" constraint:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  …
)
```

This will make it possible to create new records using the `Draft` type afforded to primary 
keyed tables without needing to specify an `id`:

```swift
try database.write { db in
  try Reminder.upsert { Reminder.Draft(title: "Get milk") }
    .execute(db)
}
```

#### Primary keys on every table

> Important: Every table synchronized must have a single, non-compound primary key to aid in 
> synchronization, even if it is not used by your app.

_Every_ table being synchronized must have a single primary key and cannot have compound primary
keys. This includes join tables that typically only have two foreign keys pointing to the two 
tables they are joining. For example, a `ReminderTag` table that joins reminders to tags should be
designed like so:

```sql
CREATE TABLE "reminders" (
  "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
  "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
  "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
)
```

Note that the `id` column may not ever be used in your application code, but it is necessary to 
facilitate synchronizing to CloudKit.

#### Foreign key relationships

> Important: Foreign key constraints must be disabled for your SQLite connection, but you can still
> use references with "ON DELETE" and "ON UPDATE" actions.

SharingGRDB can synchronize one-to-one, many-to-one and many-to-many to CloudKit, however one
cannot _enforce_ foreign key constraints. Recall that foreign key constraints allow you to say
when one table references a row from another table. For example, a reminder can belong to a 
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
the list will also be synchronized.

## Sharing records with other iCloud users

#### Foreign key relationships

Relationships between models 

## How SharingGRDB handles distributed schema scenarios

## Preparing an existing schema for synchronization

### Convert Int primary keys to UUID

### Add primary key to all tables

<!-- TODO: talk about simulator push restrictions -->
