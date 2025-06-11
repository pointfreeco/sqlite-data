import Foundation
import SharingGRDB
import SwiftUI
import Testing

@testable import Reminders

@Suite(
  .dependencies {
    $0.date.now = baseDate
    $0.defaultDatabase = try Reminders.appDatabase()
    try $0.defaultDatabase.write { try $0.seedTestData() }
  },
  .snapshots(record: .failed)
)
struct BaseTestSuite {}

extension Database {
  func seedTestData() throws {
    let baseDate = baseDate
    try seed {
      RemindersList(
        id: UUID(0),
        color: Color(red: 0x4a / 255, green: 0x99 / 255, blue: 0xef / 255),
        position: 0,
        title: "Personal"
      )
      RemindersList(
        id: UUID(1),
        color: Color(red: 0xed / 255, green: 0x89 / 255, blue: 0x35 / 255),
        position: 1,
        title: "Family"
      )
      RemindersList(
        id: UUID(2),
        color: Color(red: 0xb2 / 255, green: 0x5d / 255, blue: 0xd3 / 255),
        position: 2,
        title: "Business"
      )
      Reminder(
        id: UUID(0),
        notes: "Milk\nEggs\nApples\nOatmeal\nSpinach",
        position: 0,
        remindersListID: UUID(0),
        title: "Groceries"
      )
      Reminder(
        id: UUID(1),
        dueDate: baseDate.addingTimeInterval(-60 * 60 * 24 * 2),
        isFlagged: true,
        position: 1,
        remindersListID: UUID(0),
        title: "Haircut"
      )
      Reminder(
        id: UUID(2),
        dueDate: baseDate,
        notes: "Ask about diet",
        position: 2,
        priority: .high,
        remindersListID: UUID(0),
        title: "Doctor appointment"
      )
      Reminder(
        id: UUID(3),
        dueDate: baseDate.addingTimeInterval(-60 * 60 * 24 * 190),
        isCompleted: true,
        position: 3,
        remindersListID: UUID(0),
        title: "Take a walk"
      )
      Reminder(
        id: UUID(4),
        dueDate: baseDate,
        position: 4,
        remindersListID: UUID(0),
        title: "Buy concert tickets"
      )
      Reminder(
        id: UUID(5),
        dueDate: baseDate.addingTimeInterval(60 * 60 * 24 * 2),
        isFlagged: true,
        position: 5,
        priority: .high,
        remindersListID: UUID(1),
        title: "Pick up kids from school"
      )
      Reminder(
        id: UUID(6),
        dueDate: baseDate.addingTimeInterval(-60 * 60 * 24 * 2),
        isCompleted: true,
        position: 6,
        priority: .low,
        remindersListID: UUID(1),
        title: "Get laundry"
      )
      Reminder(
        id: UUID(7),
        dueDate: baseDate.addingTimeInterval(60 * 60 * 24 * 4),
        isCompleted: false,
        position: 7,
        priority: .high,
        remindersListID: UUID(1),
        title: "Take out trash"
      )
      Reminder(
        id: UUID(8),
        dueDate: baseDate.addingTimeInterval(60 * 60 * 24 * 2),
        notes: """
            Status of tax return
            Expenses for next year
            Changing payroll company
            """,
        position: 8,
        remindersListID: UUID(2),
        title: "Call accountant"
      )
      Reminder(
        id: UUID(9),
        dueDate: baseDate.addingTimeInterval(-60 * 60 * 24 * 2),
        isCompleted: true,
        position: 9,
        priority: .medium,
        remindersListID: UUID(2),
        title: "Send weekly emails"
      )
      Reminder(
        id: UUID(10),
        dueDate: baseDate.addingTimeInterval(60 * 60 * 24 * 2),
        isCompleted: false,
        position: 10,
        remindersListID: UUID(2),
        title: "Prepare for WWDC"
      )
      Tag(id: UUID(0), title: "car")
      Tag(id: UUID(1), title: "kids")
      Tag(id: UUID(2), title: "someday")
      Tag(id: UUID(3), title: "optional")
      Tag(id: UUID(4), title: "social")
      Tag(id: UUID(5), title: "night")
      Tag(id: UUID(6), title: "adulting")
      ReminderTag.Draft(reminderID: UUID(0), tagID: UUID(2))
      ReminderTag.Draft(reminderID: UUID(0), tagID: UUID(3))
      ReminderTag.Draft(reminderID: UUID(0), tagID: UUID(6))
      ReminderTag.Draft(reminderID: UUID(1), tagID: UUID(2))
      ReminderTag.Draft(reminderID: UUID(1), tagID: UUID(3))
      ReminderTag.Draft(reminderID: UUID(2), tagID: UUID(6))
      ReminderTag.Draft(reminderID: UUID(3), tagID: UUID(0))
      ReminderTag.Draft(reminderID: UUID(3), tagID: UUID(1))
      ReminderTag.Draft(reminderID: UUID(4), tagID: UUID(4))
      ReminderTag.Draft(reminderID: UUID(3), tagID: UUID(4))
      ReminderTag.Draft(reminderID: UUID(10), tagID: UUID(4))
      ReminderTag.Draft(reminderID: UUID(4), tagID: UUID(5))
    }
  }
}

private let baseDate = Date(timeIntervalSince1970: 1234567890)
