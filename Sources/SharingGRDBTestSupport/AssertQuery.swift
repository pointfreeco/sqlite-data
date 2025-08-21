import CustomDump
import Foundation
import InlineSnapshotTesting
import StructuredQueriesCore
import StructuredQueriesTestSupport

/// An end-to-end snapshot testing helper for database content.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// ) {
///   try db.execute($0)
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - includeSQL: Whether to snapshot the SQL fragment in addition to the results.
///   - query: A statement.
///   - execute: A closure responsible for executing the query and returning the results.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - snapshotTrailingClosureOffset: The trailing closure offset of the `sql` snapshot. Defaults
///     to `1` for invoking this helper directly, but if you write a wrapper function that automates
///     the `execute` trailing closure, you should pass `0` instead.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
@_disfavoredOverload
public func assertQuery<each V: QueryRepresentable, S: Statement<(repeat each V)>>(
  includeSQL: Bool = false,
  _ query: S,
  execute: (S) throws -> [(repeat (each V).QueryOutput)],
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  snapshotTrailingClosureOffset: Int = 1,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  if includeSQL {
    assertInlineSnapshot(
      of: query,
      as: .sql,
      message: "Query did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "sql",
        trailingClosureOffset: snapshotTrailingClosureOffset
      ),
      matches: sql,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
  do {
    let rows = try execute(query)
    var table = ""
    printTable(rows, to: &table)
    if !table.isEmpty {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results did not match",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? snapshotTrailingClosureOffset + 1 : snapshotTrailingClosureOffset
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    } else if results != nil {
      assertInlineSnapshot(
        of: table,
        as: .lines,
        message: "Results expected to be empty",
        syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
          trailingClosureLabel: "results",
          trailingClosureOffset: includeSQL ? snapshotTrailingClosureOffset + 1 : snapshotTrailingClosureOffset
        ),
        matches: results,
        fileID: fileID,
        file: filePath,
        function: function,
        line: line,
        column: column
      )
    }
  } catch {
    assertInlineSnapshot(
      of: error.localizedDescription,
      as: .lines,
      message: "Results did not match",
      syntaxDescriptor: InlineSnapshotSyntaxDescriptor(
        trailingClosureLabel: "results",
        trailingClosureOffset: includeSQL ? snapshotTrailingClosureOffset + 1 : snapshotTrailingClosureOffset
      ),
      matches: results,
      fileID: fileID,
      file: filePath,
      function: function,
      line: line,
      column: column
    )
  }
}

/// An end-to-end snapshot testing helper for database content.
///
/// This helper can be used to generate snapshots of both the given query and the results of the
/// query decoded back into Swift.
///
/// ```swift
/// assertQuery(
///   Reminder.select(\.title).order(by: \.title)
/// ) {
///   try db.execute($0)
/// } results: {
///   """
///   ┌────────────────────────────┐
///   │ "Buy concert tickets"      │
///   │ "Call accountant"          │
///   │ "Doctor appointment"       │
///   │ "Get laundry"              │
///   │ "Groceries"                │
///   │ "Haircut"                  │
///   │ "Pick up kids from school" │
///   │ "Send weekly emails"       │
///   │ "Take a walk"              │
///   │ "Take out trash"           │
///   └────────────────────────────┘
///   """
/// }
/// ```
///
/// - Parameters:
///   - includeSQL: Whether to snapshot the SQL fragment in addition to the results.
///   - query: A statement.
///   - execute: A closure responsible for executing the query and returning the results.
///   - sql: A snapshot of the SQL produced by the statement.
///   - results: A snapshot of the results.
///   - snapshotTrailingClosureOffset: The trailing closure offset of the `sql` snapshot. Defaults
///     to `1` for invoking this helper directly, but if you write a wrapper function that automates
///     the `execute` trailing closure, you should pass `0` instead.
///   - fileID: The source `#fileID` associated with the assertion.
///   - filePath: The source `#filePath` associated with the assertion.
///   - function: The source `#function` associated with the assertion
///   - line: The source `#line` associated with the assertion.
///   - column: The source `#column` associated with the assertion.
public func assertQuery<S: SelectStatement, each J: Table>(
  includeSQL: Bool = false,
  _ query: S,
  execute: (Select<(S.From, repeat each J), S.From, (repeat each J)>) throws -> [(
    S.From.QueryOutput, repeat (each J).QueryOutput
  )],
  sql: (() -> String)? = nil,
  results: (() -> String)? = nil,
  snapshotTrailingClosureOffset: Int = 1,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: StaticString = #function,
  line: UInt = #line,
  column: UInt = #column
) where S.QueryValue == (), S.Joins == (repeat each J) {
  assertQuery(
    includeSQL: includeSQL,
    query.selectStar(),
    execute: execute,
    sql: sql,
    results: results,
    snapshotTrailingClosureOffset: snapshotTrailingClosureOffset,
    fileID: fileID,
    filePath: filePath,
    function: function,
    line: line,
    column: column
  )
}

private func printTable<each C>(_ rows: [(repeat each C)], to output: inout some TextOutputStream) {
  var maxColumnSpan: [Int] = []
  var hasMultiLineRows = false
  for _ in repeat (each C).self {
    maxColumnSpan.append(0)
  }
  var table: [([[Substring]], maxRowSpan: Int)] = []
  for row in rows {
    var columns: [[Substring]] = []
    var index = 0
    var maxRowSpan = 0
    for column in repeat each row {
      defer { index += 1 }
      var cell = ""
      customDump(column, to: &cell)
      let lines = cell.split(separator: "\n")
      hasMultiLineRows = hasMultiLineRows || lines.count > 1
      maxRowSpan = max(maxRowSpan, lines.count)
      maxColumnSpan[index] = max(maxColumnSpan[index], lines.map(\.count).max() ?? 0)
      columns.append(lines)
    }
    table.append((columns, maxRowSpan))
  }
  guard !table.isEmpty else { return }
  output.write("┌─")
  output.write(
    maxColumnSpan
      .map { String(repeating: "─", count: $0) }
      .joined(separator: "─┬─")
  )
  output.write("─┐\n")
  for (offset, rowAndMaxRowSpan) in table.enumerated() {
    let (row, maxRowSpan) = rowAndMaxRowSpan
    for rowOffset in 0..<maxRowSpan {
      output.write("│ ")
      var line: [String] = []
      for (columns, maxColumnSpan) in zip(row, maxColumnSpan) {
        if columns.count <= rowOffset {
          line.append(String(repeating: " ", count: maxColumnSpan))
        } else {
          line.append(
            columns[rowOffset]
              + String(repeating: " ", count: maxColumnSpan - columns[rowOffset].count)
          )
        }
      }
      output.write(line.joined(separator: " │ "))
      output.write(" │\n")
    }
    if hasMultiLineRows, offset != table.count - 1 {
      output.write("├─")
      output.write(
        maxColumnSpan
          .map { String(repeating: "─", count: $0) }
          .joined(separator: "─┼─")
      )
      output.write("─┤\n")
    }
  }
  output.write("└─")
  output.write(
    maxColumnSpan
      .map { String(repeating: "─", count: $0) }
      .joined(separator: "─┴─")
  )
  output.write("─┘")
}
