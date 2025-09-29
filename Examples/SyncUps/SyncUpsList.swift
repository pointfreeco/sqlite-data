import SQLiteData
import SwiftUI
import SwiftUINavigation
import TipKit

@MainActor
@Observable
final class SyncUpsListModel {
  var addSyncUp: SyncUpFormModel?
  @ObservationIgnored
  @FetchAll(
    SyncUp
      .group(by: \.id)
      .leftJoin(Attendee.all) { $0.id.eq($1.syncUpID) }
      .select { Row.Columns(attendeeCount: $1.count(), syncUp: $0) },
    animation: .default
  )
  var syncUps: [Row]
  @ObservationIgnored @Dependency(\.uuid) var uuid
  @ObservationIgnored @Dependency(\.defaultDatabase) var database

  init(
    addSyncUp: SyncUpFormModel? = nil
  ) {
    self.addSyncUp = addSyncUp
  }

  func addSyncUpButtonTapped() {
    addSyncUp = withDependencies(from: self) {
      SyncUpFormModel(syncUp: SyncUp.Draft())
    }
  }

  #if DEBUG
    func seedDatabase() {
      withErrorReporting {
        try database.write { db in
          try db.seedSampleData()
        }
      }
    }
  #endif

  @Selection
  struct Row: Identifiable {
    let attendeeCount: Int
    let syncUp: SyncUp

    var id: SyncUp.ID { syncUp.id }
  }
}

struct SyncUpsList: View {
  @State var model = SyncUpsListModel()
  @State private var seedDatabaseTip: SeedDatabaseTip?

  var body: some View {
    List {
      ForEach(model.syncUps) { state in
        NavigationLink(value: AppModel.Path.detail(SyncUpDetailModel(syncUp: state.syncUp))) {
          CardView(syncUp: state.syncUp, attendeeCount: state.attendeeCount)
        }
        .listRowBackground(state.syncUp.theme.mainColor)
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.addSyncUpButtonTapped()
        } label: {
          Image(systemName: "plus")
        }
      }
      #if DEBUG
        ToolbarItem(placement: .automatic) {
          Menu {
            Button {
              model.seedDatabase()
            } label: {
              Text("Seed data")
              Image(systemName: "leaf")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .popoverTip(seedDatabaseTip)
          .task {
            await withErrorReporting {
              try Tips.configure()
              try await model.$syncUps.load()
              if model.syncUps.isEmpty {
                seedDatabaseTip = SeedDatabaseTip()
              }
            }
          }
        }
      #endif
    }
    .navigationTitle("Daily Sync-ups")
    .sheet(item: $model.addSyncUp) { syncUpFormModel in
      NavigationStack {
        SyncUpFormView(model: syncUpFormModel)
          .navigationTitle("New sync-up")
      }
    }
  }
}

struct CardView: View {
  let syncUp: SyncUp
  let attendeeCount: Int

  var body: some View {
    VStack(alignment: .leading) {
      Text(syncUp.title)
        .font(.headline)
      Spacer()
      HStack {
        Label("\(attendeeCount)", systemImage: "person.3")
        Spacer()
        Label(syncUp.seconds.duration.formatted(.units()), systemImage: "clock")
          .labelStyle(.trailingIcon)
      }
      .font(.caption)
    }
    .padding()
    .foregroundColor(syncUp.theme.accentColor)
  }
}

struct TrailingIconLabelStyle: LabelStyle {
  func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack {
      configuration.title
      configuration.icon
    }
  }
}

extension LabelStyle where Self == TrailingIconLabelStyle {
  static var trailingIcon: Self { Self() }
}

private struct SeedDatabaseTip: Tip {
  var title: Text {
    Text("Seed Sample Data")
  }
  var message: Text? {
    Text("Tap here to quickly populate the app with test data.")
  }
  var image: Image? {
    Image(systemName: "leaf")
  }
}

#Preview {
  let _ = try! prepareDependencies {
    try $0.bootstrapDatabase()
  }
  NavigationStack {
    SyncUpsList(model: SyncUpsListModel())
  }
}
