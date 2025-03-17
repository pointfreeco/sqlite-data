import SharingGRDB
import StructuredQueries
import SwiftUI
import SwiftUINavigation

@MainActor
@Observable
final class SyncUpsListModel {
  var addSyncUp: SyncUpFormModel?
  @ObservationIgnored @SharedReader(
    .fetchAll(
      SyncUp
        .group(by: \.id)
        .leftJoin(Attendee.all()) { $0.id.eq($1.syncUpID) }
        .select { Record.Columns(attendeeCount: $1.id.count(), syncUp: $0) },
      animation: .default
    )
  )
  var syncUps: [Record]
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

  @Selection
  struct Record {
    let attendeeCount: Int
    let syncUp: SyncUp
  }
}

struct SyncUpsList: View {
  @State var model = SyncUpsListModel()

  var body: some View {
    List {
      ForEach(model.syncUps, id: \.syncUp.id) { state in
        NavigationLink(value: AppModel.Path.detail(SyncUpDetailModel(syncUp: state.syncUp))) {
          CardView(syncUp: state.syncUp, attendeeCount: state.attendeeCount)
        }
        .listRowBackground(state.syncUp.theme.mainColor)
      }
    }
    .toolbar {
      Button {
        model.addSyncUpButtonTapped()
      } label: {
        Image(systemName: "plus")
      }
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

#Preview {
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try SyncUps.appDatabase()
  }
  NavigationStack {
    SyncUpsList(model: SyncUpsListModel())
  }
}
