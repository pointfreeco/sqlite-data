# ``SharingGRDBCore/Fetch``

## Overview

## Topics

### Fetching data

- ``FetchKeyRequest``
- ``init(wrappedValue:_:database:)``
- ``init(_:database:)``
- ``init(database:)``
- ``init(wrappedValue:)``
- ``load(_:database:)``

### Accessing state

- ``wrappedValue``
- ``projectedValue``
- ``isLoading``
- ``loadError``

### SwiftUI integration

- ``init(wrappedValue:_:database:animation:)``
- ``load(_:database:animation:)``

### Combine integration

- ``publisher``

### Custom scheduling

- ``init(wrappedValue:_:database:scheduler:)``
- ``load(_:database:scheduler:)``

### Sharing infrastructure

- ``sharedReader``
- ``subscript(dynamicMember:)``
- ``FetchKey``
- ``FetchKeyID``
