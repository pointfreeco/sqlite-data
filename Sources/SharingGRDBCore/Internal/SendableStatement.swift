import StructuredQueriesCore

typealias SendableStatement<QueryValue> = StructuredQueriesCore.Statement<QueryValue> & Sendable
