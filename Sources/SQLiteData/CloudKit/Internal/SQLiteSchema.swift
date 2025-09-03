@Table("sqlite_schema")
struct SQLiteSchema {
  let type: String
  let name: String
  @Column("tbl_name")
  let tableName: String
  let sql: String?
}
