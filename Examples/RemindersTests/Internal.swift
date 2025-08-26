import Dependencies
import DependenciesTestSupport
import CustomDump
import Foundation
import SharingGRDB
import SnapshotTesting
import SwiftUI
import Testing

@testable import Reminders

@Suite(
  .dependency(\.date.now, Date(timeIntervalSince1970: 1234567890)),
  .dependency(\.uuid, .incrementing),
  .dependencies {
    try $0.bootstrapDatabase()
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
