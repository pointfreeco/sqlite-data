#if canImport(CloudKit)
  import ConcurrencyExtras
  import Foundation
  import SQLiteData

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  struct TemporaryDirectoryDataManager: DataManager {
    let temporaryDirectory: URL
    let storage = LockIsolated<[URL: Data]>([:])

    func load(_ url: URL) throws -> Data {
      try storage.withValue { storage in
        guard let data = storage[url]
        else {
          struct FileNotFound: Error {}
          throw FileNotFound()
        }
        return data
      }
    }

    func save(_ data: Data, to url: URL) throws {
      storage.withValue { $0[url] = data }
    }

    func sha256(of fileURL: URL) -> Data? {
      nil
    }
  }
#endif
