protocol StatementKeyRequest<QueryValue>: FetchKeyRequest {
  associatedtype QueryValue
  var statement: SQLQueryExpression<QueryValue> { get }
}

extension StatementKeyRequest {
  static func == (lhs: Self, rhs: Self) -> Bool {
    // NB: A Swift 6.1 regression prevents this from compiling:
    //     https://github.com/swiftlang/swift/issues/79623
    // return AnyHashable(lhs.statement) == AnyHashable(rhs.statement)
    let lhs = lhs.statement
    let rhs = rhs.statement
    return AnyHashable(lhs) == AnyHashable(rhs)
  }

  func hash(into hasher: inout Hasher) {
    // NB: A Swift 6.1 regression prevents this from compiling:
    //     https://github.com/swiftlang/swift/issues/79623
    // hasher.combine(statement)
    let statement = statement
    hasher.combine(statement)
  }
}
