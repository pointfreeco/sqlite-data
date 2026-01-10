import Dependencies
import Foundation

/// Prepares a context-sensitive database writer.
///
///   * In a live app context (e.g. simulator, device), a database pool is provisioned in the app
///     container (unless explicitly overridden with the `path` parameter).
///   * In an Xcode preview context, an in-memory database is provisioned.
///   * In a test context, a database pool is provisioned at a temporary file.
///
/// - Parameters:
///   - path: A path to the database. If `nil`, a path to a file in the application support
///     directory will be used.
///   - configuration: A database configuration.
/// - Returns: A context-sensitive database writer.
public func defaultDatabase(
  path: String? = nil,
  configuration: Configuration = Configuration()
) throws -> any DatabaseWriter {
  let database: any DatabaseWriter
  @Dependency(\.context) var context
  switch context {
  case .live:
    var defaultPath: String {
      get throws {
        let applicationSupportDirectory = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
        return applicationSupportDirectory.appendingPathComponent("SQLiteData.db").absoluteString
      }
    }
    database = try DatabasePool(path: path ?? defaultPath, configuration: configuration)
  case .preview:
    var configuration = configuration
    configuration.busyMode = .callback({ numberOfTries in
      print("numberOfTries", numberOfTries)
      return numberOfTries < 100
    })
    database = try DatabasePool(
      path: "\(NSTemporaryDirectory())\(UUID().uuidString).db",
      configuration: configuration
    )
  case .test:
    database = try DatabasePool(
      path: "\(NSTemporaryDirectory())\(UUID().uuidString).db",
      configuration: configuration
    )
  }
  return database
}

extension DependencyValues {
  /// The default database used by `fetchAll`, `fetchOne`, and `fetch`.
  ///
  /// Configure this as early as possible in your app's lifetime, like the app entry point in
  /// SwiftUI, using `prepareDependencies`:
  ///
  /// ```swift
  /// import SQLiteData
  /// import SwiftUI
  ///
  /// @main
  /// struct MyApp: App {
  ///   init() {
  ///     prepareDependencies {
  ///       // Create database connection and run migrations...
  ///       $0.defaultDatabase = try! DatabaseQueue(/* ... */)
  ///     }
  ///   }
  ///   // ...
  /// }
  /// ```
  ///
  /// > Note: You can only prepare the database a single time in the lifetime of your app.
  /// > Attempting to do so more than once will produce a runtime warning.
  ///
  /// Once configured, access the database anywhere using `@Dependency`:
  ///
  /// ```swift
  /// @Dependency(\.defaultDatabase) var database
  ///
  /// var newItem = Item(/* ... */)
  /// try database.write { db in
  ///   try newItem.insert(db)
  /// }
  /// ```
  ///
  /// See <doc:PreparingDatabase> for more info.
  public var defaultDatabase: any DatabaseWriter {
    get { self[DefaultDatabaseKey.self] }
    set { self[DefaultDatabaseKey.self] = newValue }
  }

  private enum DefaultDatabaseKey: DependencyKey {
    static var liveValue: any DatabaseWriter { testValue }
    static var testValue: any DatabaseWriter {
      var message: String {
        @Dependency(\.context) var context
        switch context {
        case .live:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            'SQLiteData', use the 'prepareDependencies' tool as early as possible in the lifetime \
            of your app, such as in your app or scene delegate in UIKit, or the app entry point in \
            SwiftUI:

                @main
                struct MyApp: App {
                  init() {
                    prepareDependencies {
                      $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                    }
                  }
                  // ...
                }
            """

        case .preview:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            'SQLiteData' in a preview, use a tool like 'prepareDependencies':

                #Preview {
                  let _ = prepareDependencies {
                    $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                  }
                  // ...
                }
            """

        case .test:
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            'SQLiteData' in a test, use a tool like the 'dependency' trait from \
            'DependenciesTestSupport':

                import DependenciesTestSupport

                @Suite(.dependency(\\.defaultDatabase, try DatabaseQueue(/* ... */)))
                struct MyTests {
                  // ...
                }
            """
        }
      }
      if shouldReportUnimplemented {
        reportIssue(message)
      }
      var configuration = Configuration()
      #if DEBUG
        configuration.label = .defaultDatabaseLabel
      #endif
      return try! DatabaseQueue(configuration: configuration)
    }
  }
}

#if DEBUG
  extension String {
    package static let defaultDatabaseLabel = "co.pointfree.SQLiteData.testValue"
  }
#endif
