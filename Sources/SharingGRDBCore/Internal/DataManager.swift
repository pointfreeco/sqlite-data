import Dependencies
import Foundation

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
package protocol DataManager: Sendable {
  func load(_ url: URL) throws -> Data
  func save(_ data: Data, to url: URL) throws
  var temporaryDirectory: URL { get }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
struct LiveDataManager: DataManager {
  func load(_ url: URL) throws -> Data {
    try Data(contentsOf: url)
  }
  func save(_ data: Data, to url: URL) throws {
    try data.write(to: url)
  }
  var temporaryDirectory: URL {
    .temporaryDirectory
  }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
package struct InMemoryDataManager: DataManager {
  package let storage = LockIsolated<[URL: Data]>([:])

  package init() {}

  package func load(_ url: URL) throws -> Data {
    try storage.withValue { storage in
      guard let data = storage[url]
      else {
        struct FileNotFound: Error {}
        throw FileNotFound()
      }
      return data
    }
  }

  package func save(_ data: Data, to url: URL) throws {
    storage.withValue { $0[url] = data }
  }

  package var temporaryDirectory: URL {
    URL(filePath: "/")
  }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
private enum DataManagerKey: DependencyKey {
  static var liveValue: any DataManager {
    LiveDataManager()
  }
  static var testValue: any DataManager {
    InMemoryDataManager()
  }
}

extension DependencyValues {
  @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
  package var dataManager: DataManager {
    get { self[DataManagerKey.self] }
    set { self[DataManagerKey.self] = newValue }
  }
}
