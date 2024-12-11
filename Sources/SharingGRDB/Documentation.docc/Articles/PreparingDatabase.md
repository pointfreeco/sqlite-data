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

### Step 1: Static database connection

We will begin by defining a static `appDatabase` that represents a connection to a local database
stored on disk. We find that the place to put this value is on an extension of the protocol that
abstracts the database connection from GRDB, `DatabaseWriter`:

```swift
extension DatabaseWriter where Self == DatabaseQueue {
  static var appDatabase: Self {
    // ...
  }
}
```

> Note: Here we have used a [`DatabaseQueue`][db-q-docs], but it is also possible to use a
> [`DatabasePool`][db-pool-docs].

[db-q-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/databasequeue
[db-pool-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/databasepool

### Step 2: Create configuration

Inside this static variable we can create a [`Configuration`][config-docs] value that is used to
configure the database. We highly recommend always turning on 
[foreign key](https://www.sqlite.org/foreignkeys.html) constraints to protect the integrity of your
data:

```diff
 static var appDatabase: Self {
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
information when the app is running on a user's device:

```diff
 static var appDatabase: Self {
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
+  #if DEBUG
+    configuration.prepareDatabase { db in
+      db.trace(options: .profile) {
+        print($0.expandedDescription)
+      }
+    }
+  #endif
 }
```

> Note: `expandedDescription` will also print the data bound to the SQL statement, which can include
> sensitive data that you may not want to leak. In this case we feel it is ok because everything
> is surrounded in `#if DEBUG`, but it is something to be careful of in your own apps.

For more information on configuring tracing, see [GRDB's documentation][trace-docs] on the
matter.

[config-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/configuration
[trace-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/database/trace(options:_:)

### Step 3: Create database connection

Once a `Configuration` value is set up we can construct the actual database connection. The simplest
way to do this is to construct the database connection for a path on the file system like so:

```diff
 static var appDatabase: Self {
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
   #if DEBUG
     configuration.prepareDatabase { db in
       db.trace(options: .profile) {
         print($0.expandedDescription)
       }
     }
   #endif
+  let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
+  let databaseQueue = try! DatabaseQueue(path: path, configuration: configuration)
+  return databaseQueue
 }
```

However, in tests and Xcode previews we would like to use an in-memory database so that each test
and preview gets their own sandboxed database. To do this we can turn `appDatabase` into a static
function that takes an `inMemory` option (that defaults to `false`) so that it can be configured
when setting up the database:

```diff
-static var appDatabase: Self {
+static func appDatabase(inMemory: Bool = false) -> Self {
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
   #if DEBUG
     configuration.prepareDatabase { db in
       db.trace(options: .profile) {
         print($0.expandedDescription)
       }
     }
   #endif
+  let databaseQueue: DatabaseQueue
+  if inMemory {
+    databaseQueue = try! DatabaseQueue(configuration: configuration)
+  } else {
+    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
+    databaseQueue = try! DatabaseQueue(path: path, configuration: configuration)
+  }
   return databaseQueue
 }
```

> Tip: An alternative to an `inMemory` argument is to use `@Dependency(\.context)` to determine
> if the code is running in tests or previews:
>
> ```diff
> -static func appDatabase(inMemory: Bool = false) -> Self {
> +static var appDatabase: Self {
>    var configuration = Configuration()
>    configuration.foreignKeysEnabled = true
>    #if DEBUG
>      configuration.prepareDatabase { db in
>        db.trace(options: .profile) {
>          print($0.expandedDescription)
>        }
>      }
>    #endif
> +  @Dependency(\.context) var context
>    let databaseQueue: DatabaseQueue
> -  if inMemory {
> +  if context != .live {
>      databaseQueue = try! DatabaseQueue(configuration: configuration)
>    } else {
>      let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
>      databaseQueue = try! DatabaseQueue(path: path, configuration: configuration)
>    }
>    return databaseQueue
>  }
> ```

### Step 4: Migrate database

Now that the database connection is created we can migrate the database. GRDB provides all the 
tools necessary to perform [database migrations][grdb-migration-docs], but the basics include
creating a `DatabaseMigrator`, registering migrations with it, and then using it to migrate the
database connection:

```diff
 static func appDatabase(inMemory: Bool = false) -> Self {
   var configuration = Configuration()
   configuration.foreignKeysEnabled = true
   #if DEBUG
     configuration.prepareDatabase { db in
       db.trace(options: .profile) {
         print($0.expandedDescription)
       }
     }
   #endif
   let databaseQueue: DatabaseQueue
   if inMemory {
     databaseQueue = try! DatabaseQueue(configuration: configuration)
   } else {
     let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
     databaseQueue = try! DatabaseQueue(path: path, configuration: configuration)
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
+  try! migrator.migrate(databaseQueue)
   return databaseQueue
 }
```

As your application evolves you will register more and more migrations with the migrator.

That is all it takes to create, configure and migrate a database connection. Here is the code
we have just written in one snippet:

```swift
static func appDatabase(inMemory: Bool = false) -> Self {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = true
  #if DEBUG
    configuration.prepareDatabase { db in
      db.trace(options: .profile) {
        print($0.expandedDescription)
      }
    }
  #endif
  let databaseQueue: DatabaseQueue
  if inMemory {
    databaseQueue = try! DatabaseQueue(configuration: configuration)
  } else {
    let path = URL.documentsDirectory.appending(component: "db.sqlite").path()
    databaseQueue = try! DatabaseQueue(path: path, configuration: configuration)
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
  try! migrator.migrate(databaseQueue)
  return databaseQueue
}
```

[grdb-migration-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/migrations

### Step 5: Set database connection in entry point

Once you have defined your `appDatabase` helper for creating a database connection, you must set
it as the ``Dependencies/DependencyValues/defaultDatabase`` for your app in its entry point. This
can be in done in SwiftUI by using `prepareDependencies` in the `init` of your `App` conformance:

```swift
import SharingGRDB
import SwiftUI

@main
struct MyApp: App {
  init() {
    prepareDependencies { 
      $0.defaultDatabase = .appDatabase()
    }
  }
  // ...
}
```

> Important: You can only prepare the default database a single time in the lifetime of your
> application. It is best to do this as early as possible after the app launches.

If using app or scene delegates, then you can prepare the
``Dependencies/DependencyValues/defaultDatabase`` in one of those conformances:

```swift
import SharingGRDB
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
  func applicationDidFinishLaunching(_ application: UIApplication) {
    prepareDependencies {
      $0.defaultDatabase = .appDatabase()
    }
  }
  // ...
}
```

And if using something besides UIKit or SwiftUI, then simply set the
``Dependencies/DependencyValues/defaultDatabase`` as early as possible in the application's 
lifecycle.

It is also important to prepare the database in Xcode previews, but in this situation you will want
to use an in-memory database. This can be done like so:

```swift
#Preview {
  let _ = prepareDependencies { 
    $0.defaultDatabase = .appDatabase(inMemory: true)
  }
  // ...
}
```

And similarly, in tests you will also want to use an in-memory database. This can be done using the
`.dependency` testing trait:

```swift
@Test(.dependency(\.defaultDatabase, .appDatabase(inMemory: true))
func feature() {
  // ...
}
```
