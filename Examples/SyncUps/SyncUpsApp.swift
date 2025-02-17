import SharingGRDB
import SwiftUI

@main
struct SyncUpsApp: App {
  static let model = AppModel()

  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try SyncUps.appDatabase(inMemory: false)
    }
  }

  var body: some Scene {
    WindowGroup {
      AppView(model: Self.model)
    }
  }
}
