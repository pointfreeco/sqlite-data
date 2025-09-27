#if canImport(CloudKit)
  @Table("sqlite_schema")
  package struct SQLiteSchema {
    package let type: ObjectType
    package let name: String
    @Column("tbl_name")
    package let tableName: String
    package let sql: String?

    package enum ObjectType: String, QueryBindable {
      case table, index, view, trigger
    }
  }
#endif
