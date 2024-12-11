import CasePaths
import SharingGRDB
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
  @Dependency(\.continuousClock) var clock
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
      case let .detail(detailModel):
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
          case let .detail(model):
            SyncUpDetailView(model: model)
          case let .meeting(meeting, attendees: attendees):
            MeetingView(meeting: meeting, attendees: attendees)
          case let .record(model):
            RecordMeetingView(model: model)
          }
        }
    }
  }
}

#Preview("Happy path") {
  let _ = prepareDependencies {
    $0.defaultDatabase = .appDatabase
  }
  AppView(model: AppModel())
}
