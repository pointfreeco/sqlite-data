import CloudKit
import SwiftUI
import UIKit

#if canImport(UIKit)
//import UIKit
//extension UICloudSharingController {
//  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
//  public convenience init<T: PrimaryKeyedTable>(_ record: T)
//  where T.TableColumns.PrimaryKey == UUID {
//    // TODO: Remove UUID constraint by reaching into metadata table
//    // TODO: verify that table has no foreign keys
//    @Dependency(\.defaultSyncEngine) var syncEngine
//    let record = try! syncEngine.database.write { db in
//      return
//      try Metadata
//        .find(
//          recordID: CKRecord.ID.init(
//            recordName: record[keyPath: T.columns.primaryKey.keyPath].uuidString.lowercased()
//          )
//        )
//        .select(\.lastKnownServerRecord)
//        .fetchOne(db)
//    }
//    self.init(
//      share: CKShare(rootRecord: record!!),
//      container: syncEngine.container
//    )
//  }
//}
//
//import SwiftUI
//
//@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
//public struct CloudSharingView<T: PrimaryKeyedTable>: UIViewControllerRepresentable
//where T.TableColumns.PrimaryKey == UUID {
//  let record: T
//  public init(_ record: T) {
//    self.record = record
//  }
//
//  public func makeUIViewController(context: Context) -> UICloudSharingController {
//    UICloudSharingController(record)
//  }
//
//  public func updateUIViewController(
//    _ uiViewController: UICloudSharingController,
//    context: Context
//  ) {
//  }
//}
//
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public struct CloudSharingView2: UIViewControllerRepresentable {
  let share: CKShare
  public init(share: CKShare) {
    self.share = share
  }

  public func makeUIViewController(context: Context) -> UICloudSharingController {
    // TODO: Should we take the container from the sync engine or should we require it to be passed in?
    @Dependency(\.defaultSyncEngine) var syncEngine
    return UICloudSharingController(share: share, container: syncEngine.container)
  }

  public func updateUIViewController(
    _ uiViewController: UICloudSharingController,
    context: Context
  ) {
  }
}
#endif
