# Examples

This directory holds many case studies and applications to demonstrate solving various problems 
with [SQLiteData](https://github.com/pointfreeco/sqlite-data). Open the 
`Examples.xcodeproj` to see all example projects in a single 
project. To work on each example app individually, select its scheme in Xcode.

* **Case Studies**
  <br> Demonstrates how to solve some common application problems in an isolated environment, in
  both SwiftUI and UIKit. Things like animations, dynamic queries, database transactions, and more.

* **CloudKitDemo**
  <br> A simplified demo that shows how to synchronize a SQLite database to CloudKit and how to
  share records with other iCloud users. See our dedicated articles on [CloudKit Synchronization]
  and [CloudKit Sharing] for more information. 
  
  [CloudKit Synchronization]: https://swiftpackageindex.com/pointfreeco/sqlite-data/main/documentation/sqlitedata/cloudkit
  [CloudKit Sharing]: https://swiftpackageindex.com/pointfreeco/sqlite-data/main/documentation/sqlitedata/cloudkitsharing

* **Reminders**
  <br> A rebuild of Apple's [Reminders][reminders-app-store] app that uses a SQLite database to
  model the reminders, lists and tags. It features many advanced queries, such as searching, stats
  aggregation, and multi-table joins. It also features CloudKit synchronization and sharing.

* **SyncUps**
  <br> This application is a faithful reconstruction of one of Apple's more interesting sample
  projects, called [Scrumdinger][scrumdinger], and uses SQLite to persist the data for meetings.
  We have also added CloudKit synchronization so that all changes are automatically made available
  on all of the user's devices.

[scrumdinger]: https://developer.apple.com/tutorials/app-dev-training/getting-started-with-scrumdinger
[reminders-app-store]: https://apps.apple.com/us/app/reminders/id1108187841
