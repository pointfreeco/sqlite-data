import Dependencies
import DependenciesTestSupport
import GRDB
import Foundation
import StructuredQueries
import Testing

@testable import SyncUps

@Suite(
  .dependencies {
    $0.defaultDatabase = try! SyncUps.appDatabase()
    try! $0.defaultDatabase.write { try $0.seedSyncUpFormTests() }
    $0.uuid = .incrementing
  }
)
struct SyncUpFormTests {
  @Dependency(\.defaultDatabase) var database

  @Test func saveNew() async throws {
    let draft = SyncUp.Draft(title: "Morning Sync")
    let model = SyncUpFormModel(syncUp: draft)
    model.addAttendeeButtonTapped()
    model.addAttendeeButtonTapped()
    model.attendees[0].name = "Blob"
    model.attendees[1].name = "Blob Jr."
    model.saveButtonTapped()

    let syncUp = try await database.read { db in
      try #require(try SyncUp.order { $0.id.desc() }.fetchOne(db))
    }
    #expect(syncUp.title == "Morning Sync")
    let attendees = try await database.read { db in
      try Attendee.where { $0.syncUpID.eq(syncUp.id) }.fetchAll(db)
    }
    #expect(attendees.map(\.name) == ["Blob", "Blob Jr."])
  }

  @Test func updateExisting() async throws {
    let existingSyncUp = try await database.read { db in
      try #require(try SyncUp.all.fetchOne(db))
    }
    let draft = SyncUp.Draft(existingSyncUp)
    let model = SyncUpFormModel(syncUp: draft)
    model.syncUp.title = "Evening Sync"
    model.deleteAttendees(atOffsets: [1, 2, 3, 4, 5])
    model.addAttendeeButtonTapped()
    model.attendees[model.attendees.count - 1].name = "Blobby McBlob"
    model.saveButtonTapped()

    let syncUp = try await database.read { db in
      try #require(try SyncUp.where { $0.id.eq(existingSyncUp.id) }.fetchOne(db))
    }
    #expect(syncUp.title == "Evening Sync")
    let attendees = try await database.read { db in
      try Attendee.where { $0.syncUpID.eq(existingSyncUp.id) }.fetchAll(db)
    }
    #expect(attendees.map(\.name) == ["Blob", "Blobby McBlob"])
  }
}

extension Database {
  fileprivate func seedSyncUpFormTests() throws {
    try seed {
      SyncUp(id: 1, seconds: 60, theme: .appOrange, title: "Design")
      SyncUp(id: 2, seconds: 60 * 10, theme: .periwinkle, title: "Engineering")
      SyncUp(id: 3, seconds: 60 * 30, theme: .poppy, title: "Product")

      for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
        Attendee.Draft(name: name, syncUpID: 1)
      }
      for name in ["Blob", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: 2)
      }
      for name in ["Blob Sr", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: 3)
      }

      Meeting.Draft(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
        syncUpID: 1,
        transcript: """
          Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor \
          incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud \
          exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute \
          irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla \
          pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia \
          deserunt mollit anim id est laborum.
          """
      )
    }
  }
}
