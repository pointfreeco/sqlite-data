@Table("sqlite_schema")
package struct SQLiteSchema {
  package let type: String
  package let name: String
  @Column("tbl_name")
  package let tableName: String
  package let sql: String?
}
