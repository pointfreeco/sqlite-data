# Manually migrating primary keys

The steps needed to manually migrate your tables so that all tables have a primary key, and so
that all primary keys are UUIDs.

## Overview

If the [manual migration](<doc:SyncEngine/migratePrimaryKeys(_:tables:uuid:)>) tool provided
by this library does not work for you, then you will need to migrate your tables manually.
This consists of converting integer primary keys to UUIDs, and adding a primary key to all tables
that do not have one.

### Convert Int primary keys to UUID

The most important step for migrating an existing SQLite database to be compatible with CloudKit
synchronization is converting any `Int` primary keys in your tables to UUID, or some other
globally unique identifier. This can be done in a new migration that is registered when provisioning
your database, but it does take a few queries to accomplish because SQLite does not support
changing the definition of an existing column.

The steps are roughly: 1) create a table with the new schema, 2) copy data over from old
table to new table and convert integer IDs to UUIDs, 3) drop the old table, and finally 4) rename
the new table to have the same name as the old table.

```swift
migrator.registerMigration("Convert 'remindersLists' table primary key to UUID") { db in
  // Step 1: Create new table with updated schema
  try #sql("""
    CREATE TABLE "new_remindersLists" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      -- all other columns from 'remindersLists' table
    ) STRICT
    """)
    .execute(db)

  // Step 2: Copy data from 'remindersLists' to 'new_remindersLists' and convert integer
  // IDs to UUIDs
  try #sql("""
    INSERT INTO "new_remindersLists"
    (
      "id",
      -- all other columns from 'remindersLists' table
    )
    SELECT
      -- This converts integers to UUIDs, e.g. 1 -> 00000000-0000-0000-0000-000000000001
      '00000000-0000-0000-0000-' || printf('%012x', "id"),
      -- all other columns from 'remindersLists' table
    FROM "remindersLists"
    """)
    .execute(db)

  // Step 3: Drop the old 'remindersLists' table
  try #sql("""
    DROP TABLE "remindersLists"
    """)
    .execute(db)

  // Step 4: Rename 'new_remindersLists' to 'remindersLists'
  try #sql("""
    ALTER TABLE "new_remindersLists" RENAME TO "remindersLists"
    """)
    .execute(db)
}
```

This will need to be done for every table that uses an integer for its primary key. Further,
for tables with foreign keys, you will need to adapt step 1 to change the types of those
columns to TEXT and will need to perform the integer-to-UUID conversion for those columns in
step 2:

```swift
migrator.registerMigration("Convert 'reminders' table primary key to UUID") { db in
  // Step 1: Create new table with updated schema
  try #sql("""
    CREATE TABLE "new_reminders" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE,
      -- all other columns from 'reminders' table
    ) STRICT
    """)
    .execute(db)

  // Step 2: Copy data from 'reminders' to 'new_reminders' and convert integer
  // IDs to UUIDs
  try #sql("""
    INSERT INTO "new_reminders"
    (
      "id",
      "remindersListID",
      -- all other columns from 'reminders' table
    )
    SELECT
      -- This converts integers to UUIDs, e.g. 1 -> 00000000-0000-0000-0000-000000000001
      '00000000-0000-0000-0000-' || printf('%012x', "id"),
      '00000000-0000-0000-0000-' || printf('%012x', "remindersListID"),
      -- all other columns from 'reminders' table
    FROM "remindersLists"
    """)
    .execute(db)

  // Step 3 and 4 are unchanged...
}
```

### Add primary key to all tables

All tables must have a primary key to be synchronized to CloudKit, even typically you would not
add one to the table. For example, a join table that joins reminders to tags:

```swift
@Table
struct ReminderTag {
  let reminderID: Reminder.ID
  let tagID: Tag.ID
}
```

…must be updated to have a primary key:


```diff
 @Table
 struct ReminderTag {
+  let id: UUID
   let reminderID: Reminder.ID
   let tagID: Tag.ID
 }
```

And a migration must be run to add that column to the table. However, you must perform a multi-step
migration similar to what is described above in <doc:CloudKit#Convert-Int-primary-keys-to-UUID>.
You must 1) create a new table with the new primary key column, 2) copy data from the old table
to the new table, 3) delete the old table, and finally 4) rename the new table.

Here is how such a migration can look like for the `ReminderTag` table above:

```swift
migrator.registerMigration("Add primary key to 'reminderTags' table") { db in
  // Step 1: Create new table with updated schema
  try #sql("""
    CREATE TABLE "new_reminderTags" (
      "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
      "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
      "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
    ) STRICT
    """)
    .execute(db)

  // Step 2: Copy data from 'reminderTags' to 'new_reminderTags'
  try #sql("""
    INSERT INTO "new_reminderTags"
    ("reminderID", "tagID")
    SELECT "reminderID", "tagID"
    FROM "reminderTags"
    """)
    .execute(db)

  // Step 3: Drop the old 'reminderTags' table
  try #sql("""
    DROP TABLE "reminderTags"
    """)
    .execute(db)

  // Step 4: Rename 'new_reminderTags' to 'reminderTags'
  try #sql("""
    ALTER TABLE "new_reminderTags" RENAME TO "reminderTags"
    """)
    .execute(db)
}
```

