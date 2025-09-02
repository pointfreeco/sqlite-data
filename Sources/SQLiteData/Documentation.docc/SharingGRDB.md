# ``SQLiteData``

A fast, lightweight replacement for SwiftData, powered by SQL and supporting CloudKit 
synchronization.

## Overview

The core functionality of this library is defined in
[`SQLiteDataCore`](sqlitedatacore) and [`StructuredQueriesGRDBCore`](structuredquereisgrdbcore),
which this module automatically exports.

> Note: This module also exports `StructuredQueries`, which provides the `@Table` macro for building
> and decoding queries. If you are using [GRDB][]'s built-in tools instead of
> [StructuredQueries][], consider depending  on `SQLiteDataCore`, instead.

See [`SQLiteDataCore`](sqlitedatacore) for documentation on the integration with the
`@FetchAll` property wrapper, which is equivalent to SwiftData's `@Query`.

See [`StructuredQueriesGRDBCore`](sqlitedatacore) for documentation on the integration between
[StructuredQueries][] and [GRDB][].

> Tip: SQLiteData's primary product is the `SQLiteData` module, which includes all of the
> library's functionality, including the `@Fetch` family of property wrappers, the `@Table` macro,
> and tools for driving StructuredQueries using GRDB. This is the module that most library users
> should depend on.
>
> If you are a library author that wishes to extend SQLiteData with additional functionality, you
> may want to depend on a different module:
>
>   * [`SQLiteDataCore`](sqlitedatacore): This product includes everything in `SQLiteData`
>     _except_ the macros (`@Table`, `#sql`, _etc._). This module can be imported to extend
>     SQLiteData with additional functionality without forcing the heavyweight dependency of
>     SwiftSyntax on your users.
>   * `StructuredQueriesGRDB`: This product includes everything in `SQLiteData` _except_ the
>     `@Fetch` family of property wrappers. It can be imported if you want to extend
>     StructuredQueries' GRDB driver but do not need access to observation tools provided by
>     Sharing.
>   * [`StructuredQueriesGRDBCore`](sqlitedatacore): This product includes everything in
>     `StructuredQueriesGRDB` _except_ the macros. This module can be imported to extend
>     StructuredQueries' GRDB driver with additional functionality without forcing the heavyweight
>     dependency of SwiftSyntax on your users.

[GRDB]: https://github.com/groue/GRDB.swift
[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries
