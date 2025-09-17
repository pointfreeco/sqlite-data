import SQLiteData
import SwiftUI
import SwiftUINavigation

@Observable
final class SyncUpFormModel: Identifiable {
  var attendees: [AttendeeDraft] = []
  var focus: Field?
  var isDismissed = false
  var syncUp: SyncUp.Draft

  @ObservationIgnored @Dependency(\.defaultDatabase) var database
  @ObservationIgnored @Dependency(\.uuid) var uuid

  struct AttendeeDraft: Identifiable {
    let id: UUID
    var name = ""
  }

  enum Field: Hashable {
    case attendee(AttendeeDraft.ID)
    case title
  }

  init(
    syncUp: SyncUp.Draft,
    focus: Field? = .title
  ) {
    self.syncUp = syncUp
    self.focus = focus
    defer {
      if attendees.isEmpty {
        self.attendees.append(AttendeeDraft(id: uuid()))
      }
    }
    guard let syncUpID = syncUp.id
    else { return }

    withErrorReporting {
      self.attendees = try database.read { db in
        try Attendee.all
          .where { $0.syncUpID.eq(syncUpID) }
          .fetchAll(db)
          .map { (attendee: Attendee) in AttendeeDraft(id: uuid(), name: attendee.name) }
      }
    }
  }

  func deleteAttendees(atOffsets indices: IndexSet) {
    attendees.remove(atOffsets: indices)
    if attendees.isEmpty {
      attendees.append(AttendeeDraft(id: uuid()))
    }
    guard let firstIndex = indices.first
    else { return }
    let index = min(firstIndex, attendees.count - 1)
    focus = .attendee(attendees[index].id)
  }

  func addAttendeeButtonTapped() {
    let attendee = AttendeeDraft(id: uuid())
    attendees.append(attendee)
    focus = .attendee(attendee.id)
  }

  func cancelButtonTapped() {
    isDismissed = true
  }

  func saveButtonTapped() {
    attendees.removeAll { attendee in
      attendee.name.allSatisfy(\.isWhitespace)
    }
    if attendees.isEmpty {
      attendees.append(SyncUpFormModel.AttendeeDraft(id: uuid()))
    }
    withErrorReporting {
      try database.write { db in
        let syncUpID = try SyncUp.upsert { syncUp }.returning(\.id).fetchOne(db)!
        try Attendee.where { $0.syncUpID == syncUpID }.delete().execute(db)
        try Attendee.insert {
          for attendee in attendees {
            Attendee.Draft(name: attendee.name, syncUpID: syncUpID)
          }
        }
        .execute(db)
      }
    }
    isDismissed = true
  }
}

struct SyncUpFormView: View {
  @Environment(\.dismiss) var dismiss
  @FocusState var focus: SyncUpFormModel.Field?
  @Bindable var model: SyncUpFormModel

  var body: some View {
    Form {
      Section {
        TextField("Title", text: $model.syncUp.title)
          .focused($focus, equals: .title)
        HStack {
          Slider(value: $model.syncUp.seconds.toDouble, in: 5...30, step: 1) {
            Text("Length")
          }
          Spacer()
          Text(model.syncUp.seconds.duration.formatted(.units()))
        }
        ThemePicker(selection: $model.syncUp.theme)
      } header: {
        Text("Sync-up Info")
      }
      Section {
        ForEach($model.attendees) { $attendee in
          TextField("Name", text: $attendee.name)
            .focused($focus, equals: .attendee(attendee.id))
        }
        .onDelete { indices in
          model.deleteAttendees(atOffsets: indices)
        }

        Button("New attendee") {
          model.addAttendeeButtonTapped()
        }
      } header: {
        Text("Attendees")
      }
    }
    .bind($model.focus, to: $focus)
    .onChange(of: model.isDismissed) {
      dismiss()
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          model.cancelButtonTapped()
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          model.saveButtonTapped()
        }
      }
    }
  }
}

extension Int {
  fileprivate var toDouble: Double {
    get { Double(self) }
    set { self = Int(newValue) }
  }
}

struct ThemePicker: View {
  @Binding var selection: Theme

  var body: some View {
    Picker("Theme", selection: $selection) {
      ForEach(Theme.allCases) { theme in
        ZStack {
          RoundedRectangle(cornerRadius: 4)
            .fill(theme.mainColor)
          Label(theme.name, systemImage: "paintpalette")
            .padding(4)
        }
        .foregroundColor(theme.accentColor)
        .fixedSize(horizontal: false, vertical: true)
        .tag(theme)
      }
    }
  }
}

struct SyncUpFormPreviews: PreviewProvider {
  static var previews: some View {
    NavigationStack {
      SyncUpFormView(
        model: SyncUpFormModel(
          syncUp: SyncUp.Draft()
        )
      )
    }
  }
}
