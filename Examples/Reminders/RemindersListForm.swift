import IssueReporting
import PhotosUI
import SQLiteData
import SwiftUI

struct RemindersListForm: View {
  @Dependency(\.defaultDatabase) private var database

  @State var remindersList: RemindersList.Draft
  @State var coverImageData: Data?
  @State var photosPickerItem: PhotosPickerItem?
  @State private var isPhotoPickerPresented = false
  @Environment(\.dismiss) var dismiss

  init(remindersList: RemindersList.Draft) {
    self.remindersList = remindersList
  }

  var body: some View {
    Form {
      Section {
        VStack {
          TextField("List Name", text: $remindersList.title)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(remindersList.color)
            .multilineTextAlignment(.center)
            .padding()
            .textFieldStyle(.plain)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(.buttonBorder)
      }
      ColorPicker("Color", selection: $remindersList.color)
      ZStack(alignment: .topTrailing) {
        ZStack {
          if let coverImageData,
            let uiImage = UIImage(data: coverImageData)
          {
            Image(uiImage: uiImage)
              .resizable()
              .scaledToFill()
              .frame(height: 150)
              .clipped()
              .cornerRadius(10)
          } else {
            Rectangle()
              .fill(Color.secondary.opacity(0.1))
              .frame(height: 150)
              .cornerRadius(10)
          }

          Button("Select Cover Image") {
            isPhotoPickerPresented = true
          }
          .padding()
          .background(.ultraThinMaterial)
          .clipShape(.capsule)
        }

        if coverImageData != nil {
          Button {
            coverImageData = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.red)
              .background(Color.white)
              .clipShape(Circle())
          }
          .padding(8)
        }
      }
      .buttonStyle(.plain)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem {
        Button("Save") {
          Task { [remindersList, coverImageData] in
            await withErrorReporting {
              try await database.write { db in
                let remindersListID =
                try RemindersList
                  .upsert { remindersList }
                  .returning(\.id)
                  .fetchOne(db)
                guard let remindersListID
                else {
                  reportIssue("No 'remindersListID'")
                  return
                }
                try RemindersListAsset.upsert {
                  RemindersListAsset.Draft(
                    remindersListID: remindersListID,
                    coverImage: coverImageData
                  )
                }
                .execute(db)
              }
            }
          }
          dismiss()
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
    .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photosPickerItem)
    .onChange(of: photosPickerItem) {
      Task {
        await withErrorReporting {
          if let photosPickerItem {
            coverImageData = try await photosPickerItem.loadTransferable(type: Data.self)
              .flatMap { resizedAndOptimizedImageData(from: $0) }
            self.photosPickerItem = nil
          }
        }
      }
    }
    .task {
      guard let remindersListID = remindersList.id
      else { return }
      do {
        coverImageData = try await database.read { db in
          try RemindersListAsset
            .where { $0.remindersListID.eq(remindersListID) }
            .select(\.coverImage)
            .fetchOne(db) ?? nil
        }
      } catch is CancellationError {
      } catch {
        reportIssue(error)
      }
    }
  }
}

func resizedAndOptimizedImageData(from data: Data, maxWidth: CGFloat = 1000) -> Data? {
  guard let image = UIImage(data: data) else { return nil }

  let originalSize = image.size
  let scaleFactor = min(1, maxWidth / originalSize.width)
  let newSize = CGSize(
    width: originalSize.width * scaleFactor,
    height: originalSize.height * scaleFactor
  )

  UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
  image.draw(in: CGRect(origin: .zero, size: newSize))
  let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
  UIGraphicsEndImageContext()

  return resizedImage?.jpegData(compressionQuality: 0.8)
}

struct RemindersListFormPreviews: PreviewProvider {
  static var previews: some View {
    let _ = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
    }
    NavigationStack {
      RemindersListForm(remindersList: RemindersList.Draft())
        .navigationTitle("New List")
    }
  }
}
