import Dependencies
import Foundation
import SQLiteData
import SwiftUI

@testable import Reminders

extension DatabaseWriter {
  func seedTestData() throws {
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid
    try write { db in
      var remindersListIDs: [UUID] = []
      for _ in 0...2 {
        remindersListIDs.append(uuid())
      }
      var reminderIDs: [UUID] = []
      for _ in 0...10 {
        reminderIDs.append(uuid())
      }
      try db.seed {
        RemindersList(
          id: remindersListIDs[0],
          color: .personal,
          title: "Personal"
        )
        RemindersList(
          id: remindersListIDs[1],
          color: .family,
          title: "Family"
        )
        RemindersList(
          id: remindersListIDs[2],
          color: .business,
          title: "Business"
        )
        Reminder(
          id: reminderIDs[0],
          notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
          remindersListID: remindersListIDs[0],
          title: "Groceries"
        )
        Reminder(
          id: reminderIDs[1],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          isFlagged: true,
          remindersListID: remindersListIDs[0],
          title: "Haircut"
        )
        Reminder(
          id: reminderIDs[2],
          dueDate: now,
          notes: "Ask about diet",
          priority: .high,
          remindersListID: remindersListIDs[0],
          title: "Doctor appointment"
        )
        Reminder(
          id: reminderIDs[3],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 190),
          remindersListID: remindersListIDs[0],
          status: .completed,
          title: "Take a walk"
        )
        Reminder(
          id: reminderIDs[4],
          dueDate: now,
          remindersListID: remindersListIDs[0],
          title: "Buy concert tickets"
        )
        Reminder(
          id: reminderIDs[5],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          isFlagged: true,
          priority: .high,
          remindersListID: remindersListIDs[1],
          title: "Pick up kids from school"
        )
        Reminder(
          id: reminderIDs[6],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          priority: .low,
          remindersListID: remindersListIDs[1],
          status: .completed,
          title: "Get laundry"
        )
        Reminder(
          id: reminderIDs[7],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 4),
          priority: .high,
          remindersListID: remindersListIDs[1],
          status: .incomplete,
          title: "Take out trash"
        )
        Reminder(
          id: reminderIDs[8],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
          remindersListID: remindersListIDs[2],
          title: "Call accountant"
        )
        Reminder(
          id: reminderIDs[9],
          dueDate: now.addingTimeInterval(-60 * 60 * 24 * 2),
          priority: .medium,
          remindersListID: remindersListIDs[2],
          status: .completed,
          title: "Send weekly emails"
        )
        Reminder(
          id: reminderIDs[10],
          dueDate: now.addingTimeInterval(60 * 60 * 24 * 2),
          remindersListID: remindersListIDs[2],
          status: .incomplete,
          title: "Prepare for WWDC"
        )
        let tagIDs = ["car", "kids", "someday", "optional", "social", "night", "adulting"]
        for tagID in tagIDs {
          Tag(title: tagID)
        }
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[2])
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[3])
        ReminderTag.Draft(reminderID: reminderIDs[0], tagID: tagIDs[6])
        ReminderTag.Draft(reminderID: reminderIDs[1], tagID: tagIDs[2])
        ReminderTag.Draft(reminderID: reminderIDs[1], tagID: tagIDs[3])
        ReminderTag.Draft(reminderID: reminderIDs[2], tagID: tagIDs[6])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[0])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[1])
        ReminderTag.Draft(reminderID: reminderIDs[4], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[3], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[10], tagID: tagIDs[4])
        ReminderTag.Draft(reminderID: reminderIDs[4], tagID: tagIDs[5])
      }
    }
  }
}
