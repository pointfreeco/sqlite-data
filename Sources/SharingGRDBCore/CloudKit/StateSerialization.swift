#if canImport(CloudKit)
import CloudKit
import StructuredQueriesCore

// @Table("\(String.sqliteDataCloudKitSchemaName)_stateSerialization")
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package struct StateSerialization {
  // @Column(as: CKDatabase.Scope.RawValueRepresentation.self, primaryKey: true)
  package var scope: CKDatabase.Scope
  // @Column(as: CKSyncEngine.State.Serialization.JSONRepresentation.self)
  package var data: CKSyncEngine.State.Serialization
}
#endif
