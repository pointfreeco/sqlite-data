@Table
struct PragmaDatabaseList {
  static var tableAlias: String? { "databases" }
  static var tableFragment: QueryFragment { "pragma_database_list()" }

  @Column("seq") let sequence: Int
  let name: String
  let file: String
}

@Table
struct PragmaForeignKeyList<Base: Table> {
  static var tableAlias: String? { "\(Base.tableName)ForeignKeys" }
  static var tableFragment: QueryFragment {
    "pragma_foreign_key_list(\(quote: Base.tableName, delimiter: .text))"
  }

  let id: Int
  @Column("seq") let sequence: Int
  let table: String
  let from: String
  let to: String
  @Column("on_update") let onUpdate: ForeignKeyAction
  @Column("on_delete") let onDelete: ForeignKeyAction
  let match: String
}

package enum ForeignKeyAction: String, QueryBindable {
  case cascade = "CASCADE"
  case restrict = "RESTRICT"
  case setDefault = "SET DEFAULT"
  case setNull = "SET NULL"
  case noAction = "NO ACTION"
}

@Table
struct PragmaIndexList<Base: Table> {
  static var tableAlias: String? { "\(Base.tableName)Indices" }
  static var tableFragment: QueryFragment {
    "pragma_index_list(\(quote: Base.tableName, delimiter: .text))"
  }

  @Column("seq") let sequence: Int
  let name: String
  @Column("unique") let isUnique: Bool
  let origin: String
  @Column("partial") let isPartial: Bool
}

@Table
struct PragmaTableInfo<Base: Table> {
  static var tableAlias: String? { "\(Base.tableName)TableInfo" }
  static var schemaName: String? { Base.schemaName }
  static var tableFragment: QueryFragment {
    "pragma_table_info(\(quote: Base.tableName, delimiter: .text))"
  }

  @Column("cid") let columnID: Int
  let name: String
  let type: String
  @Column("notnull") let isNotNull: Bool
  @Column("dflt_value") let defaultValue: String?
  @Column("pk") let isPrimaryKey: Bool
}
