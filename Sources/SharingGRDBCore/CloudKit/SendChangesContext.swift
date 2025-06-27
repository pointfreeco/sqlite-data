#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    package struct SendChangesContext: Sendable {
      package var reason: CKSyncEngine.SyncReason
      package var options: CKSyncEngine.SendChangesOptions
      package init(
        reason: CKSyncEngine.SyncReason = .scheduled,
        options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(scope: .all)
      ) {
        self.reason = reason
        self.options = options
      }
      init(context: CKSyncEngine.SendChangesContext) {
        reason = context.reason
        options = context.options
      }
    }
  }
#endif
