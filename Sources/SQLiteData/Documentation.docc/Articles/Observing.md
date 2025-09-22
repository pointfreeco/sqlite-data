# Observing changes to model data

Learn how to observe changes to your database in SwiftUI views, UIKit view controllers, and
more.

## Overview

This library can be used to fetch and observe data from a SQLite database in a variety of places
in your application, and is not limited to just SwiftUI views as is the case with the `@Query`
macro from SwiftData.

### SwiftUI

The [`@FetchAll`](<doc:FetchAll>), [`@FetchOne`](<doc:FetchOne>), and [`@Fetch`](<doc:Fetch>)
property wrappers work in SwiftUI views similarly to how the `@Query` macro does from SwiftData.
You simply add a property to the view that is annotated with one of the various ways of
 [querying your database](<doc:Fetching>):

```swift
struct ItemsView: View {
  @FetchAll var items: [Item]

  var body: some View {
    ForEach(items) { item in
      Text(item.name)
    }
  }
}
```

The SwiftUI view will automatically re-render whenever the database changes that causes the
queried data to update.

### @Observable models

SQLiteData's property wrappers also works in `@Observable` models (and `ObservableObject`s for
pre-iOS 17 apps). You can add a property to an `@Observable` class, and its data will automatically
update when the database changes and cause any SwiftUI view using it to re-render:

```swift
@Observable
class ItemsModel {
  @ObservationIgnored
  @FetchAll var items: [Item]
}
struct ItemsView: View {
  let model: ItemsModel

  var body: some View {
    ForEach(model.items) { item in
      Text(item.name)
    }
  }
}
```

> Note: Due to how macros work in Swift, property wrappers must be annotated with
> `@ObservationIgnored`, but this does not affect observation as SQLiteData handles its own
> observation.

### UIKit

It is also possible to use this library's tools in a UIKit view controller. For example, if you
want to use a `UICollectionView` to display a list of items, powered by a diffable data source,
then you can do roughly the following:

```swift
class ItemsViewController: UICollectionViewController {
  @FetchAll var items: [Item]

  override func viewDidLoad() {
    // Set up data source and cell registration...

    // Observe changes to items in order to update data source:
    $items.publisher.sink { items in
      guard let self else { return }
      dataSource.apply(
        NSDiffableDataSourceSnapshot(items: items),
        animatingDifferences: true
      )
    }
    .store(in: &cancellables)
  }
}
```

This uses the `publisher` property that is available on every fetched value to update the collection
view's data source whenever the `items` change.

> Tip: There is an alternative way to observe changes to `items`. If you are already depending on
> our [Swift Navigation][swift-nav-gh] library to make use of powerful navigation APIs for SwiftUI
> and UIKitNavigation, then you can use the [`observe`][observe-docs] tool to update the database
> without using Combine:
>
> ```swift
> override func viewDidLoad() {
>   // Set up data source and cell registration...
>
>   // Observe changes to items in order to update data source:
>   observe { [weak self] in
>     guard let self else { return }
>     dataSource.apply(
>       NSDiffableDataSourceSnapshot(items: items),
>       animatingDifferences: true
>     )
>   }
> }
> ```

[swift-nav-gh]: http://github.com/pointfreeco/swift-navigation
[observe-docs]: https://swiftpackageindex.com/pointfreeco/swift-navigation/main/documentation/swiftnavigation/objectivec/nsobject/observe(_:)-94oxy
