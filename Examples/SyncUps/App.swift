import CasePaths
import SQLiteData
import SwiftUI

@MainActor
@Observable
class AppModel {
  var path: [Path] {
    didSet { bind() }
  }
  var syncUpsList: SyncUpsListModel {
    didSet { bind() }
  }

  @ObservationIgnored
  @Dependency(\.date.now) var now
  @ObservationIgnored
  @Dependency(\.uuid) var uuid

  @CasePathable
  @dynamicMemberLookup
  enum Path: Hashable {
    case detail(SyncUpDetailModel)
    case meeting(Meeting, attendees: [Attendee])
    case record(RecordMeetingModel)
  }

  init(
    path: [Path] = [],
    syncUpsList: SyncUpsListModel = SyncUpsListModel()
  ) {
    self.path = path
    self.syncUpsList = syncUpsList
    self.bind()
  }

  private func bind() {
    for destination in path {
      switch destination {
      case .detail(let detailModel):
        bindDetail(model: detailModel)

      case .meeting, .record:
        break
      }
    }
  }

  private func bindDetail(model: SyncUpDetailModel) {
    model.onMeetingStarted = { [weak self] syncUp, attendees in
      guard let self else { return }
      withDependencies(from: self) {
        path.append(.record(RecordMeetingModel(syncUp: syncUp, attendees: attendees)))
      }
    }
  }
}

struct AppView: View {
  @Bindable var model: AppModel

  var body: some View {
    NavigationStack(path: $model.path) {
      SyncUpsList(model: model.syncUpsList)
        .navigationDestination(for: AppModel.Path.self) { path in
          switch path {
          case .detail(let model):
            SyncUpDetailView(model: model)
          case .meeting(let meeting, let attendees):
            MeetingView(meeting: meeting, attendees: attendees)
          case .record(let model):
            RecordMeetingView(model: model)
          }
        }
    }
  }
}

#Preview("Happy path") {
  let _ = try! prepareDependencies { try $0.bootstrapDatabase() }
  AppView(model: AppModel())
}
