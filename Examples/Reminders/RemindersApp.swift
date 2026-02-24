import CloudKit
import Combine
import Dependencies
import SQLiteData
import SwiftData
import SwiftUI
import UIKit

@main
struct RemindersApp: App {
  @UIApplicationDelegateAdaptor var delegate: AppDelegate
  @Dependency(\.context) var context
  @Dependency(\.defaultSyncEngine) var syncEngine
  static let model = RemindersListsModel()

  @State var syncEngineDelegate = RemindersSyncEngineDelegate()
  @State var undoManagerDelegate = RemindersUndoManagerDelegate()

  init() {
    if context == .live {
      try! prepareDependencies {
        try $0.bootstrapDatabase(
          syncEngineDelegate: syncEngineDelegate,
          undoManagerDelegate: undoManagerDelegate
        )
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView(model: Self.model)
        }
        .bindSQLiteUndoManagerToSystemUndo()
        .alert(
          "Reset local data?",
          isPresented: $syncEngineDelegate.isDeleteLocalDataAlertPresented
        ) {
          Button("Reset", role: .destructive) {
            Task {
              try await syncEngine.deleteLocalData()
            }
          }
        } message: {
          Text(
            """
            You are no longer logged into iCloud. Would you like to reset your local data to the \
            defaults? This will not affect your data in iCloud.
            """
          )
        }
        .alert(item: $undoManagerDelegate.confirmationRequest) { request in
          Alert(
            title: Text(request.title),
            message: Text(request.message),
            primaryButton: .destructive(Text(request.confirmButtonTitle)) {
              undoManagerDelegate.respondToConfirmation(confirmed: true)
            },
            secondaryButton: .cancel {
              undoManagerDelegate.respondToConfirmation(confirmed: false)
            }
          )
        }
      }
    }
  }
}

@MainActor
@Observable
class RemindersSyncEngineDelegate: SyncEngineDelegate {
  var isDeleteLocalDataAlertPresented = false
  func syncEngine(
    _ syncEngine: SQLiteData.SyncEngine,
    accountChanged changeType: CKSyncEngine.Event.AccountChange.ChangeType
  ) async {
    switch changeType {
    case .signIn:
      break
    case .signOut, .switchAccounts:
      isDeleteLocalDataAlertPresented = true
    @unknown default:
      break
    }
  }
}

@MainActor
@Observable
final class RemindersUndoManagerDelegate: SQLiteData.UndoManagerDelegate {
  struct ConfirmationRequest: Identifiable {
    let action: UndoAction
    let group: UndoGroup
    var id: UUID { group.id }
    var title: String {
      switch action {
      case .undo: "Undo \"\(group.description)\"?"
      case .redo: "Redo \"\(group.description)\"?"
      }
    }
    var message: String {
      "This change came from \(originDescription). Are you sure you want to continue?"
    }
    var confirmButtonTitle: String {
      switch action {
      case .undo: "Undo"
      case .redo: "Redo"
      }
    }

    private var originDescription: String {
      var parts: [String] = []
      if group.deviceID != SQLiteUndoManager.defaultDeviceID {
        if group.deviceID == "sqlitedata-sync" {
          parts.append("another device")
        } else {
          parts.append("device \(group.deviceID)")
        }
      }
      if
        let userRecordName = group.userRecordName
      {
        parts.append("user \(userRecordName)")
      }
      return parts.isEmpty ? "this device" : parts.joined(separator: " and ")
    }
  }

  var confirmationRequest: ConfirmationRequest?
  private var confirmationContinuation: CheckedContinuation<Bool, Never>?

  func undoManager(
    _ undoManager: SQLiteData.UndoManager,
    willPerform action: UndoAction,
    for group: UndoGroup,
    performAction: @isolated(any) @Sendable () async throws -> Void
  ) async throws {
    guard shouldConfirm(for: group) else {
      try await performAction()
      return
    }
    if await requestConfirmation(action: action, group: group) {
      try await performAction()
    }
  }

  func respondToConfirmation(confirmed: Bool) {
    confirmationContinuation?.resume(returning: confirmed)
    confirmationContinuation = nil
    confirmationRequest = nil
  }

  private func shouldConfirm(for group: UndoGroup) -> Bool {
    let isOtherDevice = group.deviceID != SQLiteUndoManager.defaultDeviceID
    let isOtherUser = group.userRecordName != nil
    return isOtherDevice || isOtherUser
  }

  private func requestConfirmation(action: UndoAction, group: UndoGroup) async -> Bool {
    if confirmationContinuation != nil {
      respondToConfirmation(confirmed: false)
    }
    return await withCheckedContinuation { continuation in
      confirmationContinuation = continuation
      confirmationRequest = ConfirmationRequest(action: action, group: group)
    }
  }
}

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    true
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
  @Dependency(\.defaultSyncEngine) var syncEngine
  var window: UIWindow?

  func windowScene(
    _ windowScene: UIWindowScene,
    userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
  ) {
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let cloudKitShareMetadata = connectionOptions.cloudKitShareMetadata
    else {
      return
    }
    Task {
      try await syncEngine.acceptShare(metadata: cloudKitShareMetadata)
    }
  }
}
