# Package traits

Learn about the opt-in package traits that SQLiteData provides, including support for enum tables,
tagged identifiers, and more.

## Overview

SQLiteData uses [package traits], a Swift 6.1 feature, to provide opt-in functionality that extends
the core library. Traits allow the library to integrate with other packages, and to introduce new
behavior in a backwards-compatible manner, without imposing extra dependencies or
source changes on projects that do not need them.

[package traits]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md

The library currently provides the following traits:

  * [`CasePaths`](#CasePaths): Adds support for single-table inheritance _via_ "enum" tables.
  * [`ColumnCoding`](#ColumnCoding): Aligns the `Codable` conformance of tables and selections
    with their column names.
  * [`LazyInitializableByDefault`](#LazyInitializableByDefault): Makes draft properties with no
    default value lazy-initializable.
  * [`StrictDecoding`](#StrictDecoding): Throw an error, rather than coerce, when decoding a column
    whose storage type does not match the expected type.
  * [`SuppressPlatformSQLiteAvailability`](#SuppressPlatformSQLiteAvailability): Suppresses
    `@available` checks on APIs that depend on a newer version of SQLite than the one bundled with
    the platform.
  * [`Tagged`](#Tagged): Adds support for type-safe identifiers.

To enable a trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["CasePaths", "ColumnCoding", "LazyInitializableByDefault"]
 ),
```

…or enable the trait from your Xcode project's package dependencies.

### CasePaths

The `CasePaths` trait unlocks the ability to use enums as a domain modeling tool for your table
schema, which can help you emulate "inheritance" for your tables without the burden of using
reference types. For example, a table of attachments, where an attachment can either be a link, a
note, or an image, can be modeled as a struct that holds onto an enum of the possible kinds:

```swift
@Table struct Attachment {
  let id: Int
  let kind: Kind

  @Selection
  enum Kind {
    case link(URL)
    case note(String)
    case image(URL)
  }
}
```

This functionality is powered by our [CasePaths] library, which enhances enumerations with key
path-like functionality, and so enabling the trait adds a dependency on that package.

[CasePaths]: https://github.com/pointfreeco/swift-case-paths

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["CasePaths"]
 ),
```

> Important: On Swift toolchains earlier than 6.3, you _must_ also explicitly depend on the
> `swift-case-paths` package to work around a SwiftPM bug in which dependencies introduced by a
> trait are not resolved:
>
> ```diff
> +.package(
> +  url: "https://github.com/pointfreeco/swift-case-paths",
> +  from: "1.0.0"
> +),
> ```
>
> This bug is fixed in Swift 6.3, where the explicit dependency can be omitted.

See [Enum tables](<doc:DefiningYourSchema#Enum-tables>) for more information on modeling your
schema with enums.

### ColumnCoding

The `ColumnCoding` trait aligns the `Codable` conformance of tables and selections with their
column names. By default, Swift synthesizes coding keys for `Codable` types from a type's property
names, which can drift from the column names the `@Table` and `@Selection` macros use when columns
are renamed:

```swift
@Table
struct Reminder: Codable {
  let id: Int
  @Column("is_completed")
  var isCompleted = false
}
```

Without the trait enabled, the above type encodes its `isCompleted` property under the
`"isCompleted"` key, even though the database column is named `"is_completed"`. With the trait
enabled, the macro generates a `CodingKeys` conformance that matches the schema:

```swift
private enum CodingKeys: String, CodingKey {
  case id
  case isCompleted = "is_completed"
}
```

This keeps external representations of your data types, such as JSON, consistent with your schema.
Because the macro takes over `CodingKeys` generation, defining a custom `CodingKeys` type on a
table or selection is a compile-time diagnostic when the trait is enabled.

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["ColumnCoding"]
 ),
```

> Important: In the next major release of SQLiteData this be the default behavior. Add this trait
> and update your tables to get a head start on compatibility.

### LazyInitializableByDefault

The `LazyInitializableByDefault` trait makes every table property with no default value
lazy-initializable in its generated `Draft` type, matching the lazy initialization of the draft's
primary key. This means such fields become optional in the draft and can be omitted when creating
one, which is useful for fields whose values are assigned by the database, such as
created/updated timestamps and foreign keys:

```swift
@Table
struct User {
  let id: UUID
  var name = ""
  let createdAt: Date
  let updatedAt: Date
}

let draft = User.Draft(name: "Blob")
```

Without the trait enabled, the above would fail to compile because `createdAt` and `updatedAt`
must be provided, unless each property is explicitly annotated with
`@Column(lazyInitializable: true)`.

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["LazyInitializableByDefault"]
 ),
```

See [Lazy initialization](<doc:TableDrafts#Lazy-initialization>) for more information on
lazy-initializable draft properties.

> Important: In a future version of SQLiteData this will become the default behavior, and you will
> be able to opt out of it for a particular property with `@Column(lazyInitializable: false)`.
> Enable the trait today to prepare for that future release.

### StrictDecoding

The `StrictDecoding` trait throws errors during decoding when a Swift type being decoded does not
match the affinity of the SQLite data type. This helps align the data you store with the data you
load into your application, and prevents accidentally data corruption.

The trait is disabled by default for backwards compatibility, and instead of throwing an error, an
issue is reported to the developer.

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["StrictDecoding"]
 ),
```

> Important: In a future version of SQLiteData this will become the default behavior. Enable the
> trait today to prepare for that future release.

### SuppressPlatformSQLiteAvailability

Some of the library's APIs correspond to SQLite features that are newer than the version of SQLite
bundled with certain Apple platforms. For example, the JSONB family of functions requires SQLite
3.45, which first shipped with iOS 26, macOS 26, tvOS 26, and watchOS 26. Such APIs are annotated
with `@available` attributes so that the compiler prevents you from invoking a SQLite function that
does not exist on an older OS:

```swift
Reminder.select { $0.title.jsonbGroupArray() }
// 🛑 'jsonbGroupArray' is only available in iOS 26 or newer
```

These checks only apply to the system SQLite, though. If your app links against its own copy of
SQLite instead, such as a custom build of SQLite or SQLCipher, these restrictions are unnecessary,
and you can enable the `SuppressPlatformSQLiteAvailability` trait to remove them.

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["SuppressPlatformSQLiteAvailability"]
 ),
```

> Warning: Only enable this trait if your app embeds a version of SQLite that supports the features
> you use. If you enable it while relying on the system SQLite, queries that use newer functions
> will compile but fail at runtime on older OS versions.

### Tagged

The `Tagged` trait adds support for the [Tagged] library, which provides lightweight syntax for
introducing type-safe identifiers (and more) to your models. With the trait enabled, tagged values
can be used directly in your schema:

[Tagged]: https://github.com/pointfreeco/swift-tagged

```swift
@Table
struct RemindersList: Identifiable {
  typealias ID = Tagged<Self, Int>
  let id: ID
  var title = ""
}
@Table
struct Reminder: Identifiable {
  typealias ID = Tagged<Self, Int>
  let id: ID
  var title = ""
  var remindersListID: RemindersList.ID
}
```

This makes it a compile-time error to compare a `Reminder.ID` to a `RemindersList.ID`, or to pass
one where the other is expected.

To enable the trait, specify it in the `Package.swift` file that depends on SQLiteData:

```diff
 .package(
   url: "https://github.com/pointfreeco/sqlite-data",
   from: "1.10.0",
+  traits: ["Tagged"]
 ),
```

> Important: On Swift toolchains earlier than 6.3, you _must_ also explicitly depend on the
> `swift-tagged` package to work around a SwiftPM bug in which dependencies introduced by a trait
> are not resolved:
>
> ```diff
> +.package(
> +  url: "https://github.com/pointfreeco/swift-tagged",
> +  from: "0.1.0"
> +),
> ```
>
> This bug is fixed in Swift 6.3, where the explicit dependency can be omitted.

See [Tagged identifiers](<doc:DefiningYourSchema#Tagged-identifiers>) for more information on
using tagged values in your schema.

### Deprecated traits

The `SQLiteDataTagged` trait is a deprecated aliases to the `Tagged` trait, and will be removed in
a future version of SQLiteData.
