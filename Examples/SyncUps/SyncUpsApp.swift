import SharingGRDB
import SwiftUI

@main
struct SyncUpsApp: App {
  static let model = AppModel()

  init() {
    if !isTesting {
      try! prepareDependencies {
        $0.defaultDatabase = try SyncUps.appDatabase()
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if !isTesting {
        AppView(model: Self.model)
      }
    }
  }
}
