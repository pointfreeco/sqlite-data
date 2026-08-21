import DebugSnapshots
import Dependencies
import DependenciesTestSupport
import Foundation
import SQLiteData
import StructuredQueries
import Testing

@testable import SyncUps

@Suite(
  .dependencies {
    try $0.bootstrapDatabase()
    try await $0.defaultSyncEngine.start()
    try await $0.defaultDatabase.seedForTests()
    $0.uuid = .incrementing
  }
)
struct SyncUpFormTests {
  @Dependency(\.defaultDatabase) var database

  @Test func saveNew() async throws {
    let draft = SyncUp.Draft(title: "Morning Sync")
    let model = SyncUpFormModel(syncUp: draft)
    expect(model) {
      $0.attendees = [SyncUpFormModel.AttendeeDraft(id: UUID(0))]
      $0.focus = .title
      $0.isDismissed = false
      $0.syncUp = SyncUp.Draft(title: "Morning Sync")
    }

    expect(model) {
      model.addAttendeeButtonTapped()
    } changes: {
      $0.attendees.append(SyncUpFormModel.AttendeeDraft(id: UUID(1)))
      $0.focus = .attendee(UUID(1))
    }
    expect(model) {
      model.addAttendeeButtonTapped()
    } changes: {
      $0.attendees.append(SyncUpFormModel.AttendeeDraft(id: UUID(2)))
      $0.focus = .attendee(UUID(2))
    }
    model.attendees[0].name = "Blob"
    model.attendees[1].name = "Blob Jr."
    expect(model) {
      model.saveButtonTapped()
    } changes: {
      $0.attendees.removeLast()
      $0.isDismissed = true
    }

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
      try #require(try SyncUp.fetchOne(db))
    }
    let draft = SyncUp.Draft(existingSyncUp)
    let model = SyncUpFormModel(syncUp: draft)
    expect(model) {
      $0.attendees = [
        SyncUpFormModel.AttendeeDraft(id: UUID(0), name: "Blob"),
        SyncUpFormModel.AttendeeDraft(id: UUID(1), name: "Blob Jr"),
        SyncUpFormModel.AttendeeDraft(id: UUID(2), name: "Blob Sr"),
        SyncUpFormModel.AttendeeDraft(id: UUID(3), name: "Blob Esq"),
        SyncUpFormModel.AttendeeDraft(id: UUID(4), name: "Blob III"),
        SyncUpFormModel.AttendeeDraft(id: UUID(5), name: "Blob I"),
      ]
      $0.focus = .title
      $0.isDismissed = false
      $0.syncUp = SyncUp.Draft(
        id: UUID(1),
        seconds: 60,
        theme: .appOrange,
        title: "Design"
      )
    }

    model.syncUp.title = "Evening Sync"
    expect(model) {
      model.deleteAttendees(atOffsets: [1, 2, 3, 4, 5])
    } changes: {
      $0.attendees.removeSubrange(1...5)
      $0.focus = .attendee(UUID(0))
    }
    expect(model) {
      model.addAttendeeButtonTapped()
    } changes: {
      $0.attendees.append(SyncUpFormModel.AttendeeDraft(id: UUID(6)))
      $0.focus = .attendee(UUID(6))
    }
    model.attendees[model.attendees.count - 1].name = "Blobby McBlob"
    expect(model) {
      model.saveButtonTapped()
    } changes: {
      $0.isDismissed = true
    }

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
