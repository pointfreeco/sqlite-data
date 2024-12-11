import SharingGRDB
import SwiftUI

@main
struct SyncUpsApp: App {
  static let model = AppModel()

  init() {
    prepareDependencies {
      $0.defaultDatabase = .appDatabase
    }
  }

  var body: some Scene {
    WindowGroup {
      AppView(model: Self.model)
    }
  }
}
