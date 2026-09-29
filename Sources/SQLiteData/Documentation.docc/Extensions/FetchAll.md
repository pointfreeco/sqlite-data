# ``SQLiteData/FetchAll``

## Overview

## Topics

### Fetching data

- ``init(wrappedValue:database:)``
- ``init(wrappedValue:_:database:)``
- ``load(_:database:)``

### Sectioning data

- ``init(wrappedValue:sectionBy:database:)``
- ``init(wrappedValue:_:sectionBy:database:)``
- ``load(_:sectionBy:database:)``
- ``sections``
- ``ResultsSectionCollection``
- ``ResultsSection``

### Accessing state

- ``wrappedValue``
- ``projectedValue``
- ``isLoading``
- ``loadError``

### SwiftUI integration

- ``init(wrappedValue:database:animation:)``
- ``init(wrappedValue:_:database:animation:)``
- ``init(wrappedValue:sectionBy:database:animation:)``
- ``init(wrappedValue:_:sectionBy:database:animation:)``
- ``load(_:database:animation:)``
- ``load(_:sectionBy:database:animation:)``

### Combine integration

- ``publisher``

### Custom scheduling

- ``init(wrappedValue:database:scheduler:)``
- ``init(wrappedValue:_:database:scheduler:)``
- ``init(wrappedValue:sectionBy:database:scheduler:)``
- ``init(wrappedValue:_:sectionBy:database:scheduler:)``
- ``load(_:database:scheduler:)``
- ``load(_:sectionBy:database:scheduler:)``

### Sharing infrastructure

- ``sharedReader``
- ``subscript(dynamicMember:)``
