#if canImport(CloudKit)
  import CloudKit
  import Dependencies

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension DependencyValues {
    /// The default sync engine used by the application.
    ///
    /// Configure this as early as possible in your app's lifetime, like the app entry point in
    /// SwiftUI, using `prepareDependencies`:
    ///
    /// ```swift
    /// import SQLiteData
    /// import SwiftUI
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///   init() {
    ///     prepareDependencies {
    ///       $0.defaultDatabase = try! appDatabase()
    ///       $0.defaultSyncEngine = SyncEngine(
    ///         for: $0.defaultDatabase,
    ///         tables: Item.self
    ///       )
    ///     }
    ///   }
    ///   // ...
    /// }
    /// ```
    ///
    /// > Note: You can only prepare the default sync engine a single time in the lifetime of
    /// > your app. Attempting to do so more than once will produce a runtime warning.
    ///
    /// Once configured, access the default sync engine anywhere using `@Dependency`:
    ///
    /// ```swift
    /// @Dependency(\.defaultSyncEngine) var syncEngine
    ///
    /// syncEngine.acceptShare(metadata: metadata)
    /// ```
    ///
    /// See <doc:PreparingDatabase> for more info.
    public var defaultSyncEngine: SyncEngine {
      get { self[SyncEngine.self] }
      set { self[SyncEngine.self] = newValue }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine: TestDependencyKey {
    public static var previewValue: SyncEngine {
      try! SyncEngine(for: DatabaseQueue())
    }

    public static var testValue: SyncEngine {
      try! SyncEngine(
        for: DatabasePool(
          path: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite").path()
        )
      )
    }
  }
#endif
