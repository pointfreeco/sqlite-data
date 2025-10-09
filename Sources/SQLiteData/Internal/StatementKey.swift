protocol StatementKeyRequest<QueryValue>: FetchKeyRequest {
  associatedtype QueryValue
  var statement: SQLQueryExpression<QueryValue> { get }
}

extension StatementKeyRequest {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.statement.query == rhs.statement.query
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(statement.query)
  }
}
