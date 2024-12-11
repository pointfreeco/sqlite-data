import SharingGRDB
import SwiftNavigation
import SwiftUI
import UIKit
import UIKitNavigation

final class UIKitCaseStudyViewController: UICollectionViewController, UIKitCaseStudy {
  let caseStudyTitle = "UIKit"
  let readMe = """
    This case study demonstrates how to use the 'fetchAll' tool in a UIKit app. The view \
    controller observes changes to the database and updates a collection view when data is added \
    or removed.
    """

  private var dataSource: UICollectionViewDiffableDataSource<Section, Fact>!
  @SharedReader(.fetchAll(sql: #"SELECT * FROM "facts" ORDER BY "id" DESC"#, animation: .default))
  private var facts: [Fact]
  private var viewDidLoadTask: Task<Void, Error>?

  @Dependency(\.defaultDatabase) var database

  init() {
    var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    configuration.trailingSwipeActionsConfigurationProvider = {
      [database = _database, facts = _facts] indexPath in
      UISwipeActionsConfiguration(
        actions: [
          UIContextualAction(
            style: .destructive,
            title: "Delete"
          ) { action, view, completion in
            _ = withErrorReporting {
              try database.wrappedValue.write { db in
                try facts.wrappedValue[indexPath.row].delete(db)
              }
            }
          }
        ]
      )
    }
    super.init(
      collectionViewLayout: UICollectionViewCompositionalLayout.list(
        using: configuration
      )
    )
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    viewDidLoadTask?.cancel()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, Fact> {
      cell, indexPath, fact in
      var configuration = cell.defaultContentConfiguration()
      defer { cell.contentConfiguration = configuration }
      configuration.text = fact.body
    }

    self.dataSource = UICollectionViewDiffableDataSource<Section, Fact>(
      collectionView: self.collectionView
    ) { collectionView, indexPath, item in
      collectionView.dequeueConfiguredReusableCell(
        using: cellRegistration,
        for: indexPath,
        item: item
      )
    }

    observe { [weak self] in
      guard let self else { return }
      var snapshot = NSDiffableDataSourceSnapshot<Section, Fact>()
      snapshot.appendSections([.facts])
      snapshot.appendItems(facts, toSection: .facts)
      dataSource.apply(snapshot, animatingDifferences: true)
    }

    viewDidLoadTask = Task { [weak self] in
      guard let self else { return }

      var number = 0
      while true {
        try await Task.sleep(for: .seconds(1))
        number += 1
        let fact = try? await String(
          decoding: URLSession.shared
            .data(from: URL(string: "http://numberapi.com/\(number)")!).0,
          as: UTF8.self
        )
        if let fact {
          await withErrorReporting {
            try await database.write { db in
              _ = try Fact(body: fact).inserted(db)
            }
          }
        }
      }
    }
  }

  enum Section: Hashable {
    case facts
  }
}

private struct Fact: Codable, FetchableRecord, Hashable, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "facts"
  var id: Int64?
  var body: String
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var uiKitDemoDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'facts' table") { db in
      try db.create(table: Fact.databaseTableName) { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("body", .text).notNull()
      }
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .uiKitDemoDatabase
  }
  UINavigationController(caseStudy: UIKitCaseStudyViewController())
}
