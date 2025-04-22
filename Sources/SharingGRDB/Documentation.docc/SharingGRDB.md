# ``SharingGRDB``

A fast, lightweight replacement for SwiftData, powered by SQL.

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

[GRDB]: https://github.com/groue/GRDB.swift
[StructuredQueries]: https://github.com/pointfreeco/swift-structured-queries
