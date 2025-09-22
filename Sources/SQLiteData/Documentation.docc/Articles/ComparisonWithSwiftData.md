# Comparison with SwiftData

Learn how SQLiteData compares to SwiftData when solving a variety of problems.

## Overview

The SQLiteData library can replace SwiftData for many kinds of apps, and provide additional
benefits such as direct access to the underlying SQLite schema, and better integration outside of
SwiftUI views (including UIKit, `@Observable` models, _etc._). This article describes how the two
approaches compare in a variety of situations, such as setting up the data store, fetching data,
associations, and more.

  * [Defining your schema](#Defining-your-schema)
  * [Setting up external storage](#Setting-up-external-storage)
  * [Fetching data for a view](#Fetching-data-for-a-view)
  * [Fetching data for an @Observable model](#Fetching-data-for-an-Observable-model)
  * [Dynamic queries](#Dynamic-queries)
  * [Creating, updating and deleting data](#Creating-updating-and-deleting-data)
  * [Associations](#Associations)
  * [Booleans and enums](#Booleans-and-enums)
  * [Migrations](#Migrations)
    * [Lightweight migrations](#Lightweight-migrations)
    * [Manual migrations](#Manual-migrations)
  * [CloudKit](#CloudKit)
  * [Supported Apple platforms](#Supported-Apple-platforms)

### Defining your schema

Both SQLiteData and SwiftData come with tools to expose your data types' fields to the compiler
so that type-safe and schema-safe queries can be written. SQLiteData uses another library of ours
to provide these tools, called [StructuredQueries][sq-gh], and its `@Table` macro works similarly
to SwiftData's `@Model` macro:

[sq-gh]: http://github.com/pointfreeco/swift-structured-queries

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Table
    struct Item {
      let id: UUID
      var title = ""
      var isInStock = true
      var notes = ""
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Model
    class Item {
      var title: String
      var isInStock: Bool
      var notes: String
      init(
        title: String = "",
        isInStock: Bool = true,
        notes: String = ""
      ) {
        self.title = title
        self.isInStock = isInStock
        self.notes = notes
      }
    }
    ```
  }
}

Some key differences:

  * The `@Table` macro works with struct data types, whereas `@Model` only works with classes.
  * Because the `@Model` version of `Item` is a class it is necessary to provide an initializer.
  * The `@Model` version of `Item` does not need an `id` field because SwiftData provides a
    `persistentIdentifier` to each model.

See the [documentation][sq-defining-schema] from StructuredQueries for more information on how
to define your schema.

[sq-defining-schema]: https://swiftpackageindex.com/pointfreeco/swift-structured-queries/main/documentation/structuredqueriescore/definingyourschema

### Setting up external storage

Both SQLiteData and SwiftData require some work to be done at the entry point of the app in order
to set up the external storage system that will be used throughout the app. In SQLiteData we use
the `prepareDependencies` function to set up the default database used, and in SwiftUI you construct
a `ModelContainer` and propagate it through the environment:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @main
    struct MyApp: App {
      init() {
        prepareDependencies {
          // Create/migrate a database
          let db = try! DatabaseQueue(/* ... */)
          $0.defaultDatabase = db
        }
      }
      // ...
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @main
    struct MyApp: App {
      let container = {
        // Create/configure a container
        try! ModelContainer(/* ... */)
      }()

      var body: some Scene {
        WindowGroup {
          ContentView()
            .modelContainer(container)
        }
      }
    }
    ```
  }
}

See <doc:PreparingDatabase> for more advice on the various ways you will want to create and
configure your SQLite database for use with SQLiteData.

### Fetching data for a view

To fetch data from a SQLite database you use the `@FetchAll` property wrapper in SQLiteData,
whereas you use the `@Query` macro with SwiftData:

@Row {
  @Column {
    ```swift
    // SQLiteData
    struct ItemsView: View {
      @FetchAll(Item.order(by: \.title))
      var items

      var body: some View {
        ForEach(items) { item in
          Text(item.name)
        }
      }
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    struct ItemsView: View {
      @Query(sort: \Item.title)
      var items: [Item]

      var body: some View {
        ForEach(items) { item in
          Text(item.name)
        }
      }
    }
    ```
  }
}

The `@FetchAll` property wrapper takes a variety of options and allows you to write queries using a
type-safe and schema-safe builder syntax, or you can write safe SQL strings that are schema-safe and
protect you from SQL injection.

The library also ships a few other property wrappers that have no equivalent in SwiftData. For
example, the [`@FetchOne`](<doc:FetchOne>) property wrapper allows you to query for just a single
value, which can be useful for computing aggregate data:

```swift
@FetchOne(Item.where(\.isInStock).count())
var inStockItemsCount = 0
```

And the [`@Fetch`](<doc:Fetch>) property wrapper allows you to execute multiple queries in a single
database transaction to gather your data into a single data type. SwiftData has no equivalent for
either of these operations. See <doc:Fetching> for more detailed information on how to fetch
data from your database using the tools of this library.

### Fetching data for an @Observable model

There are many reasons one may want to move logic out of the view and into an `@Observable` model,
such as allowing to unit test your feature's logic, and making it possible to deep link in your
app. The `@FetchAll` property warpper, and other [data fetching tools](<doc:Fetching>) work just as
well in an `@Observable` model as they do in a SwiftUI view. The state held in the property wrapper
automatically updates when changes are made to the database.

The `@Query` macro, on the other hand, only works in SwiftUI views. This means if you want to move
some of your feature's logic out of the view and into an `@Observable` model you must recreate
its functionality from scratch:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Observable
    class FeatureModel {
      @ObservationIgnored
      @FetchAll(Item.order(by: \.title)) var items
      // ...
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Observable
    class FeatureModel {
      var modelContext: ModelContext
      var items = [Item]()
      var observer: (any NSObjectProtocol)!

      init(modelContext: ModelContext) {
        self.modelContext = modelContext
        observer = NotificationCenter.default.addObserver(
          forName: ModelContext.willSave,
          object: modelContext,
          queue: nil
        ) { [weak self] _ in
          self?.fetchItems()
        }
        fetchItems()
      }

      deinit {
        NotificationCenter.default.removeObserver(observer)
      }

      func fetchItems() {
        do {
          items = try modelContext.fetch(
            FetchDescriptor<Item>(sortBy: [SortDescriptor(\.title)])
          )
        } catch {
          // Handle error
        }
      }
      // ...
    }
    ```
  }
}

> Note: It is necessary to annotate `@FetchAll` with `@ObservationIgnored` when using the
> `@Observable` macro due to how macros interact with property wrappers. However, `@FetchAll`
> handles its own observation, and so state will still be observed when accessed in a view.

### Dynamic queries

Dynamic queries are important for updating the data fetched from the database based on information
that is not known at compile time. The prototypical example of this is a UI that allows the user to
search for rows in a table:

@Row {
  @Column {
    ```swift
    // SQLiteData
    struct ItemsView: View {
      @State var searchText = ""
      @FetchAll var items: [Item]

      var body: some View {
        ForEach(items) { item in
          Text(item.name)
        }
        .searchable(text: $searchText)
        .task(id: searchText) {
          await updateSearchQuery()
        }
      }

      func updateSearchQuery() {
        await $items.load(
          .fetchAll(
            Item.where {
              $0.title.contains(searchText)
            }
          )
        )
      }
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    struct ItemsView: View {
      @State var searchText = ""

      var body: some View {
        SearchResultsView(
          searchText: searchText
        )
        .searchable(text: $searchText)
      }
    }

    struct SearchResultsView: View {
      @Query var items: [Item]

      init(searchText: String) {
        _items = Query(
          filter: #Predicate<Item> {
            $0.title.contains(searchText)
          }
        )
      }

      var body: some View {
        ForEach(items) { item in
          Text(item.name)
        }
      }
    }
    ```
  }
}

Note that the SwiftData version of this code must have two views. The outer view, `ItemsView`,
holds onto the `searchText` state that the user can change and uses the `searchable` SwiftUI view
modifier. Then, the inner view, `SearchResultsView`, holds onto the `@Query` state so that it can
initialize with a dynamic predicate based on the `searchText`. These two views are necessary
because `@Query` state is not mutable after it is initialized. The only way to change `@Query`
state is if the view holding it is reinitialized, which requires a parent view to recreate the
child view.

On the other hand, the same UI made with `@FetchAll` can all happen in a single view. We can
hold onto the `searchText` state that the user edits, use the `searchable` view modifier for the
UI, and update the `@FetchAll` query when the `searchText` state changes.

See <doc:DynamicQueries> for more information on how to execute dynamic queries in the library.

### Creating, updating and deleting data

To create, update and delete data from the database you must use the `defaultDatabase` dependency.
This is similar to what one does with SwiftData too, where all changes to the database go through
the `ModelContext` and is not done through the `@Query` macro at all.

For example, to get access to `defaultDatabase`, you use the `@Dependency` property wrapper:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Dependency(\.defaultDatabase) var database
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Environment(\.modelContext) var modelContext
    ```
  }
}

Then, to create a new row in a table you use the `write` and `insert` methods from SQLiteData:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Dependency(\.defaultDatabase) var database

    try database.write { db in
      try Item.insert(Item(/* ... */))
        .execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Environment(\.modelContext) var modelContext

    let newItem = Item(/* ... */)
    modelContext.insert(newItem)
    try modelContext.save()
    ```
  }
}

To update an existing row you can use the `write` and `update` methods from SQLiteData:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Dependency(\.defaultDatabase) var database

    existingItem.title = "Computer"
    try database.write { db in
      try Item.update(existingItem).execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Environment(\.modelContext) var modelContext

    existingItem.title = "Computer"
    try modelContext.save()
    ```
  }
}

And to delete an existing row, you can use the `write` and `delete` methods from SQLiteData:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Dependency(\.defaultDatabase) var database

    try database.write { db in
      try Item.delete(existingItem).execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Environment(\.modelContext) var modelContext

    modelContext.delete(existingItem))
    try modelContext.save()
    ```
  }
}

### Associations

The biggest difference between SwiftData and SQLiteData is that SwiftData provides tools for an
Object Relational Mapping (ORM), whereas SQLiteData is largely just a nice API for interacting with SQLite
directly.

For example, SwiftData allows you to model a `Sport` type that belongs to many `Team`s like
so:

```swift
@Model class Sport {
  @Relationship(inverse: \Team.sport)
  var teams = [Team]()
}
@Model class Team {
  var sport: Sport
}
```

The data for `Sport` and `Team` are stored in separate tables of a SQLite database, and if you
fetch a `Sport`, you can immediate access the `teams` property on the sport in order to execute
another query to fetch all of the sport's teams:

```swift
let sport = try modelContext.fetch(FetchDescriptor<Sport>())
for sport in sports {
  print("\(sport) has \(sport.teams.count) teams")
}
```

This is powerful, but it can also lead to a number of problems in apps. First, the only way for this
mechanism to work is for `Team` and `Sport` to be classes, and the `@Model` macro enforces that.
Second, because the SQLite execution is so abstracted from us, it makes it easy to execute many,
_many_ queries, leading to inefficient code. In this case, we are first executing a query to
get all sports, and then executing a query for each sport to get the number of teams in each
sport. And on top of that, we are loading every team into memory just to compute the number of
teams.  We don't actually need any data from the team, only their aggregate count.

SQLiteData does not provide these kinds of tools, and for good reason. Instead, if you know you
want to fetch all of the teams with their corresponding sport, you can simply perform a single
query that joins the two tables together:

```swift
@Selection
struct SportWithTeamCount {
  let sport: Sport
  let teamCount: Int
}

@FetchAll(
  Sport
    .group(by: \.id)
    .leftJoin(Team.all) { $0.id.eq($1.sportID) }
    .select {
      SportWithTeamCount.Columns(sport: $0, teamCount: $1.count())
    }
)
var sportsWithTeamCounts
```

If either of the "sports" or "teams" tables change, this query will be executed again and the
state will update to the freshest values.

This style of handling associations does require you to be knowledgable in SQL to wield it
correctly, but that is a benefit! SQL (and SQLite) are some of the most proven pieces of
technologies in the history of computers, and knowing how to wield their powers is a huge benefit.

### Booleans and enums

While it may be hard to believe at first, SwiftData does not fully support boolean or enum values
for fields of a model. Take for example this following model:

```swift
@Model
class Reminder {
  var isCompleted = false
  var priority: Priority?
  init(isCompleted: Bool = false, priority: Priority? = nil) {
    self.isCompleted = isCompleted
    self.priority = priority
  }

  enum Priority: Int, Codable {
    case low, medium, high
  }
}
```

This model compiles just fine, but it is very limited in what you can do with it. First, you cannot
sort by the `isCompleted` column when constructing a `@Query` because `Bool` is not `Comparable`:

```swift
@Query(sort: [SortDescriptor(\.isCompleted)])
var reminders: [Reminder]  // 🛑
```

There is no way to sort by boolean columns in SwiftData.

Further, you cannot filter by enum columns, such as selecting only high priority reminders:

```swift
@Query(filter: #Predicate { $0.priority == Priority.high })
var highPriorityReminders: [Reminder]
```

This will compile just fine yet crash at runtime. The only way to make this code work is to greatly
weaken your model by modeling both `isCompleted` _and_ `priority` as integers:

```swift
@Model
class Reminder {
  var isCompleted = 0
  var priority: Int?
  init(isCompleted: Int = 0, priority: Int? = nil) {
    self.isCompleted = isCompleted
    self.priority = priority
  }
}

@Query(
  filter: #Predicate { $0.priority == 2 },
  sort: [SortDescriptor(\.isCompleted)]
)
var highPriorityReminders: [Reminder]
```

This will now work, but of course these fields can now hold over 9 quintillion possible values when
only a few values are valid.

On the other hand, booleans and enums work just fine in SQLiteData:

```swift
@Table
struct Reminder {
  var isCompleted = false
  var priority: Priority?
  enum Priority: Int, QueryBindable {
    case low, medium, high
  }
}

@FetchAll(
  Reminder
    .where { $0.priority == Priority.high }
    .order(by: \.isCompleted)
)
var reminders
```

This compiles and selects all high priority reminders ordered by their `isCompleted` state. You
can even leave off the type annotation for `reminders` because it is inferred from the query.

### Migrations

[grdb-migration-docs]: https://swiftpackageindex.com/groue/grdb.swift/master/documentation/grdb/migrations

[Migrations in GRDB][grdb-migration-docs] and SwiftData are very different. GRDB makes migrations
explicit where you make direct changes to the schemas in your database. This includes creating
tables, adding, removing or altering columns, adding or removing indices, and more.

Whereas SwiftData has two flavors of migrations. The simplest, "lightweight" migrations, work
implicitly by comparing your data types to the database schema and updating the schema accordingly.
That cannot always work, and so there are "manual" migrations where you explicitly describe how
to change the database schema.

#### Lightweight migrations

Lightweight migrations in SwiftData work for simple situations, such as adding a new data type:

@Row {
  @Column {
    ```swift
    // SQLiteData
    @Table
    struct Item {
      let id: UUID
      var title = ""
      var isInStock = true
    }

    migrator.registerMigration("Create 'items' table") { db in
      try #sql(
        """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "isInStock" INTEGER NOT NULL DEFAULT 1
        )
        """
      )
      .execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Model
    class Item {
      var title = ""
      var isInStock = true
    }
    ```
  }
}

Note that in GRDB we must explicitly create the table, specify its columns, as well as its
constraints, such as if it is nullable or has a default value.

Similarly, adding a column to a data type is also a lightweight migration in SwiftData, such as
adding a `description` field to the `Item` type:

@Row {
  @Column {
    ```swift
    @Table
    struct Item {
      let id: UUID
      var title = ""
      var description = ""
      var isInStock = true
    }

    migrator.registerMigration("Add 'description' column to 'items'") { db in
      try #sql(
        """
        ALTER TABLE "items"
        ADD COLUMN "description" TEXT
        """
      )
      .execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @Model
    class Item {
      var title = ""
      var description = ""
      var isInStock = true
    }
    ```
  }
}

In each of these cases, the lightweight migration of SwiftData is less code and the actual
migration logic is implicit and hidden away from you.

#### Manual migrations

However, unfortunately, not all migrations can be "lightweight". In fact, from our experience,
real world apps tend to require complex logic when performing most migrations. Something as simple
as changing an optional field to be a non-optional field cannot be done as a lightweight migration
since SwiftData does not know what value to insert into the database for any rows with a NULL
value. Even adding a unique index to a column is not possible because that may introduce constraint
errors if two rows have the same value.

For the times that a lightweight migration is not possible in SwiftData, one must turn to
"manual" migrations via the `VersionedSchema` protocol. As an example, consider adding a unique
index on the "title" column of the "items" table.

In GRDB this is a simple two-step process:

  1. Delete all items that have duplicate titles keeping the first created. Alternatively one could
    rename the titles to
    incorporate a "#" suffix to differentiate between items with the same name.
  1. Add the unique index.

In SwiftData this is a much more involved process since migrations are implicitly tied to the
structure of your data types. The overall steps to follow are as such:

  1. Create a type that conforms to the `VersionedSchema` protocol, which represents the current
     schema of the `Item` model. It is also customary to nest the `Item` model in this type.
  1. Create another type that conforms to the `VersionedSchema` protocol to represents the
     new schema of the `Item` data type.
  1. Duplicate the entire `@Model` data type so that you can specify the unique index. This type
     will need a new name so as to not conflict with the current, and so often it is nested in
     the type created in the previous step.
  1. Because you now have different data types representing `Item` it is customary to add a
     type alias that represents the most "current" version of the `Item`.
  1. Create a type that conforms to the `SchemaMigrationPlan` which allows you to specify the
    "stages" that will be executed when a migration is performed.
  1. Create a `MigrationStage` to implement the logic you want to perform when a migration occurs.
    This is where you will delete the items with duplicate titles, or however you want to handle
    the duplicates.
  1. Provide the migration plan to the `ModelContainer` you create at the entry point of your app.

@Row {
  @Column {
    ```swift
    // SQLiteData
    migrator.registerMigration("Make 'title' unique") { db in
      // 1️⃣ Delete all items that have duplicate title, keeping the first created one:
      try Item
        .delete()
        .where {
          !$0.id.in(
            Item
              .select { $0.id.min() }
              .group(by: \.title)
          )
        }
        .execute()
      // 2️⃣ Create unique index
      try #sql(
        """
        CREATE UNIQUE INDEX
        "items_title" ON "items" ("title")
        """
      )
      .execute(db)
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    // 1️⃣ Create a type to conform to VersionedSchema and nest current Item inside:
    enum Schema1: VersionedSchema {
      static var versionIdentifier = Schema.Version(1, 0, 0)
      static var models: [any PersistentModel.Type] { [Item.self] }
      @Model
      class Item {
        var title = ""
        var isInStock = true
      }
    }

    // 2️⃣ Create type to conform to VersionedSchema:
    enum Schema2: VersionedSchema {
      static var versionIdentifier = Schema.Version(2, 0, 0)
      static var models: [any PersistentModel.Type] { [Item.self] }

      // 3️⃣ Duplicate Item type for new schema version with unique index:
      @Model
      class Item {
        @Attribute(.unique)
        var title = ""
        var isInStock = true
      }
    }

    // 4️⃣ Create a type alias for the newest Item schema:
    typealias Item = Schema2.Item

    // 5️⃣ Create a type to conform to the SchemaMigrationPlan protocol:
    enum MigrationPlan: SchemaMigrationPlan {
      static var schemas: [any VersionedSchema.Type] {
        [
          Schema1.self,
          Schema2.self
        ]
      }

      // 6️⃣ Create MigrationStage values to implement the logic for migration from one schema
      //    to the next:
      static var stages: [MigrationStage] {
        [
          MigrationStage.custom(
            fromVersion: Schema1.self,
            toVersion: Schema2.self
          ) { context in
            // Delete items with duplicate titles, keeping the first created.
            // Fetch all items but hydrating only their titles:
            var fetchDescriptor = FetchDescriptor<Item>()
            fetchDescriptor.propertiesToFetch = [\.title]
            let items = try context.fetch(fetchDescriptor)
            // Keep track of unique titles so that we know when to delete an item:
            var uniqueTitles: Set<String> = []
            for item in items {
              if uniqueTitles.contains(item.title) {
                // If title is not unique, delete the item:
                context.delete(item)
              } else {
                // If title is unique, add it to the set so that we know to delete
                // items with this title:
                uniqueTitles.insert(item.title)
              }
            }
            try context.save()
          } didMigrate: { _ in
          }
        ]
      }
    }

    // 7️⃣ Create ModelContainer with migration plan in entry point of app:
    @main
    struct MyApp: App {
      let container: ModelContainer
      init() {
        container = try ModelContainer(
          for: Schema(versionedSchema: Schema2.self),
          migrationPlan: MigrationPlan.self
        )
      }
      // ...
    }
    ```
  }
}

Some things to note about the above comparison:

  * In the SQLite version we can make use of SQL's powerful features for easily deleting all items
    with a duplicate title (keeping the first) by using a subquery.
  * The SwiftData migration is many, many times longer than the equivalent SQLite version involving
    many intricate steps that are hard to remember and easy to get wrong.
  * Because database schemas are tightly coupled to type definitions we have no choice but to
    duplicate our data type so that we can apply the `@Attribute(.unique)` macro.
  * Further, we will need to move all helper methods and computed properties from the previous
    version of the data type to the new version.
  * The work in step #6 that deletes items if they have a duplicate titles is very inefficient, but
    it's not possible to make much more efficient. SwiftData does not provide us with tools to run
    raw SQL on the tables, and so we have no choice but to load all of the items into memory and
    manually check for unique titles. This is memory intensive and CPU intensive work and may
    require extra attention if there are thousands of items in the table. On the other hand, SQLite
    can perform this work efficiently on millions of rows without ever loading a single `Item` into
    memory.

So, while lightweight migrations are one of the "magical" features of SwiftData, we feel that
complex "manual" migrations are common enough that one should optimize for them rather than the
other way around.

### CloudKit

Both SQLiteData and SwiftData support basic synchronization of models to CloudKit so that data
can be made available on all of a user's devices. However, SQLiteData also supports sharing records
with other iCloud users, and it exposes the underlying CloudKit data types (e.g. `CKRecord`) so
that you can interact directly with CloudKit if needed.

Setting up a database and sync engine in SQLiteData isn't much different from setting up a
SwiftData stack with CloudKit. The main difference is that one must explicitly provide the
container identifier in SQLiteData because SwiftData has been privileged in being able to
inspect the Entitlements.plist in order to automatically extract that information:

@Row {
  @Column {
    ```swift
    // SQLiteData
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

      …
    }
    ```
  }
  @Column {
    ```swift
    // SwiftData
    @main
    struct MyApp: App {
      let modelContainer: ModelContainer
      init() {
        let schema = Schema([
          Reminder.self,
          RemindersList.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema)
        modelContainer = try! ModelContainer(
          for: schema,
          configurations: [modelConfiguration]
        )
      }

      …
    }
    ```
  }
}

Once this initial set up is performed, all insertions, updates and deletions from the database
will be automatically synchronized to CloudKit.

SwiftData also has a few limitations in what features you are allowed to use in your schema:

* Unique constraints are not allowed on columns.
* All properties on a model must be optional or have a default value.
* All relationships must be optional.

SQLiteData has only one of these limitations:

* Unique constraints on columns (except for the primary key) cannot be upheld on a distributed
schema. For example, if you have a `Tag` table with a unique `title` column, then what
are you to do if two different devices create a tag with the title "family" at the same time?
See <doc:CloudKit#Uniqueness-constraints> for more information.
* Columns on freshly created tables do not need to have default values or be nullable. Only
newly added columns to existing tables need to either be nullable or have a default. See
<doc:CloudKit#Adding-columns> for more info.
* Relationships on freshly created do not need to be nullable. Only newly added columns to
existing tables need to be nullable. See <doc:CloudKit#Adding-columns> for more info.

For more information about requirements of your schema in order to use CloudKit synchronization,
see <doc:CloudKit#Designing-your-schema-with-synchronization-in-mind> and
<doc:CloudKit#Backwards-compatible-migrations>, and for more general
information about CloudKit synchronization, see <doc:CloudKit>.

### Supported Apple platforms

SwiftData and the `@Query` macro require iOS 17, macOS 14, tvOS 17, watchOS 10 and higher, and
some newer features require even more recent versions of iOS.

Meanwhile, SQLiteData has a broad set of deployment targets supporting all the way back to iOS 13,
macOS 10.15, tvOS 13, and watchOS 6. This means you can use these tools on essentially any
application today with no restrictions.
