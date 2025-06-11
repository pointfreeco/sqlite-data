import Foundation
import SharingGRDB

@testable import SyncUps

extension Database {
  func seedSyncUpFormTests() throws {
    try seed {
      SyncUp(id: UUID(1), seconds: 60, theme: .appOrange, title: "Design")
      SyncUp(id: UUID(2), seconds: 60 * 10, theme: .periwinkle, title: "Engineering")
      SyncUp(id: UUID(3), seconds: 60 * 30, theme: .poppy, title: "Product")

      for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
        Attendee.Draft(name: name, syncUpID: UUID(1))
      }
      for name in ["Blob", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: UUID(2))
      }
      for name in ["Blob Sr", "Blob Jr"] {
        Attendee.Draft(name: name, syncUpID: UUID(3))
      }

      Meeting.Draft(
        date: Date().addingTimeInterval(-60 * 60 * 24 * 7),
        syncUpID: UUID(1),
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
