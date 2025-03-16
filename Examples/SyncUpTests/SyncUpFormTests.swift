import Dependencies
import DependenciesTestSupport
import Testing

@testable import SyncUps

@Suite
struct SyncUpFormTests {
  @Dependency(\.defaultDatabase) var database

  @Test func saveNew() async throws {
    prepareDependencies {
      $0.defaultDatabase = try! SyncUps.appDatabase(inMemory: true)
      $0.uuid = .incrementing
    }
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
    prepareDependencies {
      $0.defaultDatabase = try! SyncUps.appDatabase(inMemory: true)
      $0.uuid = .incrementing
    }
    let existingSyncUp = try await database.read { db in
      try #require(try SyncUp.all().fetchOne(db))
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
