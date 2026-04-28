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
  enum ConfirmationReason {
    /// The group itself came from syncing.
    case syncOrigin
    /// The group is local but remote sync changes have arrived since.
    case syncChangesSinceRedo
  }

  struct ConfirmationRequest: Identifiable {
    let action: UndoAction
    let group: UndoGroup
    let reason: ConfirmationReason
    var id: UUID { group.id }
    var title: String {
      switch action {
      case .undo: "Undo \"\(group.description)\"?"
      case .redo: "Redo \"\(group.description)\"?"
      }
    }
    var message: String {
      switch reason {
      case .syncOrigin:
        "This change came from syncing. Are you sure you want to continue?"
      case .syncChangesSinceRedo:
        """
        Changes from another device or user have been applied since this action and could \
        potentially conflict with the changes you are trying to redo.
        """
      }
    }
    var confirmButtonTitle: String {
      switch action {
      case .undo: "Undo"
      case .redo: "Redo"
      }
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
    guard let reason = confirmationReason(
      undoManager: undoManager, action: action, group: group
    ) else {
      try await performAction()
      return
    }
    if await requestConfirmation(action: action, group: group, reason: reason) {
      try await performAction()
    }
  }

  func respondToConfirmation(confirmed: Bool) {
    confirmationContinuation?.resume(returning: confirmed)
    confirmationContinuation = nil
    confirmationRequest = nil
  }

  private func confirmationReason(
    undoManager: SQLiteData.UndoManager,
    action: UndoAction,
    group: UndoGroup
  ) -> ConfirmationReason? {
    if action == .undo && group.isSharedZoneChange {
      return .syncOrigin
    }
    if action == .redo && undoManager.hasSyncChangesSince(group) {
      return .syncChangesSinceRedo
    }
    return nil
  }

  private func requestConfirmation(
    action: UndoAction,
    group: UndoGroup,
    reason: ConfirmationReason
  ) async -> Bool {
    if confirmationContinuation != nil {
      respondToConfirmation(confirmed: false)
    }
    return await withCheckedContinuation { continuation in
      confirmationContinuation = continuation
      confirmationRequest = ConfirmationRequest(
        action: action, group: group, reason: reason
      )
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
