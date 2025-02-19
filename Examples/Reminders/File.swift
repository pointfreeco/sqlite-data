import StructuredQueries
import Foundation

@Table
struct SyncUp: Codable, Hashable {
  var id: Int64?
  var isDeleted = false
  var seconds = 60 * 5
  var title = ""
  static let notDeleted = Self.where { !$0.isDeleted }
}

@Table
struct Attendee: Codable, Hashable {
  var id: Int64?
  var isDeleted = false
  var name = ""
  var syncUpID: Int64
  static let notDeleted = Self.where { !$0.isDeleted }
  static let withSyncUp = Attendee.notDeleted
    .join(SyncUp.notDeleted) { $0.syncUpID == $1.id }
}


