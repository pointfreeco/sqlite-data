#if canImport(CloudKit)
  @Table("sqlitedata_icloud_recordTypes")
  package struct RecordType: Hashable {
    @Column(primaryKey: true)
    package let tableName: String
    package let schema: String
    @Column(as: Set<TableInfo>.JSONRepresentation.self)
    package let tableInfo: Set<TableInfo>

    // NB: The 'Hashable' conformance is manually implemented due to a Swift bug that causes the
    //     synthesized implementations to erroneously return 'false'

    package static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.tableName == rhs.tableName && lhs.schema == rhs.schema && lhs.tableInfo == rhs.tableInfo
    }

    package func hash(into hasher: inout Hasher) {
      hasher.combine(tableName)
      hasher.combine(schema)
      hasher.combine(tableInfo)
    }
  }
#endif
