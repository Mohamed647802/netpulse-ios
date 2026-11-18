import Foundation

enum ByteFormatterUtil {
    private static let kb: Double = 1024.0
    private static let mb: Double = 1024.0 * 1024.0
    private static let gb: Double = 1024.0 * 1024.0 * 1024.0
    private static let tb: Double = 1024.0 * 1024.0 * 1024.0 * 1024.0

    static let arabicLocale = Locale(identifier: "ar@numbers=latn")

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let arabicFullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ar@numbers=latn")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE، d MMMM yyyy"
        return formatter
    }()

    private static let arabicShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ar@numbers=latn")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private static let arabicDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ar@numbers=latn")
        formatter.timeZone = .current
        formatter.dateFormat = "d MMM yyyy • h:mm a"
        return formatter
    }()

    private static let arabicMonthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ar@numbers=latn")
        formatter.timeZone = .current
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static func formatBytes(_ bytes: Int64, unit: DataUnitPreference = .auto, decimals: Int = 2) -> String {
        let safeBytes = max(0, bytes)
        let value = Double(safeBytes)

        switch unit {
        case .megabytes:
            let mbs = value / mb
            return String(format: "%.\(decimals)f MB", mbs)
        case .gigabytes:
            let gbs = value / gb
            return String(format: "%.\(decimals)f GB", gbs)
        case .auto:
            if value < kb {
                return "\(safeBytes) B"
            } else if value < mb {
                return String(format: "%.1f KB", value / kb)
            } else if value < gb {
                return String(format: "%.\(decimals)f MB", value / mb)
            } else if value < tb {
                return String(format: "%.\(decimals)f GB", value / gb)
            } else {
                return String(format: "%.\(decimals)f TB", value / tb)
            }
        }
    }

    static func splitValueAndUnit(_ bytes: Int64, unit: DataUnitPreference = .auto) -> (number: String, unit: String) {
        let safeBytes = max(0, bytes)
        let value = Double(safeBytes)

        switch unit {
        case .megabytes:
            return (String(format: "%.2f", value / mb), "MB")
        case .gigabytes:
            return (String(format: "%.2f", value / gb), "GB")
        case .auto:
            if value < kb {
                return ("\(safeBytes)", "B")
            } else if value < mb {
                return (String(format: "%.1f", value / kb), "KB")
            } else if value < gb {
                return (String(format: "%.2f", value / mb), "MB")
            } else {
                return (String(format: "%.2f", value / gb), "GB")
            }
        }
    }

    static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let safe = max(0, bytesPerSecond)
        if safe < kb {
            return String(format: "%.0f B/s", safe)
        } else if safe < mb {
            return String(format: "%.1f KB/s", safe / kb)
        } else {
            return String(format: "%.2f MB/s", safe / mb)
        }
    }

    static func todayDateKey(for date: Date = Date()) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func date(fromKey key: String) -> Date {
        dateKeyFormatter.date(from: key) ?? Date()
    }

    static func arabicFullDate(from date: Date) -> String {
        arabicFullDateFormatter.string(from: date)
    }

    static func arabicFullDate(fromKey key: String) -> String {
        if key == todayDateKey() {
            return "اليوم • " + arabicShortDateFormatter.string(from: date(fromKey: key))
        }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()),
           key == todayDateKey(for: yesterday) {
            return "أمس • " + arabicShortDateFormatter.string(from: yesterday)
        }
        return arabicFullDateFormatter.string(from: date(fromKey: key))
    }

    static func arabicShortDate(from date: Date) -> String {
        arabicShortDateFormatter.string(from: date)
    }

    static func arabicDateTime(from timestamp: TimeInterval) -> String {
        arabicDateTimeFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    static func arabicMonthYear(from date: Date) -> String {
        arabicMonthYearFormatter.string(from: date)
    }

    static func dateKeysBetween(start: Date, end: Date) -> Set<String> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let d1 = calendar.startOfDay(for: min(start, end))
        let d2 = calendar.startOfDay(for: max(start, end))

        var result = Set<String>()
        var cursor = d1
        while cursor <= d2 {
            result.insert(todayDateKey(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

// MARK: - حاسبة دورات تجديد الباقات الشهرية
enum BillingCycleCalculator {
    static func currentCycle(renewalDay: Int, referenceDate: Date = Date()) -> (start: Date, end: Date, remainingDays: Int, cycleKey: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let clampedRenewal = min(max(renewalDay, 1), 31)
        let todayStart = calendar.startOfDay(for: referenceDate)
        let comps = calendar.dateComponents([.year, .month, .day], from: todayStart)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let day = comps.day ?? 1

        let renewalDateThisMonth = clampedDate(year: year, month: month, desiredDay: clampedRenewal, calendar: calendar)

        let cycleStart: Date
        let nextRenewalStart: Date

        if day >= calendar.component(.day, from: renewalDateThisMonth) {
            cycleStart = renewalDateThisMonth
            let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: makeFirstOfMonth(year: year, month: month, calendar: calendar)) ?? todayStart
            let nextComps = calendar.dateComponents([.year, .month], from: nextMonthDate)
            nextRenewalStart = clampedDate(year: nextComps.year ?? year, month: nextComps.month ?? month, desiredDay: clampedRenewal, calendar: calendar)
        } else {
            nextRenewalStart = renewalDateThisMonth
            let prevMonthDate = calendar.date(byAdding: .month, value: -1, to: makeFirstOfMonth(year: year, month: month, calendar: calendar)) ?? todayStart
            let prevComps = calendar.dateComponents([.year, .month], from: prevMonthDate)
            cycleStart = clampedDate(year: prevComps.year ?? year, month: prevComps.month ?? month, desiredDay: clampedRenewal, calendar: calendar)
        }

        let cycleEnd = calendar.date(byAdding: .day, value: -1, to: nextRenewalStart) ?? todayStart
        let diff = calendar.dateComponents([.day], from: todayStart, to: nextRenewalStart).day ?? 1
        let remainingDays = max(1, diff)
        let cycleKey = ByteFormatterUtil.todayDateKey(for: cycleStart)

        return (cycleStart, cycleEnd, remainingDays, cycleKey)
    }

    private static func makeFirstOfMonth(year: Int, month: Int, calendar: Calendar) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = 1
        return calendar.date(from: c) ?? Date()
    }

    private static func clampedDate(year: Int, month: Int, desiredDay: Int, calendar: Calendar) -> Date {
        let first = makeFirstOfMonth(year: year, month: month, calendar: calendar)
        let maxDay = calendar.range(of: .day, in: .month, for: first)?.count ?? 28
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = min(desiredDay, maxDay)
        return calendar.startOfDay(for: calendar.date(from: c) ?? first)
    }
}
