import Foundation

/// A single calendar occurrence supplied by the user. Parsing never writes to Calendar.
public struct CalendarSelection: Equatable {
    public var uid: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var isAllDay: Bool
    public var recurrenceID: Date?
    public var hasRecurrence: Bool

    public init(uid: String, title: String, start: Date, end: Date? = nil,
                isAllDay: Bool = false, recurrenceID: Date? = nil, hasRecurrence: Bool = false) {
        self.uid = uid
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrenceID = recurrenceID
        self.hasRecurrence = hasRecurrence
    }

    public static func parse(_ text: String, timeZone: TimeZone = .current) throws -> CalendarSelection {
        try CalendarSelectionParser.parse(text, timeZone: timeZone)
    }

    /// Unfold before UTF-8 decoding, since an external calendar can fold inside a multibyte character.
    public static func parse(_ data: Data, timeZone: TimeZone = .current) throws -> CalendarSelection {
        guard data.count <= 1_048_576 else { throw CalendarSelectionError.tooLarge }
        let input = Array(data)
        var unfolded: [UInt8] = []
        unfolded.reserveCapacity(input.count)
        var index = 0
        while index < input.count {
            if index + 2 < input.count, input[index] == 13, input[index + 1] == 10,
               input[index + 2] == 32 || input[index + 2] == 9 {
                index += 3
            } else if index + 1 < input.count, input[index] == 10,
                      input[index + 1] == 32 || input[index + 1] == 9 {
                index += 2
            } else {
                unfolded.append(input[index])
                index += 1
            }
        }
        guard let text = String(bytes: unfolded, encoding: .utf8) else { throw CalendarSelectionError.malformed }
        return try parse(text, timeZone: timeZone)
    }
}

public enum CalendarSelectionError: LocalizedError, Equatable {
    case tooLarge
    case malformed
    case selectOneEvent
    case missingField(String)
    case duplicateField(String)
    case invalidDate
    case unknownTimeZone(String)
    case invalidDuration

    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "日历内容过大，请只选择一条日程。"
        case .malformed: return "无法识别这条日历内容，请重新传入一条日程。"
        case .selectOneEvent: return "请只选择一条日程后再开始计时。"
        case .missingField(let field): return "这条日程缺少\(field)，请在日历中补全后重试。"
        case .duplicateField: return "这条日程包含重复信息，无法确定要计时的事项。"
        case .invalidDate: return "这条日程的日期或结束时间无效，请在日历中检查后重试。"
        case .unknownTimeZone(let zone): return "无法识别日程时区“\(zone.prefix(100))”，请在日历中确认时区后重试。"
        case .invalidDuration: return "这条日程的时长无效，请在日历中检查后重试。"
        }
    }
}

private enum CalendarSelectionParser {
    private struct Property {
        let name: String
        let parameters: [String: String]
        let value: String
    }

    private struct ParsedDate {
        let value: Date
        let isAllDay: Bool
        let zone: TimeZone
    }

