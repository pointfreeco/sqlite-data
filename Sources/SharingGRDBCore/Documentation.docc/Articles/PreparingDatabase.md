# Preparing a SQLite database

Learn how to create and configure the SQLite database that holds your application's data.

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
configure the database. We highly recommend always turning on 
[foreign key](https://www.sqlite.org/foreignkeys.html) constraints to protect the integrity of your
data:

```diff
 func appDatabase() -> any DatabaseWriter {
+  var configuration = Configuration()
+  configuration.foreignKeysEnabled = true
 }
```

This will prevent you from deleting rows that leave other rows with invalid associations. For 
example, if a "teams" table had an association to a "sports" table, you would not be allowed to
delete a sports row unless there were no teams associated with it, or if you had specified a 
cascading action (such as delete).

We further recommend that you enable query tracing to log queries that are executed in your
application. This can be handy for tracking down long-running queries, or when more queries execute
than you expect. We also recommend only doing this in debug builds to avoid leaking sensitive
information when the app is running on a user's device, and we further recommned using OSLog
when running your app in the simulator/device and using `Swift.print` in previews:

```diff
 import OSLog
 import SharingGRDB

 func appDatabase() -> any DatabaseWriter {
+  @Dependency(\.context) var context
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
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
> which SharingGRDB uses to share its database connection across fetch keys. It allows you to
> inspect the context your app is running in: live, preview or test.

[swift-dependencies-gh]: https://github.com/pointfreeco/swift-dependencies

For more information on configuring tracing, see [GRDB's documentation][trace-docs] on the
matter.

[config-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/configuration
[trace-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/database/trace(options:_:)

### Step 3: Create database connection

Once a `Configuration` value is set up we can construct the actual database connection. The simplest
way to do this is to construct the database connection for a path on the file system like so:

```diff
-func appDatabase() -> any DatabaseWriter {
+func appDatabase() throws -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
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
+  let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
+  logger.info("open \(path)")
+  let database = try DatabasePool(path: path, configuration: configuration)
+  return database
 }
```

However, this can be improved. First, this code will crash if it is executed in Xcode previews 
because SQLite is unable to form a connection to a database on disk in a preview context. And
second, in tests we should write this databadse to the temporary directoy on disk with a unique
name so that each test gets a fresh database and so that multiple tests can run in parallel.

To fix this we can use `@Dependency(\.context)` to determine if we are in a "live" application
context or if we're in a preview or test.

```diff
 func appDatabase() -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
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
-  let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
-  logger.info("open \(path)")
-  let database = try DatabasePool(path: path, configuration: configuration)
+  @Dependency(\.context) var context
+  let database: any DatabaseWriter
+  if context == .live {
+    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
+    logger.info("open \(path)")
+    database = try DatabasePool(path: path, configuration: configuration)
+  } else if context == .test {
+    let path = URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
+    database = try DatabasePool(path: path, configuration: configuration)
+  } else {
+    database = try DatabaseQueue(configuration: configuration)
+  }
   return database
 }
```

### Step 4: Migrate database

Now that the database connection is created we can migrate the database. GRDB provides all the 
tools necessary to perform [database migrations][grdb-migration-docs], but the basics include
creating a `DatabaseMigrator`, registering migrations with it, and then using it to migrate the
database connection:

```diff
 func appDatabase() throws -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
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
   let database: any DatabaseWriter
   if context == .live {
     let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
     logger.info("open \(path)")
     database = try DatabasePool(path: path, configuration: configuration)
   } else if context == .test {
     let path = URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
     database = try DatabasePool(path: path, configuration: configuration)
   } else {
     database = try DatabaseQueue(configuration: configuration)
   }
+  var migrator = DatabaseMigrator()
+  #if DEBUG
+    migrator.eraseDatabaseOnSchemaChange = true
+  #endif
+  migrator.registerMigration("Create sports table") { db in
+    // ...
+  }
+  migrator.registerMigration("Create teams table") { db in
+    // ...
+  }
+  try migrator.migrate(database)
   return database
 }
```

As your application evolves you will register more and more migrations with the migrator.

That is all it takes to create, configure and migrate a database connection. Here is the code
we have just written in one snippet:

```swift
import OSLog
import SharingGRDB

func appDatabase() throws -> any DatabaseWriter {
   @Dependency(\.context) var context
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
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
   let database: any DatabaseWriter
   if context == .live {
     let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
     logger.info("open \(path)")
     database = try DatabasePool(path: path, configuration: configuration)
   } else if context == .test {
     let path = URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
     database = try DatabasePool(path: path, configuration: configuration)
   } else {
     database = try DatabaseQueue(configuration: configuration)
   }
  var migrator = DatabaseMigrator()
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create sports table") { db in
    // ...
  }
  migrator.registerMigration("Create teams table") { db in
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
import SharingGRDB
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
import SharingGRDB
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
