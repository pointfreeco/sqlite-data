import CloudKit
import Combine
import Dependencies
import SharingGRDB
import SwiftUI
import UIKit

import SwiftData

@main
struct RemindersApp: App {
  @UIApplicationDelegateAdaptor var delegate: AppDelegate
  @Dependency(\.context) var context
  static let model = RemindersListsModel()

  init() {
    if context == .live {
      try! prepareDependencies {
        try $0.bootstrapDatabase()
      }

      let container = CKContainer(identifier: ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier!)

//      Task {
//        do {
//          let record = CKRecord.init(recordType: "foo", recordID: CKRecord.ID.init(recordName: "bar"))
//          let (saves, _) = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
//          print(#line, saves)
//
//          let fetchedRecord = try await container.privateCloudDatabase.record(for: record.recordID)
//          print(fetchedRecord)
//
//          let (_, deletes) = try await container.privateCloudDatabase.modifyRecords(saving: [], deleting: [record.recordID])
//          print(#line, deletes)
//
//          let newRecord = CKRecord.init(recordType: "foo", recordID: CKRecord.ID.init(recordName: "bar"))
//          let (newSaves, _) = try await container.privateCloudDatabase.modifyRecords(saving: [newRecord], deleting: [])
//          print(#line, newSaves)
//
//          print("!!!")
//
//        } catch {
//          print(error)
//          print("-----")
//        }
//      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView(model: Self.model)
        }
      }
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: "Default Configuration",
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func windowScene(
    _ windowScene: UIWindowScene,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    @Dependency(\.defaultSyncEngine) var syncEngine
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
