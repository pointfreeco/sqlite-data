import Foundation

extension Date {
  @usableFromInline
  var iso8601String: String {
    let nextUpDate = Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.nextUp)
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
      return
        nextUpDate
        .formatted(
          .iso8601.currentTimestamp(includingFractionalSeconds: true)
        )
    } else {
      return DateFormatter.iso8601(includingFractionalSeconds: true)
        .string(from: nextUpDate)
    }
  }

  @usableFromInline
  init(iso8601String: String) throws {
    if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
      do {
        try self.init(
          iso8601String.queryOutput,
          strategy: .iso8601.currentTimestamp(includingFractionalSeconds: true)
        )
      } catch {
        try self.init(
          iso8601String.queryOutput,
          strategy: .iso8601.currentTimestamp(includingFractionalSeconds: false)
        )
      }
    } else {
      guard
        let date = DateFormatter.iso8601(includingFractionalSeconds: true).date(from: iso8601String)
          ?? DateFormatter.iso8601(includingFractionalSeconds: false).date(from: iso8601String)
      else {
        struct InvalidDate: Error { let string: String }
        throw InvalidDate(string: iso8601String)
      }
      self = date
    }
  }
}

extension DateFormatter {
  fileprivate static func iso8601(includingFractionalSeconds: Bool) -> DateFormatter {
    includingFractionalSeconds ? iso8601Fractional : iso8601Whole
  }

  fileprivate static let iso8601Fractional: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()

  fileprivate static let iso8601Whole: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
  }()
}

@available(iOS 15, macOS 12, tvOS 15, watchOS 8, *)
extension Date.ISO8601FormatStyle {
  fileprivate func currentTimestamp(includingFractionalSeconds: Bool) -> Self {
    year().month().day()
      .dateTimeSeparator(.space)
      .time(includingFractionalSeconds: includingFractionalSeconds)
  }
}
