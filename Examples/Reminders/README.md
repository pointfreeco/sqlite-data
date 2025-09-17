# Reminders

A rebuild of many of the features from Apple's [Reminders app][reminders-app-store]. It stores data
for reminders, lists and tags in a SQLite database, and uses foreign keys to express one-to-many
and many-to-many relationships between the entities.

It also demonstrates how to perform very advanced queries in SQLite that would be impossible in
SwiftData, such as using SQLite's `group_concat` function to fetch all reminders along with a 
comma-separated list of all of its tags. SQLite is an incredibly powerful language, and one should
not embrace abstractions that keep you from querying SQLite directly as SwiftData does.

[reminders-app-store]: https://apps.apple.com/us/app/reminders/id1108187841
[tags-concat]: https://github.com/pointfreeco/sqlite-data/blob/0391201992241f62e7bd10c8d1ece63b078c16ad/Examples/Reminders/RemindersListDetail.swift#L146-L147
