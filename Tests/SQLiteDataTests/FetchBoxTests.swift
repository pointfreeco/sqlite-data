#if canImport(SwiftUI)
  import GRDB
  import Sharing
  import Testing

  @testable import SQLiteData

  @Suite struct FetchBoxTests {
    let database: any DatabaseReader

    init() throws {
      database = try DatabaseQueue()
    }

    @Test func keyedReinitializationWithNewQueryIsAdopted() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      persisted.fetchKeyID = fetchKeyID(TestRequest(id: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 2))
      fresh.fetchKeyID = fetchKeyID(TestRequest(id: 2))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue == 2)
      #expect(persisted.fetchKeyID == fresh.fetchKeyID)
    }

    @Test func keyedReinitializationWithSameQueryIsIgnored() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      persisted.fetchKeyID = fetchKeyID(TestRequest(id: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 2))
      fresh.fetchKeyID = fetchKeyID(TestRequest(id: 1))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue == 1)
    }

    @Test func keylessReinitializationWithSameDefaultIsIgnored() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 1))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue == 1)
    }

    @Test func keylessReinitializationWithDifferentDefaultIsAdopted() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 2))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue == 2)
    }

    @Test func keylessAdoptionCarriesSeedForward() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 2))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      persisted.sharedReader = SharedReader(value: 99)
      let refresh = FetchBox(sharedReader: SharedReader(value: 2))
      persisted.reconcile(from: refresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue == 99)
    }

    @Test func keylessReinitializationAfterLocalLoadIsIgnored() {
      let persisted = FetchBox(sharedReader: SharedReader(value: [Int]()))
      persisted.sharedReader = SharedReader(value: [1, 2, 3])
      let fresh = FetchBox(sharedReader: SharedReader(value: [Int]()))
      persisted.reconcile(from: fresh, propertyName: "@FetchAll")
      #expect(persisted.sharedReader.wrappedValue == [1, 2, 3])
    }

    @Test func keylessReinitializationWithNonEquatableDefaultIsIgnored() {
      struct Opaque: Sendable {
        let n: Int
      }
      let persisted = FetchBox(sharedReader: SharedReader(value: Opaque(n: 1)))
      let fresh = FetchBox(sharedReader: SharedReader(value: Opaque(n: 2)))
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
      #expect(persisted.sharedReader.wrappedValue.n == 1)
    }

    @Test func keyedToKeylessReinitializationReportsIssue() {
      let persisted = FetchBox(sharedReader: SharedReader(value: 1))
      persisted.fetchKeyID = fetchKeyID(TestRequest(id: 1))
      let fresh = FetchBox(sharedReader: SharedReader(value: 1))
      withKnownIssue {
        persisted.reconcile(from: fresh, propertyName: "@Fetch")
      }
      #expect(persisted.sharedReader.wrappedValue == 1)
      #expect(persisted.fetchKeyID != nil)
      persisted.reconcile(from: fresh, propertyName: "@Fetch")
    }

    private func fetchKeyID(_ request: some FetchKeyRequest<Int>) -> FetchKeyID {
      FetchKey(request: request, database: database, scheduler: nil).id
    }
  }

  private struct TestRequest: FetchKeyRequest, Hashable {
    let id: Int
    func fetch(_ db: Database) throws -> Int {
      id
    }
  }
#endif
