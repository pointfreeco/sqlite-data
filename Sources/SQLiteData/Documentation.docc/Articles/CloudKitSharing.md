# Sharing data with other iCloud users

Learn how to allow your users to share certain records with other iCloud users for collaboration.

## Overview

SQLiteData provides the tools necessary to share a record with another iCloud user so that multiple
users can collaborate on a single record. Sharing a record with another user brings extra
complications to an app that go beyond the existing complications of sharing a schema across many
devices. Please read the documentation carefully and thoroughly to understand how to best design
your schema for sharing that does not cause problems down the road.

> Important: To enable sharing of records be sure to add a `CKSharingSupported` key to your
Info.plist with a value of `true`. This is subtly documented in [Apple's documentation for sharing].

[Apple's documentation for sharing]: https://developer.apple.com/documentation/cloudkit/sharing-cloudkit-data-with-other-icloud-users#Create-and-Share-a-Topic

  - [Creating CKShare records](#Creating-CKShare-records)
  - [Accepting shared records](#Accepting-shared-records)
  - [Diving deeper into sharing](#Diving-deeper-into-sharing)
    - [Sharing root records](#Sharing-root-records)
    - [Sharing foreign key relationships](#Sharing-foreign-key-relationships)
      - [One-to-many relationships](#One-to-many-relationships)
      - [Many-to-many relationships](#Many-to-many-relationships)
      - [One-to-"at most one" relationships](#One-to-at-most-one-relationships)
  - [Sharing permissions](#Sharing-permissions)
  - [Controlling what data is shared](#Controlling-what-data-is-shared)

## Creating CKShare records

To share a record with another user one must first create a `CKShare`. SQLiteData provides the
method ``SyncEngine/share(record:configure:)`` on ``SyncEngine`` for generating a `CKShare` for a
record. Further, the value returned from this method can be stored in a view and be used to drive a
sheet to display a ``CloudSharingView``, which is a wrapper around UIKit's
`UICloudSharingController`.

As an example, a reminders app that wants to allow sharing a reminders list with another user can do
so like this:

```swift
struct RemindersListView: View {
  let remindersList: RemindersList
  @State var sharedRecord: SharedRecord?
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    Form {
      …
    }
    .toolbar {
      Button("Share") {
        Task {
          await withErrorReporting {
            sharedRecord = try await syncEngine.share(record: remindersList) { share in
              share[CKShare.SystemFieldKey.title] = "Join '\(remindersList.title)'!"
            }
          }
        }
      }
    }
    .sheet(item: $sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
  }
}
```

When the "Share" button is tapped, a ``SharedRecord`` will be generated and stored as local state in
the view. That will cause a ``CloudSharingView`` sheet to be presented where the user can configure
how they want to share the record. A record can be _unshared_ by presenting the same
``CloudSharingView`` to the user so that they can tap the "Stop sharing" button in the UI.

If you would like to provide a custom sharing experience outside of what `UICloudSharingController`
offers, you can find more info in [Apple's documentation].

[Apple's documentation]: https://developer.apple.com/documentation/cloudkit/shared-records

## Accepting shared records

Extra steps must be taken to allow a user to _accept_ a shared record. Once the user taps on the
share link sent to them (whether that is by text, email, etc.), the app will be launched with
special options provided or a special delegate method will be invoked in the app's scene delegate.
You must implement these delegate methods and invoke the ``SyncEngine/acceptShare(metadata:)``
method.

As a simplified example, a `UIWindowSceneDelegate` subclass can implement the delegate method like
so:

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  @Dependency(\.defaultSyncEngine) var syncEngine
  var window: UIWindow?

  func windowScene(
    _ windowScene: UIWindowScene,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata
    else {
      return
    }
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
```

The unstructured task is necessary because the delegate method does not work with an async context,
and the `acceptShare` method is async.

## Diving deeper into sharing

The above gives a broad overview of how one shares a record with a user, and how a user accepts a
shared record. There is, however, a lot more to know about sharing. There are important restrictions
placed on what kind of records you are allowed to share, and what associations of those records are
shared.

In a nutshell, only "root" records can be directly shared, _i.e._ records with no foreign keys.
Further, an association of a root record can only be shared if it has only one foreign key pointing
to the root record. And this last rule applies recursively: a leaf association is shared only if
it has exactly one foreign key pointing to a record that also satisfies this property.

For more in-depth information, keep reading.

### Sharing root records

> Important: It is only possible to share "root" records, _i.e._ records with no foreign keys.

A record can be shared only if it is a "root" record. That means it cannot have any
foreign keys whatsoever. As an example, the following `RemindersList` table is a root record because
it does not have any fields pointing to other tables:

```swift
@Table
struct RemindersList: Identifiable {
  let id: UUID
  var title = ""
}
```

On the other hand, a `Reminder` table with a foreign key pointing to the `RemindersList` is _not_
a root record:

```swift
@Table
struct Reminder: Identifiable {
  let id: UUID
  var title = ""
  var isCompleted = false
  var remindersListID: RemindersList.ID
}
```

Such records cannot be shared because it is not appropriate to also share the parent record (_i.e._
the reminders list).

For example, suppose you have a list named "Personal" with a reminder "Get milk". If you share this
reminder with someone, then it becomes difficult to figure out what to do when they make certain
changes to the reminder:

  * If they decide to reassign the reminder to their personal "Life" list, what should
    happen? Should their "Life" list suddenly be synchronized to your device?
  * Or what if they delete the list? Would you want that to delete your list and all of the
    reminders in the list?

For these reasons, and more, it is not possible to share non-root records, like reminders. Instead,
you can share root records, like reminders lists. If you do invoke
``SyncEngine/share(record:configure:)`` with a non-root record, an error will be thrown.

> Note: A reminder can still be shared as an association to a shared reminders list, as discussed
> [in the next section](<doc:CloudKit#Sharing-foreign-key-relationships>). However, a single
> reminder cannot be shared on its own.

For a more complex example, consider the following diagrammatic schema for a reminders app:

@Image(source: "sync-diagram-root-record.png") {
  The green node represents a "root" record, i.e. a record with no foreign key relationships.
}

In this schema, a `RemindersList` can have many `Reminder`s, can have a `CoverImage`, and a
`Reminder` can have multiple `Tag`s, and vice-versa. The only table in this diagram that constitutes
a "root" is `RemindersList`. It is the only one with no foreign key relationships. None of
`Reminder`, `CoverImage`, `Tag` or `ReminderTag` can be directly shared on their own because they
are not root tables.

### Sharing foreign key relationships

> Important: Foreign key relationships are automatically synchronized, but only if the related
> record has a single foreign key. Records with multiple foreign keys cannot be synchronized.

Relationships between models will automatically be shared when sharing a root record, but with some
limitations. An associated record of a shared record will only be shared if it has exactly one
foreign key pointing to the root shared record, whether directly or indirectly through other records
satisfying this property.

Below we describe some of the most common types of relationships in SQL databases, as well as
which are possible to synchronize, which cannot be synchronized, and which can be adapted to
play nicely with synchronization.

##### One-to-many relationships

One-to-many relationships are the simplest to share with other users. As an example, consider a
`RemindersList` table that can have many `Reminder`s associated with it:

```swift
@Table
struct RemindersList: Identifiable {
  let id: UUID
  var title = ""
}

@Table
struct Reminder: Identifiable {
  let id: UUID
  var title = ""
  var isCompleted = false
  var remindersListID: RemindersList.ID
}
```

Since `RemindersList` is a [root record](#Sharing-root-records) it can be shared, and since
`Reminder` has only one foreign key pointing to `RemindersList`, it too will be shared.

Further, suppose there was a `ChildReminder` table that had a single foreign key pointing to a
`Reminder`:

```swift
@Table
struct ChildReminder: Identifiable {
  let id: UUID
  var title = ""
  var isCompleted = false
  var parentReminderID: Reminders.ID
}
```

This too will be shared because it has one single foreign key pointing to a table that also has one
single foreign key pointing to the root record being shared.

As a more complex example, consider the following diagrammatic schema:

@Image(source: "sync-diagram-one-to-many.png") {
  The green node is a shareable root record, and all blue records are relationships that will also
  be shared when the root is shared.
}

In this schema, a `RemindersList` can have many `Reminder`s and a `CoverImage`, and a `Reminder` can
have many `ChildReminder`s. Sharing a `RemindersList` will share all associated reminders, cover
image, and even child reminders. The child reminders are synchronized because it has a single
foreign key pointing to a table that also has a single foreign key pointing to the root record.

##### Many-to-many relationships

Many-to-many relationships pose a significant problem to sharing and cannot be supported. If a table
has multiple foreign keys, then it will not be shared even if one of those  foreign keys points to
the shared record.

As an example, suppose we had a many-to-many association of a `Tag` table to `Reminder` via a
`ReminderTag` join table:

```swift
@Table
struct Tag: Identifiable {
  let id: UUID
  var title = ""
}
@Table
struct ReminderTag: Identifiable {
  let id: UUID
  var reminderID: Reminder.ID
  var tagID: Tag.ID
}
```

In diagrammatic form, this schema looks like the following:

@Image(source: sync-diagram-many-to-many.png) {
  The green record is a shareable record, the blue record will be shared when the root is shared,
  and the light purple records cannot be shared.
}

The `ReminderTag` records will _not_ be shared because it has two foreign key relationships,
represented by the two arrows leaving the `ReminderTag` node. As a consequence, the `Tag` records
will also not be shared. Sharing these records cannot be done in a consistent and logical manner.

> Note: `CKShare` in CloudKit, which is what our tools are built on, does not support sharing
> many-to-many relationships. This is also how the Reminders app works on Apple's platforms. Sharing
> a list of reminders with another use does not share its tags with that user.

To see why this is an acceptable limitation, suppose you share a "Personal" list with someone, which
holds a "Get milk" reminder, and that reminder has a "weekend" tag associated with it. If the tag
were shared with your friend, then what happens when they delete the tag? Would it be appropriate to
delete that tag from all of your reminders, even the ones that were not shared? For this reason,
and more, records with multiple foreign keys cannot be shared with a record.

If you want to support many tags associated with a single reminder, you will have no choice
but to turn it into a one-to-many relationship so that each tag belongs to exactly one reminder:

```swift
@Table
struct Tag: Identifiable {
  let id: UUID
  var title = ""
  var reminderID: Reminder.ID
}
```

In diagrammatic form this schema now looks like the following:

@Image(source: sync-diagram-many-to-many-refactor.png) {
  The green record is a shareable root record, and the blue records will be shared when the root is
  shared.
}

This kind of relationship will now be synchronized automatically. Sharing a `RemindersList` will
automatically share all of its `Reminder`s, which will subsequently also share all of their
`Tag`s.

But, this does now mean it's possible to have multiple `Tag` rows in the database that have the
same title and thus represent the same tag. You wil have to put extra care in your queries and
application logic to properly aggregate these tags together, but luckily this is something that SQL
excels at.

##### One-to-"at most one" relationships

One-to-"at most one" relationships in SQLite allow you to associate zero or one records with
another record. For an example of this, suppose we wanted to hold onto a cover image for reminders
lists (see <doc:CloudKit#Assets> for more information on synchronizing assets such as images). It
is perfectly fine to hold onto large binary data in SQLite, such as image data, but typically one
should put this data in a separate table.

The way to model this kind of relationship in SQLite is by making a foreign key point from the image
table to the reminders list table, _and_ to make that foreign key the primary key of the table. That
enforces that at most one image is associated with a reminders list.

In diagrammatic form, it looks like this:

![One-to-"at most one" relationship with uniqueness](sync-diagram-one-to-at-most-one-unique.png)
<!--
```mermaid
graph BT
  Reminder ---\>|remindersListID| RemindersList
  CoverImage ---\>|PRIMARY KEY remindersListID| RemindersList
  classDef root color:#000,fill:#4cccff,stroke:#333,stroke-width:2px;
  classDef shared color:#000,fill:#98EFB5,stroke:#333,stroke-width:2px;
  class RemindersList root
  class Reminder,CoverImage shared
```
-->

Here the `CoverImage` table has a foreign key pointing to the root table `RemindersList`, but since
it is also the primary key of the table it enforces that at most one cover image belongs to a list.

## Sharing permissions

CloudKit sharing supports permissions so that you can give read-only or read-write access to the
data you share with other users. These permissions are automatically observed by the library and
enforced when writing to your database. If your application tries to write to a record that it
does not have permission for, a `DatabaseError` will be emitted.

To check for this error you can catch `DatabaseError` and compare its message to
``SyncEngine/writePermissionError``:

```swift
do {
  try await database.write { db in
    Reminder.find(id)
      .update { $0.title = "Personal" }
      .execute(db)
  }
} catch let error as DatabaseError where error.message == SyncEngine.writePermissionError {
  // User does not have permission to write to this record.
}
```

See <doc:CloudKit#Accessing-CloudKit-metadata> for more information on accessing the metadata
associated with your user's data.

Ideally your app would not allow the user to write to records that they do not have permissions for.
To check their permissions for a record, you can join the root record table to ``SyncMetadata`` and
select the ``SyncMetadata/share`` value:

```swift
let share = try await database.read { db in
  RemindersList
    .metadata(for: id)
    .select(\.share)
    .fetchOne(db)
    ?? nil
}
guard
  share?.currentUserParticipant?.permission == .readWrite
    || share?.permission == .readWrite
else {
  // User does not have permissions to write to record.
  return
}
```

This allows you to determine the sharing permissions for a root record.

## Controlling what data is shared

It is possible to specify that certain associations that are shareable not be shared. For example,
suppose that you want reminders lists to be sorted by your user, and so add a `position` column to
the table:

```swift
@Table
struct RemindersList: Identifiable {
  let id: UUID
  var position = 0
  var title = ""
}
```

Sharing this record will mean also sharing the position of the list. That means when one user
reorders their local lists, even ones that are private to them, it will reorder the lists for
everyone shared. This is probably not what you want.

So, private and non-shareable information about this record can be stored in a separate table, and
we can use the trick mentioned in <doc:CloudKitSharing#One-to-at-most-one-relationships> by making
the foreign key of the table also be the table's primary key:

```swift
@Table
struct RemindersList: Identifiable {
  let id: UUID
  var title = ""
}
@Table
struct RemindersListPrivate: Identifiable {
  @Column(primaryKey: true)
  let remindersListID: RemindersList.ID
  var position = 0
}
```

And then when creating the ``SyncEngine`` we can specifically ask it to not share this record when
the reminders list is shared by specifying the `privateTables` argument:

```swift
@main
struct MyApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try appDatabase()
      $0.defaultSyncEngine = try SyncEngine(
        for: $0.defaultDatabase,
        tables: RemindersList.self, Reminder.self,
        privateTables: RemindersListPrivate.self
      )
    }
  }

  …
}
```

This table will still be synchronized across all of a single user's devices, but if that user
shares a list with a friend, it will _not_ share the private table, allowing each user to have
their own personal ordering of lists.
