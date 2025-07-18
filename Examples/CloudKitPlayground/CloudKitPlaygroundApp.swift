import CloudKit
import SharingGRDB
import SwiftUI
import UIKit

@main
struct CloudKitPlaygroundApp: App {
  @UIApplicationDelegateAdaptor var delegate: AppDelegate

  init() {
    let container = CKContainer(
      identifier: "iCloud.co.pointfree.SQLiteData.demos.CloudKitPlayground"
    )
    prepareDependencies {
      $0.defaultDatabase = try! appDatabase()
      $0.defaultSyncEngine = try! SyncEngine(
        container: container,
        database: $0.defaultDatabase,
        tables: [ModelA.self, ModelB.self, ModelC.self]
      )
    }
    Task {
      let record = CKRecord.init(
        recordType: "A\(Int.random(in: 1...999_999_999))",
        recordID: CKRecord.ID.init(
          recordName: UUID().uuidString,
          zoneID: CKRecordZone.ID.init(zoneName: UUID().uuidString)
        )
      )
      do {
        //let results = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [])
        let results = try await container.privateCloudDatabase.modifyRecords(
          saving: [],
          deleting: [record.recordID]
        )
        print("success")
        print(results)
        print("!!!!")
      } catch {
        print(error)
        print("!!!")
      }
    }
  }
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        ModelAView()
      }
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
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
