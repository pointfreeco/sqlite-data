import Foundation
import SharingGRDB
import SwiftUI
import Testing

@testable import Reminders

@Suite(
  .dependency(\.date.now, Date(timeIntervalSince1970: 1234567890)),
  .dependency(\.uuid, .incrementing),
  .dependencies {
    $0.defaultDatabase = try Reminders.appDatabase()
    try $0.defaultDatabase.write { try $0.seedSampleData() }
  },
  .snapshots(record: .failed)
)
struct BaseTestSuite {}
