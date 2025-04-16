import Dependencies

extension DependencyValues {
  /// The default database used by `fetchAll`, `fetchOne`, and `fetch`.
  ///
  /// Configure this as early as possible in your app's lifetime, like the app entry point in
  /// SwiftUI, using `prepareDependencies`:
  ///
  /// ```swift
  /// import SharingGRDB
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
        if context == .preview {
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            'SharingGRDB', use the 'prepareDependencies' tool as early as possible in the lifetime \
            of your preview:

                #Preview {
                  let _ = prepareDependencies {
                    $0.defaultDatabase = try! DatabaseQueue(/* ... */)
                  }

                  // ...
                }
            """
        } else {
          return """
            A blank, in-memory database is being used. To set the database that is used by \
            'SharingGRDB', use the 'prepareDependencies' tool as early as possible in the lifetime \
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
    static let defaultDatabaseLabel = "co.pointfree.SharingGRDB.testValue"
  }
#endif
