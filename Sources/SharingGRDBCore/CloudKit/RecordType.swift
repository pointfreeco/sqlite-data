// @Table("\(String.sqliteDataCloudKitSchemaName)_recordTypes")
package struct RecordType: Hashable {
  // @Column(primaryKey: true)
  package let tableName: String
  package let schema: String
  // @Column(as: [TableInfo].JSONRepresentation.self)
  package let tableInfo: [TableInfo]
}
