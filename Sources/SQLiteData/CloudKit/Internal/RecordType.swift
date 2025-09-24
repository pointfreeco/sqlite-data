@Table("sqlitedata_icloud_recordTypes")
package struct RecordType: Hashable {
  @Column(primaryKey: true)
  package let tableName: String
  package let schema: String
  @Column(as: Set<TableInfo>.JSONRepresentation.self)
  package let tableInfo: Set<TableInfo>
}
