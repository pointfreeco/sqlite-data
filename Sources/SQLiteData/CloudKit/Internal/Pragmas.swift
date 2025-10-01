#if canImport(CloudKit)
  @Table
  struct PragmaDatabaseList {
    static var tableAlias: String? { "databases" }
    static var tableFragment: QueryFragment { "pragma_database_list()" }

    @Column("seq") let sequence: Int
    let name: String
    let file: String
  }

  @Table
  struct PragmaForeignKeyCheck {
    static var tableAlias: String? { "foreignKeyChecks" }
    static var tableFragment: QueryFragment { "pragma_foreign_key_check()" }

    let table: String
    let rowid: Int
    let parent: String
    @Column("fkid")
    let index: Int
  }

  @Table
  package struct PragmaForeignKeyList<Base: Table> {
    package static var tableAlias: String? { "\(Base.tableName)ForeignKeys" }
    package static var tableFragment: QueryFragment {
      "pragma_foreign_key_list(\(quote: Base.tableName, delimiter: .text))"
    }

    package let id: Int
    @Column("seq") package let sequence: Int
    package let table: String
    package let from: String
    package let to: String
    @Column("on_update") package let onUpdate: ForeignKeyAction
    @Column("on_delete") package let onDelete: ForeignKeyAction
    package let match: String
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
  package struct PragmaTableInfo<Base: Table> {
    package static var tableAlias: String? { "\(Base.tableName)TableInfo" }
    package static var schemaName: String? { Base.schemaName }
    package static var tableFragment: QueryFragment {
      "pragma_table_info(\(quote: Base.tableName, delimiter: .text))"
    }

    @Column("cid") package let columnID: Int
    package let name: String
    package let type: String
    @Column("notnull") package let isNotNull: Bool
    @Column("dflt_value") package let defaultValue: String?
    @Column("pk") package let isPrimaryKey: Bool
  }
#endif
