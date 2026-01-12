#if canImport(CloudKit)
  import CloudKit
  import CryptoKit
  import DependenciesTestSupport
  import Foundation
  import InlineSnapshotTesting
  @testable import SQLiteData
  import StructuredQueriesTestSupport
  import Testing

  struct RowVersion<T: PrimaryKeyedTable> {
    let row: T
    private let modificationTimes: [PartialKeyPath<T>: Int64]

    package init(
      row: T,
      modificationTimes: [PartialKeyPath<T>: Int64]
    ) {
      self.row = row
      self.modificationTimes = modificationTimes
    }

    init(
      clientRow row: T,
      userModificationTime: Int64,
      ancestorVersion: RowVersion<T>
    ) {
      var modificationTimes: [PartialKeyPath<T>: Int64] = [:]
      for column in T.TableColumns.writableColumns {
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
          let keyPath = column.keyPath as! KeyPath<T, Value.QueryOutput>

          let clientValue = row[keyPath: keyPath]
          let ancestorValue = ancestorVersion.row[keyPath: keyPath]

          if areEqual(clientValue, ancestorValue, as: Value.self) {
            modificationTimes[keyPath] = ancestorVersion.modificationTime(for: keyPath)
          } else {
            modificationTimes[keyPath] = userModificationTime
          }
        }
        open(column)
      }

      self.init(
        row: row,
        modificationTimes: modificationTimes
      )
    }

    init(from record: CKRecord) throws {
      @Dependency(\.defaultDatabase) var database
      @Dependency(\.dataManager) var dataManager
      
      func makeQuery() -> SQLQueryExpression<T> {
        let values = T.TableColumns.allColumns.map { column in
          let value = record.encryptedValues[column.name]
          
          if let asset = value as? CKAsset,
             let data = try? asset.fileURL.map({ try dataManager.load($0) }) {
            return data.queryFragment
          }
          
          if let value {
            return value.queryFragment
          }
          
          return "NULL"
        }
        
        return #sql("SELECT \(values.joined(separator: ", "))")
      }

      // Convert CKRecord values into a SQL SELECT with literal values and execute through
      // the database. This leverages SQLiteQueryDecoder to handle all type conversions
      // and produces a properly decoded T instance.
      let query = makeQuery()
      let row = try database.read { db in
        // TODO: The synthetic selection always returns exactly one row, should we force-cast instead?
        guard let row = try query.fetchOne(db) else { throw NotFound() }
        // TODO: Is there a way to make the compiler aware of T.QueryOutput == T?
        return row as! T
      }
      
      var modificationTimes: [PartialKeyPath<T>: Int64] = [:]
      for column in T.TableColumns.writableColumns {
        func open<Root, Value>(_ column: some WritableTableColumnExpression<Root, Value>) {
          let keyPath = column.keyPath as! PartialKeyPath<T>
          modificationTimes[keyPath] = record.encryptedValues[at: column.name]
        }
        open(column)
      }

      self.init(
        row: row,
        modificationTimes: modificationTimes
      )
    }

    func modificationTime(for column: PartialKeyPath<T>) -> Int64 {
      return modificationTimes[column] ?? -1
    }
  }

  struct MergeConflict<T: PrimaryKeyedTable> where T.TableColumns.PrimaryColumn: WritableTableColumnExpression {
    let ancestor: RowVersion<T>
    let client: RowVersion<T>
    let server: RowVersion<T>
  }

  extension MergeConflict {
    /// Computes the merged value for a field identified by key path using the given merge policy,
    /// delegating to `mergedValue(column:policy:)`.
    func mergedValue<Column: WritableTableColumnExpression>(
      for keyPath: some KeyPath<T.TableColumns, Column>,
      policy: FieldMergePolicy<Column.QueryValue.QueryOutput>
    ) -> Column.QueryValue.QueryOutput where Column.Root == T {
      mergedValue(
        column: T.columns[keyPath: keyPath],
        policy: policy
      )
    }
    
    /// Computes the merged value for a field identified by column using three-way merge logic,
    /// applying the given merge policy when both versions changed.
    func mergedValue<Column: WritableTableColumnExpression>(
      column: Column,
      policy: FieldMergePolicy<Column.QueryValue.QueryOutput>
    ) -> Column.QueryValue.QueryOutput where Column.Root == T {
      let keyPath = column.keyPath
      let ancestorValue = ancestor.row[keyPath: keyPath]
      let clientValue = client.row[keyPath: keyPath]
      let serverValue = server.row[keyPath: keyPath]
      
      let clientChanged = !areEqual(ancestorValue, clientValue, as: Column.QueryValue.self)
      let serverChanged = !areEqual(ancestorValue, serverValue, as: Column.QueryValue.self)
      
      switch (clientChanged, serverChanged) {
      case (false, false):
        return ancestorValue
      case (true, false):
        return clientValue
      case (false, true):
        return serverValue
      case (true, true):
        let ancestorVersion = FieldVersion(
          value: ancestorValue,
          modificationTime: ancestor.modificationTime(for: keyPath)
        )
        let clientVersion = FieldVersion(
          value: clientValue,
          modificationTime: client.modificationTime(for: keyPath)
        )
        let serverVersion = FieldVersion(
          value: serverValue,
          modificationTime: server.modificationTime(for: keyPath)
        )
        
        return policy.resolve(ancestorVersion, clientVersion, serverVersion)
      }
    }
    
    /// Generates an UPDATE statement that resolves the merge conflict using the `.latest` policy.
    func makeUpdateQuery() -> QueryFragment {
      let assignments = T.TableColumns.writableColumns.compactMap { column in
        func open<Root, Value>(
          _ column: some WritableTableColumnExpression<Root, Value>
        ) -> (column: String, value: QueryBinding)? {
          guard column.name != T.primaryKey.name else { return nil }
          let column = column as! (any WritableTableColumnExpression<T, Value>)
          let merged = mergedValue(column: column, policy: .latest)
          return (column: column.name, value: Value(queryOutput: merged).queryBinding)
        }
        return open(column)
      }

      return """
        UPDATE \(T.self)
        SET \(assignments.map { "\(quote: $0.column) = \($0.value)" }.joined(separator: ", "))
        WHERE (\(T.primaryKey)) = (\(T.PrimaryKey(queryOutput: ancestor.row.primaryKey)))
        """
    }
  }

  struct FieldVersion<Value> {
    let value: Value
    let modificationTime: Int64
  }

  struct FieldMergePolicy<Value> {
    let resolve: (
      _ ancestor: FieldVersion<Value>,
      _ client: FieldVersion<Value>,
      _ server: FieldVersion<Value>
    ) -> Value
  }

  extension FieldMergePolicy {
    static var latest: Self {
      Self { _, client, server in
        server.modificationTime > client.modificationTime ? server.value : client.value
      }
    }
  }

  extension FieldMergePolicy where Value: BinaryInteger {
    static var counter: Self {
      Self { ancestor, client, server in
        ancestor.value
          + (client.value - ancestor.value)
          + (server.value - ancestor.value)
      }
    }
  }

  extension FieldMergePolicy where Value: SetAlgebra, Value.Element: Equatable {
    static var set: Self {
      Self { ancestor, client, server in
        let notDeleted = ancestor.value
          .intersection(client.value)
          .intersection(server.value)

        let addedByClient = client.value.subtracting(ancestor.value)
        let addedByServer = server.value.subtracting(ancestor.value)

        return notDeleted
          .union(addedByClient)
          .union(addedByServer)
      }
    }
  }

  /// Compares values using their database representation (`QueryBinding`), which eliminates
  /// the need for `Equatable` conformance and efficiently handles special cases.
  fileprivate func areEqual<Value: QueryRepresentable & QueryBindable>(
    _ lhs: Value.QueryOutput,
    _ rhs: Value.QueryOutput,
    as: Value.Type
  ) -> Bool {
    let lhsBinding = Value(queryOutput: lhs).queryBinding
    let rhsBinding = Value(queryOutput: rhs).queryBinding

    switch (lhsBinding, rhsBinding) {
    case (.blob(let lhsValue), .blob(let rhsValue)):
      return lhsValue.sha256 == rhsValue.sha256
    case (.bool(let lhsValue), .bool(let rhsValue)):
      return lhsValue == rhsValue
    case (.double(let lhsValue), .double(let rhsValue)):
      return lhsValue == rhsValue
    case (.date(let lhsValue), .date(let rhsValue)):
      return lhsValue == rhsValue
    case (.int(let lhsValue), .int(let rhsValue)):
      return lhsValue == rhsValue
    case (.null, .null):
      return true
    case (.text(let lhsValue), .text(let rhsValue)):
      return lhsValue == rhsValue
    case (.uint(let lhsValue), .uint(let rhsValue)):
      return lhsValue == rhsValue
    case (.uuid(let lhsValue), .uuid(let rhsValue)):
      // TODO: Can't we compare the UUID instances directly?
      return lhsValue.uuidString.lowercased() == rhsValue.uuidString.lowercased()
    case (.invalid(let error), _), (_, .invalid(let error)):
      reportIssue(error)
      return false
    default:
      return false
    }
  }

  extension DataProtocol {
    fileprivate var sha256: Data {
      Data(SHA256.hash(data: self))
    }
  }

  @Table
  private struct Post {
    let id: UUID
    var title: String
    var upvotes = 0
    @Column(as: Set<String>.JSONRepresentation.self)
    var tags: Set<String> = []
  }

  @Table
  private struct MergeModel {
    let id: Int
    var field1: String
    var field2: String
    var field3: String
    var field4: String
    var field5: String
    var field6: String
    var field7: String
  }

  extension DatabaseWriter {
    /// Resolves a merge conflict via a database roundtrip using the “last edit wins” field merge
    /// policy. Primarily used for testing conflict resolution logic.
    fileprivate func resolve<T: PrimaryKeyedTable>(
      conflict: MergeConflict<T>
    ) throws -> T where T == T.QueryOutput, T.TableColumns.PrimaryColumn: WritableTableColumnExpression {
      try write { db in
        // Insert the initial client row.
        try T.insert { conflict.client.row }.execute(db)
        
        // Perform the update query resolving the conflict.
        try #sql(conflict.makeUpdateQuery()).execute(db)
        
        // Fetch the updated client row.
        return try T.fetchOne(db)!
      }
    }
  }

  extension MergeModel {
    /// Creates a three-way merge conflict covering all seven canonical merge scenarios.
    /// See: https://github.com/structuredpath/sqlite-data-sync-notes/blob/main/BuiltInConflictResolutionModel.md
    fileprivate static func makeCanonicalConflict() -> MergeConflict<Self> {
      let ancestor = RowVersion(
        row: MergeModel(
          id: 0,
          field1: "foo", // Scenario 1: No changes
          field2: "foo", // Scenario 2: Client-only change
          field3: "foo", // Scenario 3: Server-only change
          field4: "foo", // Scenario 4: Both changed, server newer
          field5: "foo", // Scenario 5: Both changed, client newer
          field6: "foo", // Scenario 6: Both changed, equal timestamps
          field7: "foo"  // Scenario 7: Both changed, same value
        ),
        modificationTimes: [
          \.field1: 0,
           \.field2: 0,
           \.field3: 0,
           \.field4: 0,
           \.field5: 0,
           \.field6: 0,
           \.field7: 0
        ]
      )
      
      let client = RowVersion(
        row: MergeModel(
          id: 0,
          field1: "foo",
          field2: "bar",
          field3: "foo",
          field4: "bar",
          field5: "bar",
          field6: "bar",
          field7: "bar"
        ),
        modificationTimes: [
          \.field1: 0,
           \.field2: 100,
           \.field3: 0,
           \.field4: 100,
           \.field5: 100,
           \.field6: 100,
           \.field7: 100
        ]
      )
      
      let server = RowVersion(
        row: MergeModel(
          id: 0,
          field1: "foo",
          field2: "foo",
          field3: "baz",
          field4: "baz",
          field5: "baz",
          field6: "baz",
          field7: "bar"
        ),
        modificationTimes: [
          \.field1: 0,
           \.field2: 0,
           \.field3: 200,
           \.field4: 200,
           \.field5: 50,
           \.field6: 100,
           \.field7: 200
        ]
      )
      
      return MergeConflict(ancestor: ancestor, client: client, server: server)
    }
  }

  extension DatabaseWriter where Self == DatabaseQueue {
    fileprivate static func databaseForMergeConflicts() throws -> DatabaseQueue {
      let database = try DatabaseQueue()
      try database.write { db in
        try #sql(
            """
            CREATE TABLE "posts" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "title" TEXT NOT NULL,
              "upvotes" INTEGER NOT NULL DEFAULT 0,
              "tags" TEXT NOT NULL
            )
            """
        )
        .execute(db)
        try #sql(
            """
            CREATE TABLE "mergeModels" (
              "id" INTEGER PRIMARY KEY AUTOINCREMENT,
              "field1" TEXT NOT NULL,
              "field2" TEXT NOT NULL,
              "field3" TEXT NOT NULL,
              "field4" TEXT NOT NULL,
              "field5" TEXT NOT NULL,
              "field6" TEXT NOT NULL,
              "field7" TEXT NOT NULL
            )
            """
        )
        .execute(db)
      }
      return database
    }
  }

  @Suite(.dependency(\.defaultDatabase, try .databaseForMergeConflicts()))
  struct ConflictResolutionPlaygroundTests {
    @Test
    func versionInit_rowAndModificationTimes() {
      let version = RowVersion(
        row: Post(id: UUID(0), title: "My Post"),
        modificationTimes: [
          \.title: 100,
          \.upvotes: 0,
          \.tags: 0
        ]
      )

      #expect(version.modificationTime(for: \.title) == 100)
      #expect(version.modificationTime(for: \.upvotes) == 0)
      #expect(version.modificationTime(for: \.tags) == 0)
    }

    @Test
    func versionInit_clientRow() {
      let ancestor = RowVersion(
        row: Post(id: UUID(0), title: ""),
        modificationTimes: [
          \.title: 50,
          \.upvotes: 50,
          \.tags: 50
        ]
      )

      let client = RowVersion(
        clientRow: Post(id: UUID(0), title: "My Post"),
        userModificationTime: 100,
        ancestorVersion: ancestor
      )

      #expect(client.modificationTime(for: \.title) == 100)
      #expect(client.modificationTime(for: \.upvotes) == 50)
      #expect(client.modificationTime(for: \.tags) == 50)
    }

    @Test
    func versionInit_fromRecord() throws {
      let record = CKRecord(recordType: "Post")
      record.setValue(UUID(0).uuidString.lowercased(), forKey: "id", at: 0)
      record.setValue("My Post", forKey: "title", at: 100)
      record.setValue(42, forKey: "upvotes", at: 50)
      record.setValue(#"["hobby","travel"]"#, forKey: "tags", at: 50)

      let version = try RowVersion<Post>(from: record)

      #expect(version.row.id == UUID(0))
      #expect(version.modificationTime(for: \.id) == 0)
      
      #expect(version.row.title == "My Post")
      #expect(version.modificationTime(for: \.title) == 100)
      
      #expect(version.row.upvotes == 42)
      #expect(version.modificationTime(for: \.upvotes) == 50)
      
      #expect(version.row.tags == ["hobby", "travel"])
      #expect(version.modificationTime(for: \.tags) == 50)
    }

    @Test
    func mergedValue_canonicalConflictWithLatestPolicy() {
      let conflict = MergeModel.makeCanonicalConflict()

      #expect(conflict.mergedValue(for: \.field1, policy: .latest) == "foo")
      #expect(conflict.mergedValue(for: \.field2, policy: .latest) == "bar")
      #expect(conflict.mergedValue(for: \.field3, policy: .latest) == "baz")
      #expect(conflict.mergedValue(for: \.field4, policy: .latest) == "baz")
      #expect(conflict.mergedValue(for: \.field5, policy: .latest) == "bar")
      #expect(conflict.mergedValue(for: \.field6, policy: .latest) == "bar")
      #expect(conflict.mergedValue(for: \.field7, policy: .latest) == "bar")
    }

    @Test
    func mergedValue_differentPoliciesAndCustomRepresentation() {
      let ancestor = RowVersion(
        row: Post(
          id: UUID(0),
          title: "My Post",
          upvotes: 0,
          tags: ["hobby", "travel"]
        ),
        modificationTimes: [
          \.title: 0,
          \.upvotes: 0,
          \.tags: 0
        ]
      )

      let client = RowVersion(
        row: Post(
          id: UUID(0),
          title: "My Great Post",
          upvotes: 2,
          tags: ["hobby", "travel", "photography"]
        ),
        modificationTimes: [
          \.title: 100,
          \.upvotes: 100,
          \.tags: 100
        ]
      )

      let server = RowVersion(
        row: Post(
          id: UUID(0),
          title: "My Awesome Post",
          upvotes: 3,
          tags: ["hobby", "tech"]
        ),
        modificationTimes: [
          \.title: 50,
          \.upvotes: 50,
          \.tags: 50
        ]
      )

      let conflict = MergeConflict(
        ancestor: ancestor,
        client: client,
        server: server
      )

      #expect(conflict.mergedValue(for: \.title, policy: .latest) == "My Great Post")
      #expect(conflict.mergedValue(for: \.upvotes, policy: .counter) == 5)

      // - `QueryValue`: `Set<String>.JSONRepresentation` (the storage type)
      // - `QueryOutput`: `Set<String>` (the Swift type)
      // - `QueryBinding`: `.text(…)` (the JSON serialized representation)
      #expect(conflict.mergedValue(for: \.tags, policy: .set) == ["hobby", "photography", "tech"])
    }
    
    @Test
    func makeUpdateQuery_canonicalConflictWithLatestPolicy() {
      let conflict = MergeModel.makeCanonicalConflict()
      
      assertInlineSnapshot(of: #sql(conflict.makeUpdateQuery()), as: .sql) {
        """
        UPDATE "mergeModels"
        SET "field1" = 'foo', "field2" = 'bar', "field3" = 'baz', "field4" = 'baz', "field5" = 'bar', "field6" = 'bar', "field7" = 'bar'
        WHERE ("mergeModels"."id") = (0)
        """
      }
    }

    @Test
    func resolve_canonicalConflictWithLatestPolicy() throws {
      @Dependency(\.defaultDatabase) var database
      let conflict = MergeModel.makeCanonicalConflict()
      let merged = try database.resolve(conflict: conflict)

      #expect(merged.field1 == "foo")
      #expect(merged.field2 == "bar")
      #expect(merged.field3 == "baz")
      #expect(merged.field4 == "baz")
      #expect(merged.field5 == "bar")
      #expect(merged.field6 == "bar")
      #expect(merged.field7 == "bar")
    }
  }
#endif
