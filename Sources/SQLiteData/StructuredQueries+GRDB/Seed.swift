import Dependencies
import StructuredQueriesCore

extension Database {
  /// Seeds a database with the given values.
  ///
  /// This function is useful for seeding a database's initial state, especially for previews and
  /// tests. You can list out a bunch of table records and drafts and they will be inserted into the
  /// database:
  ///
  /// ```swift
  /// try db.seed {
  ///   SyncUp(id: 1, seconds: 60, theme: .appOrange, title: "Design")
  ///   SyncUp(id: 2, seconds: 60 * 10, theme: .periwinkle, title: "Engineering")
  ///   SyncUp(id: 3, seconds: 60 * 30, theme: .poppy, title: "Product")
  ///
  ///   for name in ["Blob", "Blob Jr", "Blob Sr", "Blob Esq", "Blob III", "Blob I"] {
  ///     Attendee.Draft(name: name, syncUpID: 1)
  ///   }
  ///   for name in ["Blob", "Blob Jr"] {
  ///     Attendee.Draft(name: name, syncUpID: 2)
  ///   }
  ///   for name in ["Blob Sr", "Blob Jr"] {
  ///     Attendee.Draft(name: name, syncUpID: 3)
  ///   }
  /// }
  /// // INSERT INTO "syncUps"
  /// //   ("id", "seconds", "theme", "title")
  /// // VALUES
  /// //   (1, 60, 'appOrange', 'Design'),
  /// //   (2, 600, 'periwinkle', 'Engineering'),
  /// //   (3, 1800, 'poppy', 'Product');
  /// // INSERT INTO "attendees"
  /// //   ("id", "name", "syncUpID")
  /// // VALUES
  /// //   (NULL, 'Blob', 1),
  /// //   (NULL, 'Blob Jr', 1),
  /// //   (NULL, 'Blob Sr', 1),
  /// //   (NULL, 'Blob Esq', 1),
  /// //   (NULL, 'Blob III', 1),
  /// //   (NULL, 'Blob I', 1),
  /// //   (NULL, 'Blob', 2),
  /// //   (NULL, 'Blob Jr', 2),
  /// //   (NULL, 'Blob Sr', 3),
  /// //   (NULL, 'Blob Jr', 3);
  /// ```
  ///
  /// Insertions are performed in order and in batches of consecutive records of the same table.
  ///
  /// - Parameter build: A result builder closure that inserts every built row.
  public func seed(@SeedsBuilder _ build: () -> [any StructuredQueriesCore.Table]) throws {
    for insert in Seeds(build) {
      try insert.execute(self)
    }
  }
}
