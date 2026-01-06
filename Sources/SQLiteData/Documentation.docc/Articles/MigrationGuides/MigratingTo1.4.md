# Migrating to 1.4

SQLiteData 1.4 introduces a new tool for tying the lifecycle database subscriptions to the
lifecycle of the surrounding async context, but it may incidentally cause "Result of call …
is unused" warnings in your project.

## Overview

The `load` method defined on [`@FetchAll`](<doc:FetchAll>) / [`@FetchOne`](<doc:FetchOne>) /
[`@Fetch`](<doc:Fetch>) all now return a discardable result, ``FetchSubscription``. Awaiting the
``FetchSubscription/task`` of that result ties the lifecycle of the subscription to the database
to the lifecycle of the surrounding async context, which can help views to automatically
unsubscribe from the database when they are not visible.

However, when used with `withErrorReporting` you are likely to get the following warning:

```swift
private func updateQuery() async {
  // ⚠️ Result of call to 'withErrorReporting(_:to:fileID:filePath:line:column:isolation:catching:)' is unused
  await withErrorReporting {
    try await $rows.load(…)
  }
}
```

This is happening because although `load` has a discardable result, Swift does not propagate that
to `withErrorReporting`, and so Swift thinks you have an unused value. To fix you will need to
explicitly ignore the result with `_ = `:

```swift
private func updateQuery() async {
  _ = await withErrorReporting {
    try await $rows.load(…)
  }
}
```
