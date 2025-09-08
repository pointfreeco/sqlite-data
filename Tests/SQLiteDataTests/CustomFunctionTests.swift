//import Foundation
//import SQLiteData
//import Testing
//
//@Suite struct CustomFunctionsTests {
//  @DatabaseFunction func customDate() -> Date {
//    Date(timeIntervalSinceReferenceDate: 0)
//  }
//
//  @Test func basics() throws {
//    var configuration = Configuration()
//    configuration.prepareDatabase { db in
//      db.add(function: $customDate)
//    }
//    let database = try DatabaseQueue(configuration: configuration)
//    let date = try database.read { db in
//      try Values($customDate())
//        .fetchOne(db)
//    }
//    #expect(date?.timeIntervalSinceReferenceDate == 0)
//
//    try database.write { db in
//      db.remove(function: $customDate)
//    }
//    #expect(throws: (any Error).self) {
//      try database.read { db in
//        _ = try Values($customDate()).fetchOne(db)
//      }
//    }
//  }
//}
