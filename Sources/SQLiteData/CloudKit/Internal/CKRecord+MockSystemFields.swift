#if canImport(CloudKit)
  import CloudKit
  import IssueReporting
  import ObjectiveC

  nonisolated(unsafe) private var modificationDateKey: UInt8 = 0

  extension CKRecord {
    var _modificationDate: Date? {
      get {
        objc_getAssociatedObject(self, &modificationDateKey) as? Date
      }
      set {
        installMockSystemFieldOverridesOnce()
        objc_setAssociatedObject(self, &modificationDateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
    }

    @objc fileprivate dynamic func _swizzled_modificationDate() -> Date? {
      if let override = objc_getAssociatedObject(self, &modificationDateKey) as? Date {
        return override
      }
      return self._swizzled_modificationDate()
    }
  }

  private func installMockSystemFieldOverridesOnce() {
    _ = token
  }

  private let token: Void = {
    guard
      let originalMethod = class_getInstanceMethod(
        CKRecord.self,
        #selector(getter: CKRecord.modificationDate)
      ),
      let swizzledMethod = class_getInstanceMethod(
        CKRecord.self,
        #selector(CKRecord._swizzled_modificationDate)
      )
    else {
      reportIssue("Failed to swizzle CKRecord.modificationDate")
      return
    }
    method_exchangeImplementations(originalMethod, swizzledMethod)
  }()
#endif
