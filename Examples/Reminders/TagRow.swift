import SharingGRDB
import SwiftUI

struct TagRow: View {
  let tag: Tag
  @Dependency(\.defaultDatabase) var database
  var body: some View {
    HStack {
      Image(systemName: "number.circle.fill")
        .font(.largeTitle)
        .foregroundStyle(.gray)
        .background(
          Color.white.clipShape(Circle()).padding(4)
        )
      Text(tag.title)
      Spacer()
    }
    .swipeActions {
      Button {
        withErrorReporting {
          try database.write { db in
            try Tag.delete(tag)
              .execute(db)
          }
        }
      } label: {
        Image(systemName: "trash")
      }
      .tint(.red)
    }
  }
}

#Preview {
  NavigationStack {
    List {
      TagRow(tag: Tag(id: UUID(1), title: "optional"))
    }
  }
}