    static func parse(_ text: String, timeZone: TimeZone) throws -> CalendarSelection {
        guard text.utf8.count <= 1_048_576 else { throw CalendarSelectionError.tooLarge }
        guard !text.contains("\0") else { throw CalendarSelectionError.malformed }
        let lines = try unfoldedLines(text)
        var stack: [String] = []
        var eventCount = 0
        var rootCount = 0
        var properties: [String: Property] = [:]
        var recurring = false
        let critical: Set<String> = ["UID", "SUMMARY", "DTSTART", "DTEND", "DURATION", "RECURRENCE-ID", "RRULE"]

        for line in lines where !line.isEmpty {
            let property = try parseProperty(line)
            if property.name == "BEGIN" {
                guard property.parameters.isEmpty else { throw CalendarSelectionError.malformed }
                let component = property.value.uppercased()
                guard validToken(component) else { throw CalendarSelectionError.malformed }
                if stack.isEmpty {
                    rootCount += 1
                    guard rootCount == 1, component == "VCALENDAR" || component == "VEVENT" else {
                        throw CalendarSelectionError.malformed
                    }
                } else if component == "VCALENDAR" {
                    throw CalendarSelectionError.malformed
                }
                if component == "VEVENT" {
                    guard stack.isEmpty || stack == ["VCALENDAR"] else { throw CalendarSelectionError.malformed }
                    eventCount += 1
                    guard eventCount == 1 else { throw CalendarSelectionError.selectOneEvent }
                }
                stack.append(component)
                continue
            }
            if property.name == "END" {
                guard property.parameters.isEmpty, let current = stack.last,
                      current == property.value.uppercased() else { throw CalendarSelectionError.malformed }
                stack.removeLast()
                continue
            }
            guard !stack.isEmpty else { throw CalendarSelectionError.malformed }
            // A nested alarm can have its own SUMMARY and DTSTART. They are not event fields.
            guard stack.last == "VEVENT" else { continue }
            if critical.contains(property.name) {
                guard properties[property.name] == nil else { throw CalendarSelectionError.duplicateField(property.name) }
                properties[property.name] = property
            }
            if property.name == "RRULE" || property.name == "RDATE" {
                guard !property.value.isEmpty else { throw CalendarSelectionError.malformed }
                recurring = true
            }
        }
        guard stack.isEmpty, rootCount == 1 else { throw CalendarSelectionError.malformed }
        guard eventCount == 1 else { throw CalendarSelectionError.selectOneEvent }

        func required(_ name: String, label: String) throws -> Property {
            guard let value = properties[name], !value.value.isEmpty else { throw CalendarSelectionError.missingField(label) }
            return value
        }
        let uid = try decodeText(required("UID", label: "标识").value).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = try decodeText(required("SUMMARY", label: "标题").value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { throw CalendarSelectionError.missingField("标识") }
        guard !title.isEmpty else { throw CalendarSelectionError.missingField("标题") }
        let start = try date(required("DTSTART", label: "开始时间"), defaultZone: timeZone)
        var end: Date?
        if let endProperty = properties["DTEND"] {
            guard properties["DURATION"] == nil else { throw CalendarSelectionError.malformed }
            let parsed = try date(endProperty, defaultZone: timeZone)
            guard parsed.isAllDay == start.isAllDay else { throw CalendarSelectionError.invalidDate }
            end = parsed.value
        } else if let durationProperty = properties["DURATION"] {
            end = try durationEnd(durationProperty.value, after: start)
        }
        if let end {
            guard end.timeIntervalSinceReferenceDate.isFinite, end >= start.value else { throw CalendarSelectionError.invalidDate }
        }
        var recurrenceID: Date?
        if let property = properties["RECURRENCE-ID"] {
            let parsed = try date(property, defaultZone: timeZone)
            guard parsed.isAllDay == start.isAllDay else { throw CalendarSelectionError.invalidDate }
            recurrenceID = parsed.value
            recurring = true
        }
        return CalendarSelection(uid: uid, title: title, start: start.value, end: end,
                                 isAllDay: start.isAllDay, recurrenceID: recurrenceID, hasRecurrence: recurring)
    }

    private static func unfoldedLines(_ text: String) throws -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var result: [String] = []
        for var line in normalized.components(separatedBy: "\n") {
            if result.isEmpty, line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.first == " " || line.first == "\t" {
                guard let previous = result.last, !previous.isEmpty else { throw CalendarSelectionError.malformed }
                result[result.count - 1] += line.dropFirst()
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (65...90).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    private static func parseProperty(_ line: String) throws -> Property {
        var quoted = false
        var separator: String.Index?
        for index in line.indices {
            if line[index] == "\"" { quoted.toggle() }
            if line[index] == ":", !quoted { separator = index; break }
        }
        guard let separator, !quoted else { throw CalendarSelectionError.malformed }
        let header = line[..<separator]
        var fields: [String] = []
        var field = ""
        for character in header {
            if character == "\"" { quoted.toggle() }
            if character == ";", !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        let name = fields[0].uppercased()
        guard validToken(name), !quoted else { throw CalendarSelectionError.malformed }
        var parameters: [String: String] = [:]
        for parameter in fields.dropFirst() {
            guard let equals = parameter.firstIndex(of: "=") else { throw CalendarSelectionError.malformed }
            let key = parameter[..<equals].uppercased()
            var value = String(parameter[parameter.index(after: equals)...])
            guard validToken(key), parameters[key] == nil, !value.isEmpty else { throw CalendarSelectionError.malformed }
            if value.hasPrefix("\"") {
                guard value.hasSuffix("\""), value.count >= 2 else { throw CalendarSelectionError.malformed }
                value.removeFirst()
                value.removeLast()
            }
            guard !value.contains("\"") else { throw CalendarSelectionError.malformed }
            parameters[key] = value
        }
        return Property(name: name, parameters: parameters, value: String(line[line.index(after: separator)...]))
    }

    private static func decodeText(_ value: String) throws -> String {
        var decoded = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n", "N": decoded.append("\n")
                case "\\", ",", ";": decoded.append(character)
                default: throw CalendarSelectionError.malformed
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                decoded.append(character)
            }
        }
        guard !escaping else { throw CalendarSelectionError.malformed }
        return decoded
    }

    private static func date(_ property: Property, defaultZone: TimeZone) throws -> ParsedDate {
        let value = property.value
        let declaredType = property.parameters["VALUE"]?.uppercased()
        guard declaredType == nil || declaredType == "DATE" || declaredType == "DATE-TIME" else {
            throw CalendarSelectionError.invalidDate
        }
        let allDay = declaredType == "DATE" || (declaredType == nil && value.utf8.count == 8)
        let utc = value.hasSuffix("Z")
        let bytes = Array(value.utf8)
        let expectedCount = allDay ? 8 : (utc ? 16 : 15)
        guard bytes.count == expectedCount else { throw CalendarSelectionError.invalidDate }
        let zone: TimeZone
        if let identifier = property.parameters["TZID"] {
            guard !utc, !allDay else { throw CalendarSelectionError.invalidDate }
            guard let found = TimeZone(identifier: identifier) else { throw CalendarSelectionError.unknownTimeZone(identifier) }
            zone = found
        } else {
            zone = utc ? TimeZone(secondsFromGMT: 0)! : defaultZone
        }
        func number(_ range: Range<Int>) throws -> Int {
            guard range.allSatisfy({ (48...57).contains(bytes[$0]) }) else { throw CalendarSelectionError.invalidDate }
            return range.reduce(0) { $0 * 10 + Int(bytes[$1] - 48) }
        }
        let year = try number(0..<4), month = try number(4..<6), day = try number(6..<8)
        var hour = 0, minute = 0, second = 0
        if !allDay {
            guard bytes[8] == 84 else { throw CalendarSelectionError.invalidDate }
            hour = try number(9..<11)
            minute = try number(11..<13)
            second = try number(13..<15)
        }
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw CalendarSelectionError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let parsed = calendar.date(from: components), parsed.timeIntervalSinceReferenceDate.isFinite else {
            throw CalendarSelectionError.invalidDate
        }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        guard check.year == year, check.month == month, check.day == day,
              check.hour == hour, check.minute == minute, check.second == second else {
            throw CalendarSelectionError.invalidDate
        }
        return ParsedDate(value: parsed, isAllDay: allDay, zone: zone)
    }

    private static func durationEnd(_ value: String, after start: ParsedDate) throws -> Date {
        // RFC 5545 durations use whole weeks/days, followed by optional hours/minutes/seconds.
        let expression = try NSRegularExpression(pattern: "^\\+?P(?:(\\d+)W|(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?)$")
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range), match.range == range,
              value.last != "T" else { throw CalendarSelectionError.invalidDuration }
        var parts = [Int]()
        var hasPart = false
        for index in 1...5 {
            let range = match.range(at: index)
            if range.location == NSNotFound { parts.append(0); continue }
            hasPart = true
            guard let swiftRange = Range(range, in: value), let count = Int(value[swiftRange]), count <= 3_650_000 else {
                throw CalendarSelectionError.invalidDuration
            }
            parts.append(count)
        }
        guard hasPart, !start.isAllDay || !value.contains("T") else { throw CalendarSelectionError.invalidDuration }
        let days = parts[0] * 7 + parts[1]
        let seconds = Double(parts[2]) * 3_600 + Double(parts[3]) * 60 + Double(parts[4])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = start.zone
        guard let afterDays = calendar.date(byAdding: .day, value: days, to: start.value) else {
            throw CalendarSelectionError.invalidDuration
        }
        let end = afterDays.addingTimeInterval(seconds)
        guard end.timeIntervalSinceReferenceDate.isFinite, (1...9999).contains(calendar.component(.year, from: end)) else {
            throw CalendarSelectionError.invalidDuration
        }
        return end
    }
}
