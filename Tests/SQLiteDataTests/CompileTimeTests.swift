import SQLiteData

private final class Model {
  @FetchAll var titles: [String]

  init() {
    _titles = FetchAll(Reminder.select(\.title))
  }
}
