# Preparing a SQLite database

Learn how to create, configure and migrate the SQLite database that holds your application’s
data.

## Overview

Before you can use any of the tools of this library you must create and configure the SQLite
database that will be used throughout the app. There are a few steps to getting this right, and
a few optional steps you can perform to make the database you provision work well for testing
and Xcode previews.

* [Step 1: Static database connection](#Step-1-Static-database-connection)
* [Step 2: Create configuration](#Step-2-Create-configuration)
* [Step 3: Create database connection](#Step-3-Create-database-connection)
* [Step 4: Migrate database](#Step-4-Migrate-database)
* [Step 5: Set database connection in entry point](#Step-5-Set-database-connection-in-entry-point)
* [(Optional) Step 6: Set up CloudKit SyncEngine](#Optional-Step-6-Set-up-CloudKit-SyncEngine)

### Step 1: App database connection

We will begin by defining a static `appDatabase` function that returns a connection to a local
database stored on disk. We like to define this at the module level wherever the schema is defined:

```swift
func appDatabase() -> any DatabaseWriter {
  // ...
}
```

> Note: Here we are returning an `any DatabaseWriter`. This will allow us to return either a
> [`DatabaseQueue`][db-q-docs] or [`DatabasePool`][db-pool-docs] from within.

[db-q-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/databasequeue
[db-pool-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/databasepool

### Step 2: Create configuration

Inside this static variable we can create a [`Configuration`][config-docs] value that is used to
configure the database if there is any custom configuration you want to perform. This is an
optional step:

```diff
 func appDatabase() -> any DatabaseWriter {
+  var configuration = Configuration()
 }
```

One configuration you may want to enable is query tracing in order to log queries that are executed
in your application. This can be handy for tracking down long-running queries, or when more queries
execute than you expect. We also recommend only doing this in debug builds to avoid leaking
sensitive information when the app is running on a user's device, and we further recommend using
OSLog when running your app in the simulator/device and using `Swift.print` in previews:

```diff
 import OSLog
 import SQLiteData

 func appDatabase() -> any DatabaseWriter {
+  @Dependency(\.context) var context
   var configuration = Configuration()
+  #if DEBUG
+    configuration.prepareDatabase { db in
+      db.trace(options: .profile) {
+        if context == .preview {
+          print("\($0.expandedDescription)")
+        } else {
+          logger.debug("\($0.expandedDescription)")
+        }
+      }
+    }
+  #endif
 }

+private let logger = Logger(subsystem: "MyApp", category: "Database")
```

> Note: `expandedDescription` will also print the data bound to the SQL statement, which can include
> sensitive data that you may not want to leak. In this case we feel it is OK because everything
> is surrounded in `#if DEBUG`, but it is something to be careful of in your own apps.

> Tip: `@Dependency(\.context)` comes from the [Swift Dependencies][swift-dependencies-gh] library,
> which SQLiteData uses to share its database connection across fetch keys. It allows you to
> inspect the context your app is running in: live, preview or test.

[swift-dependencies-gh]: https://github.com/pointfreeco/swift-dependencies

For more information on configuring the database connection, see [GRDB's documentation][config-docs]
on the matter.

[config-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/configuration
[trace-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/database/trace(options:_:)

### Step 3: Create database connection

Once a `Configuration` value is set up we can construct the actual database connection. The simplest
way to do this is to construct the database connection using the ``defaultDatabase(path:configuration:)`` function:

```diff
-func appDatabase() -> any DatabaseWriter {
+func appDatabase() throws -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   #if DEBUG
     configuration.prepareDatabase { db in
       db.trace(options: .profile) {
         if context == .preview {
           print("\($0.expandedDescription)")
         } else {
           logger.debug("\($0.expandedDescription)")
         }
       }
     }
   #endif
+  let database = try defaultDatabase(configuration: configuration)
+  logger.info("open '\(database.path)'")
+  return database
 }
```

This function provisions a context-dependent database for you, _e.g._ in previews and tests it
will provision unique, temporary databases that won't conflict with your live app's database.

### Step 4: Migrate database

Now that the database connection is created we can migrate the database. GRDB provides all the
tools necessary to perform [database migrations][grdb-migration-docs], but the basics include
creating a `DatabaseMigrator`, registering migrations with it, and then using it to migrate the
database connection:

```diff
 func appDatabase() throws -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   #if DEBUG
     configuration.prepareDatabase { db in
       db.trace(options: .profile) {
         if context == .preview {
           print("\($0.expandedDescription)")
         } else {
           logger.debug("\($0.expandedDescription)")
         }
       }
     }
   #endif
   let database = try defaultDatabase(configuration: configuration)
   logger.info("open '\(database.path)'")
+  var migrator = DatabaseMigrator()
+  #if DEBUG
+    migrator.eraseDatabaseOnSchemaChange = true
+  #endif
+  migrator.registerMigration("Create tables") { db in
+    // Execute SQL to create tables
+  }
+  try migrator.migrate(database)
   return database
 }
```

As your application evolves you will register more and more migrations with the migrator.

It is up to you how you want to actually execute the SQL that creates your tables. There are
[APIs in the community][grdb-table-definition] for building table definition statements using Swift
code, but we personally feel that it is simpler, more flexible and more powerful to use
[plain SQL strings][table-definition-tools]:

[grdb-table-definition]: https://swiftpackageindex.com/groue/grdb.swift/v7.6.1/documentation/grdb/database/create(table:options:body:)

```swift
migrator.registerMigration("Create tables") { db in
  try #sql("""
    CREATE TABLE "remindersLists"(
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "title" TEXT NOT NULL
    ) STRICT
    """)
    .execute(db)

  try #sql("""
    CREATE TABLE "reminders"(
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "isCompleted" INTEGER NOT NULL DEFAULT 0,
      "title" TEXT NOT NULL,
      "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
    ) STRICT
    """)
    .execute(db)
}
```

It may seem counterintuitive that we recommend using SQL strings for table definitions when so much
of the library provides type-safe and schema-safe tools for executing SQL. But table definition SQL
is fundamentally different from other SQL as it is frozen in time and should never be edited
after it has been deployed to users. Read [this article][table-definition-tools] from our
StructuredQueries library to learn more about this decision.

[table-definition-tools]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/main/documentation/structuredqueriescore/definingyourschema#Table-definition-tools

That is all it takes to create, configure and migrate a database connection. Here is the code
we have just written in one snippet:

```swift
import OSLog
import SQLiteData

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  var configuration = Configuration()
  #if DEBUG
    configuration.prepareDatabase { db in
      db.trace(options: .profile) {
        if context == .preview {
          print("\($0.expandedDescription)")
        } else {
          logger.debug("\($0.expandedDescription)")
        }
      }
    }
  #endif
  let database = try defaultDatabase(configuration: configuration)
  logger.info("open '\(database.path)'")
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create tables") { db in
    // ...
  }
  try migrator.migrate(database)
  return database
}

private let logger = Logger(subsystem: "MyApp", category: "Database")
```

[grdb-migration-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/migrations

### Step 5: Set database connection in entry point

Once you have defined your `appDatabase` helper for creating a database connection, you must set
it as the `defaultDatabase` for your app in its entry point. This can be in done in SwiftUI by using
`prepareDependencies` in the `init` of your `App` conformance:

```swift
import SQLiteData
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
    }
  }
  // ...
}
```

> Important: You can only prepare the default database a single time in the lifetime of your
> application. It is best to do this as early as possible after the app launches.

If using app or scene delegates, then you can prepare the `defaultDatabase` in one of those
conformances:

```swift
import SQLiteData
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
  func applicationDidFinishLaunching(_ application: UIApplication) {
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
    }
  }
  // ...
}
```

And if using something besides UIKit or SwiftUI, then simply set the `defaultDatabase` as early as
possible in the application's lifecycle.

It is also important to prepare the database in Xcode previews. This can be done like so:

```swift
#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = try! appDatabase()
  }
  // ...
}
```

And similarly, in tests, this can be done using the `.dependency` testing trait:

```swift
@Test(.dependency(\.defaultDatabase, try appDatabase())
func feature() {
  // ...
}
```

### (Optional) Step 6: Set up CloudKit SyncEngine

If you plan on synchronizing your local database to CloudKit so that your user's data is available
on all of their devices, there is an additional step you must take. See
<doc:CloudKit> for more information.
