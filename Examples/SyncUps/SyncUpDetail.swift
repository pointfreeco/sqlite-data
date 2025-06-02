import SharingGRDB
import SwiftUI
import SwiftUINavigation

@MainActor
@Observable
final class SyncUpDetailModel: HashableObject {
  var destination: Destination?
  var isDismissed = false
  @ObservationIgnored @FetchAll var attendees: [Attendee]
  @ObservationIgnored @FetchAll var meetings: [Meeting]
  @ObservationIgnored @FetchOne var syncUp: SyncUp

  var onMeetingStarted: (SyncUp, [Attendee]) -> Void = unimplemented("onMeetingStarted")

  @ObservationIgnored @Dependency(\.continuousClock) var clock
  @ObservationIgnored @Dependency(\.defaultDatabase) var database
  @ObservationIgnored @Dependency(\.openSettings) var openSettings
  @ObservationIgnored @Dependency(\.speechClient.authorizationStatus) var authorizationStatus
  @ObservationIgnored @Dependency(\.uuid) var uuid

  @CasePathable
  enum Destination {
    case alert(AlertState<AlertAction>)
    case edit(SyncUpFormModel)
  }
  enum AlertAction {
    case confirmDeletion
    case continueWithoutRecording
    case openSettings
  }

  init(
    destination: Destination? = nil,
    syncUp: SyncUp
  ) {
    self.destination = destination
    _attendees = FetchAll(Attendee.where { $0.syncUpID.eq(syncUp.id) })
    _meetings = FetchAll(Meeting.where { $0.syncUpID.eq(syncUp.id) })
    _syncUp = FetchOne(wrappedValue: syncUp, SyncUp.find(syncUp.id))
  }

  func deleteMeetings(atOffsets indices: IndexSet) {
    withErrorReporting {
      try database.write { db in
        let ids = indices.map { meetings[$0].id }
        try Meeting.where { ids.contains($0.id) }.delete().execute(db)
      }
    }
  }

  func deleteButtonTapped() {
    destination = .alert(.deleteSyncUp)
  }

  func alertButtonTapped(_ action: AlertAction?) async {
    switch action {
    case .confirmDeletion:
      isDismissed = true
      try? await clock.sleep(for: .seconds(0.4))
      await withErrorReporting {
        try await database.write { [syncUp] db in
          try SyncUp.delete(syncUp).execute(db)
        }
      }

    case .continueWithoutRecording:
      onMeetingStarted(syncUp, attendees)

    case .openSettings:
      await openSettings()

    case nil:
      break
    }
  }

  func editButtonTapped() {
    destination = .edit(
      withDependencies(from: self) {
        SyncUpFormModel(syncUp: SyncUp.Draft(syncUp))
      }
    )
  }

  func startMeetingButtonTapped() {
    switch authorizationStatus() {
    case .notDetermined, .authorized:
      onMeetingStarted(syncUp, attendees)

    case .denied:
      destination = .alert(.speechRecognitionDenied)

    case .restricted:
      destination = .alert(.speechRecognitionRestricted)

    @unknown default:
      break
    }
  }
}

struct SyncUpDetailView: View {
  @Environment(\.dismiss) var dismiss
  @State var model: SyncUpDetailModel

  var body: some View {
    List {
      Section {
        Button {
          model.startMeetingButtonTapped()
        } label: {
          Label("Start Meeting", systemImage: "timer")
            .font(.headline)
            .foregroundColor(.accentColor)
        }
        HStack {
          Label("Length", systemImage: "clock")
          Spacer()
          Text(model.syncUp.seconds.duration.formatted(.units()))
        }

        HStack {
          Label("Theme", systemImage: "paintpalette")
          Spacer()
          Text(model.syncUp.theme.name)
            .padding(4)
            .foregroundColor(model.syncUp.theme.accentColor)
            .background(model.syncUp.theme.mainColor)
            .cornerRadius(4)
        }
      } header: {
        Text("Sync-up Info")
      }

      if !model.meetings.isEmpty {
        Section {
          ForEach(model.meetings) { meeting in
            NavigationLink(
              value: AppModel.Path.meeting(meeting, attendees: model.attendees)
            ) {
              HStack {
                Image(systemName: "calendar")
                Text(meeting.date, style: .date)
                Text(meeting.date, style: .time)
              }
            }
          }
          .onDelete { indices in
            model.deleteMeetings(atOffsets: indices)
          }
        } header: {
          Text("Past meetings")
        }
      }

      Section {
        ForEach(model.attendees) { attendee in
          Label(attendee.name, systemImage: "person")
        }
      } header: {
        Text("Attendees")
      }

      Section {
        Button("Delete") {
          model.deleteButtonTapped()
        }
        .foregroundColor(.red)
        .frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(model.syncUp.title)
    .toolbar {
      Button("Edit") {
        model.editButtonTapped()
      }
    }
    .alert($model.destination.alert) { action in
      await model.alertButtonTapped(action)
    }
    .sheet(item: $model.destination.edit) { editModel in
      NavigationStack {
        SyncUpFormView(model: editModel)
          .navigationTitle(model.syncUp.title)
      }
    }
    .onChange(of: model.isDismissed) {
      dismiss()
    }
  }
}

extension AlertState where Action == SyncUpDetailModel.AlertAction {
  static let deleteSyncUp = Self {
    TextState("Delete?")
  } actions: {
    ButtonState(role: .destructive, action: .confirmDeletion) {
      TextState("Yes")
    }
    ButtonState(role: .cancel) {
      TextState("Nevermind")
    }
  } message: {
    TextState("Are you sure you want to delete this sync-up?")
  }

  static let speechRecognitionDenied = Self {
    TextState("Speech recognition denied")
  } actions: {
    ButtonState(action: .continueWithoutRecording) {
      TextState("Continue without recording")
    }
    ButtonState(action: .openSettings) {
      TextState("Open settings")
    }
    ButtonState(role: .cancel) {
      TextState("Cancel")
    }
  } message: {
    TextState(
      """
      You previously denied speech recognition and so your meeting meeting will not be \
      recorded. You can enable speech recognition in settings, or you can continue without \
      recording.
      """
    )
  }

  static let speechRecognitionRestricted = Self {
    TextState("Speech recognition restricted")
  } actions: {
    ButtonState(action: .continueWithoutRecording) {
      TextState("Continue without recording")
    }
    ButtonState(role: .cancel) {
      TextState("Cancel")
    }
  } message: {
    TextState(
      """
      Your device does not support speech recognition and so your meeting will not be recorded.
      """
    )
  }
}

struct MeetingView: View {
  let meeting: Meeting
  let attendees: [Attendee]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading) {
        Divider()
          .padding(.bottom)
        Text("Attendees")
          .font(.headline)
        ForEach(attendees, id: \.id) { attendee in
          Text(attendee.name)
        }
        Text("Transcript")
          .font(.headline)
          .padding(.top)
        Text(meeting.transcript)
      }
    }
    .navigationTitle(Text(meeting.date, style: .date))
    .padding()
  }
}

#Preview {
  let syncUp = try! prepareDependencies {
    $0.defaultDatabase = try SyncUps.appDatabase()
    return try $0.defaultDatabase.read { db in
      try SyncUp.limit(1).fetchOne(db)!
    }
  }
  NavigationStack {
    SyncUpDetailView(model: SyncUpDetailModel(syncUp: syncUp))
  }
}
