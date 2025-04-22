# Dynamic queries

Learn how to load model data based on information that isn't known at compile time.

## Overview

It is very common for an application to provide a particular "view" into its model data depending on
some user-provided input. For example, you may want to filter a query using the text specified in a
search field, or you may want to provide a variety of sort options for displaying the data in a
particular order.

If you were to fetch all data up front with a static query, and then filter and sort using Swift's
collection algorithms, you would not only load more data into memory than necessary, but you would
also perform work in Swift that is more efficiently done in SQLite.

Take the following example:

```swift
struct ContentView: View {
  @FetchAll var items: [Item]
  @State var filterDate: Date?
  @State var order: SortOrder = .reverse

  var displayedItems: [Item] {
    items
      .filter { $0.timestamp > filterDate ?? .distantPast }
      .sorted {
        order == .forward
          ? $0.timestamp < $1.timestamp
          : $0.timestamp > $1.timestamp
      }
      .prefix(10)
  }

  // ...
}
```

It fetches _all_ items from the backing database into memory and then Swift does the work of
filtering, sorting, and truncating this data before it is displayed to the user. This means if the
table contains thousands, or even hundreds of thousands of rows, every single one will be loaded
into memory and processed, which is incredibly inefficient to do. Worse, this work will be performed
every single time `displayedItems` is evaluated, which will be at least once for each time the 
view's body is computed, but could also be more.

This kind of data processing is exactly what SQLite excels at, and so we can offload this work by
modifying the query itself. One can do this with SharingGRDB by using the `load` method on
`SharedReader` in order to load a new key, and hence execute a new query:

```swift
struct ContentView: View {
  @State.SharedReader(value: []) var items: [Item]
  @State var filterDate: Date?
  @State var order: SortOrder = .reverse

  var body: some View {
    List {
      // ...
    }
    .task(id: [filter, ordering] as [AnyHashable]) {
      await updateQuery()
    }
  }

  private func updateQuery() async {
    do {
      try await $items.load(
        .fetchAll(
          Items
            .where { $0.timestamp > #bind(filterDate ?? .distantPast) }
            .order {
              if order == .forward {
                $0.timestamp
              } else {
                $0.timestamp.desc()
              }
            }
            .limit(10)
        )
      )
    } catch {
      // Handle error...
    }
  }

  // ...
}
```

> Important: If a parent view refreshes, a dynamically-updated query can be overwritten with the
> initial `@FetchAll`'s value, taken from the parent. To manage the state of this dynamic query
> locally to this view, we use `@State @FetchAll`, instead, and to access the underlying 
> `FetchAll` value you can use `wrappedValue`.

> Note: We are using the ``Sharing/SharedReaderKey/fetchAll(_:database:)`` style of 
> querying the database. See <doc:Fetching> for more APIs that can be used.
