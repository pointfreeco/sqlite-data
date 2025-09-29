import CryptoKit
import Dependencies
import Foundation

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
package protocol DataManager: Sendable {
  func load(_ url: URL) throws -> Data
  func save(_ data: Data, to url: URL) throws
  func sha256(of fileURL: URL) -> Data?
  var temporaryDirectory: URL { get }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
struct LiveDataManager: DataManager {
  func load(_ url: URL) throws -> Data {
    try Data(contentsOf: url)
  }
  func save(_ data: Data, to url: URL) throws {
    try data.write(to: url)
  }
  func sha256(of fileURL: URL) -> Data? {
    do {
      let fileHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? fileHandle.close() }
      var hasher = SHA256()
      while true {
        let shouldBreak = try autoreleasepool {
          guard
            let data = try fileHandle.read(upToCount: 1024 * 1024),
            !data.isEmpty
          else { return false }
          hasher.update(data: data)
          return true
        }
        guard !shouldBreak
        else { break }
      }
      let digest = hasher.finalize()
      return Data(digest)
    } catch {
      return nil
    }
  }
  var temporaryDirectory: URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
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

  package func sha256(of fileURL: URL) -> Data? {
    storage.withValue {
      $0[fileURL].map {
        Data(SHA256.hash(data: $0))
      }
    }
  }

  package var temporaryDirectory: URL {
    URL(fileURLWithPath: "/")
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
private enum DataManagerKey: DependencyKey {
  static var liveValue: any DataManager {
    LiveDataManager()
  }
  static var testValue: any DataManager {
    InMemoryDataManager()
  }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension DependencyValues {
  package var dataManager: DataManager {
    get { self[DataManagerKey.self] }
    set { self[DataManagerKey.self] = newValue }
  }
}
