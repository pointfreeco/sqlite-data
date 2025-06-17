import DependenciesTestSupport
import InlineSnapshotTesting
import SnapshotTestingCustomDump
import Testing

@testable import Reminders

extension BaseTestSuite {
  @MainActor
  struct RemindersListsTests {
    @Test func basics() async throws {
      let model = RemindersListsModel()
      try await model.$remindersLists.load()
      try await model.$stats.load()
      try await model.$tags.load()

      assertInlineSnapshot(of: model.remindersLists, as: .customDump) {
        """
        [
          [0]: RemindersListsModel.ReminderListState(
            remindersCount: 4,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000000),
              color: Color(
                provider: ColorBox(
                  base: ResolvedColorProvider(
                    color: Color.Resolved(
                      linearRed: 0.06662594,
                      linearGreen: 0.31854683,
                      linearBlue: 0.8631573,
                      opacity: 1.0
                    )
                  )
                )
              ),
              position: 1,
              title: "Personal"
            )
          ),
          [1]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000001),
              color: Color(
                provider: #1 ColorBox(
                  base: ResolvedColorProvider(
                    color: Color.Resolved(
                      linearRed: 0.8468733,
                      linearGreen: 0.25015837,
                      linearBlue: 0.0343398,
                      opacity: 1.0
                    )
                  )
                )
              ),
              position: 2,
              title: "Family"
            )
          ),
          [2]: RemindersListsModel.ReminderListState(
            remindersCount: 2,
            remindersList: RemindersList(
              id: UUID(00000000-0000-0000-0000-000000000002),
              color: Color(
                provider: #2 ColorBox(
                  base: ResolvedColorProvider(
                    color: Color.Resolved(
                      linearRed: 0.44520125,
                      linearGreen: 0.10946172,
                      linearBlue: 0.6514057,
                      opacity: 1.0
                    )
                  )
                )
              ),
              position: 3,
              title: "Business"
            )
          )
        ]
        """
      }
      assertInlineSnapshot(of: model.stats, as: .customDump) {
        """
        RemindersListsModel.Stats(
          allCount: 8,
          flaggedCount: 2,
          scheduledCount: 7,
          todayCount: 2
        )
        """
      }
      assertInlineSnapshot(of: model.tags, as: .customDump) {
        """
        [
          [0]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000006),
            title: "adulting"
          ),
          [1]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000000),
            title: "car"
          ),
          [2]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000001),
            title: "kids"
          ),
          [3]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000005),
            title: "night"
          ),
          [4]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000003),
            title: "optional"
          ),
          [5]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000004),
            title: "social"
          ),
          [6]: Tag(
            id: UUID(00000000-0000-0000-0000-000000000002),
            title: "someday"
          )
        ]
        """
      }
    }

    @Test func move() async throws {
      let model = RemindersListsModel()
      try await model.$remindersLists.load()
      assertInlineSnapshot(of: model.remindersLists.map(\.remindersList.title), as: .customDump) {
        """
        [
          [0]: "Personal",
          [1]: "Family",
          [2]: "Business"
        ]
        """
      }

      model.move(from: [2], to: 0)
      try await model.$remindersLists.load()
      assertInlineSnapshot(of: model.remindersLists.map(\.remindersList.title), as: .customDump) {
        """
        [
          [0]: "Business",
          [1]: "Personal",
          [2]: "Family"
        ]
        """
      }
    }
  }
}
