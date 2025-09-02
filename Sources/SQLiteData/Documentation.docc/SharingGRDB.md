# ``SharingGRDB``

A fast, lightweight replacement for SwiftData, powered by SQL and supporting CloudKit 
synchronization.

## Overview

The core functionality of this library is defined in
[`SharingGRDBCore`](sharinggrdbcore) and [`StructuredQueriesGRDBCore`](structuredquereisgrdbcore),
which this module automatically exports.

> Note: This module also exports `StructuredQueries`, which provides the `@Table` macro for building
> and decoding queries. If you are using [GRDB][]'s built-in tools instead of
> [StructuredQueries][], consider depending  on `SharingGRDBCore`, instead.

See [`SharingGRDBCore`](sharinggrdbcore) for documentation on the integration with the
`@FetchAll` property wrapper, which is equivalent to SwiftData's `@Query`.

See [`StructuredQueriesGRDBCore`](sharinggrdbcore) for documentation on the integration between
[StructuredQueries][] and [GRDB][].

> Tip: SharingGRDB's primary product is the `SharingGRDB` module, which includes all of the
> library's functionality, including the `@Fetch` family of property wrappers, the `@Table` macro,
> and tools for driving StructuredQueries using GRDB. This is the module that most library users
> should depend on.
>
> If you are a library author that wishes to extend SharingGRDB with additional functionality, you
> may want to depend on a different module:
>
>   * [`SharingGRDBCore`](sharinggrdbcore): This product includes everything in `SharingGRDB`
>     _except_ the macros (`@Table`, `#sql`, _etc._). This module can be imported to extend
>     SharingGRDB with additional functionality without forcing the heavyweight dependency of
>     SwiftSyntax on your users.
>   * `StructuredQueriesGRDB`: This product includes everything in `SharingGRDB` _except_ the
>     `@Fetch` family of property wrappers. It can be imported if you want to extend
>     StructuredQueries' GRDB driver but do not need access to observation tools provided by
>     Sharing.
>   * [`StructuredQueriesGRDBCore`](sharinggrdbcore): This product includes everything in
>     `StructuredQueriesGRDB` _except_ the macros. This module can be imported to extend
>     StructuredQueries' GRDB driver with additional functionality without forcing the heavyweight
>     dependency of SwiftSyntax on your users.

[GRDB]: https://github.com/groue/GRDB.swift
[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries
