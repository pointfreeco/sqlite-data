import CustomDump
import Foundation
import SQLiteData
import SwiftUI
import Testing

@testable import Reminders

@Suite(
  .dependency(\.continuousClock, ImmediateClock()),
  .dependency(\.date.now, Date(timeIntervalSince1970: 1234567890)),
  .dependency(\.uuid, .incrementing),
  .dependencies {
    $0.defaultDatabase = try Reminders.appDatabase()
    try $0.defaultDatabase.write { try $0.seedSampleData() }
  },
  .snapshots(record: .failed)
)
struct BaseTestSuite {}

// NB: SwiftUI colors are not consistently dumped across simulators.
extension RemindersList: @retroactive CustomDumpReflectable {
  public var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        "id": id,
        "color": Color.HexRepresentation(queryOutput: color).hexValue ?? 0,
        "position": position,
        "title": title
      ],
      displayStyle: .struct
    )
  }
}
