import StructuredQueriesCore

protocol StatementKeyRequest<QueryValue>: FetchKeyRequest {
  associatedtype QueryValue
  var prepared: PreparedQuery { get }
}

extension StatementKeyRequest {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.prepared.sql == rhs.prepared.sql && lhs.prepared.bindings == rhs.prepared.bindings
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(prepared.sql)
    hasher.combine(prepared.bindings)
  }
}
