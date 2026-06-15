//
//  Models.swift
//  smallthings, bigmoney.
//
//  User settings, persistence, and the earnings calculation engine.
//

import Foundation
import SwiftUI

// MARK: - Salary Type

enum SalaryType: String, CaseIterable, Identifiable, Codable {
    case hourly  = "시급"
    case weekly  = "주급"
    case monthly = "월급"
    case yearly  = "연봉"

    var id: String { rawValue }
}

// MARK: - Weekday

enum Weekday: Int, CaseIterable, Identifiable, Codable {
    case mon = 0, tue, wed, thu, fri, sat, sun

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .mon: "월"
        case .tue: "화"
        case .wed: "수"
        case .thu: "목"
        case .fri: "금"
        case .sat: "토"
        case .sun: "일"
        }
    }

    /// Maps `Calendar.component(.weekday)` (1 = Sun ... 7 = Sat) to our Weekday.
    static func from(calendarWeekday: Int) -> Weekday {
        // 1(Sun) -> .sun(6), 2(Mon) -> .mon(0), ... 7(Sat) -> .sat(5)
        Weekday(rawValue: (calendarWeekday + 5) % 7)!
    }

    /// Apple's `Calendar` weekday number (1 = Sun ... 7 = Sat), for notification triggers.
    var calendarWeekday: Int { (rawValue + 1) % 7 + 1 }
}

// MARK: - Currency

enum Currency: String, CaseIterable, Identifiable, Codable {
    case krw = "₩"
    case usd = "$"
    case jpy = "¥"
    case eur = "€"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .krw: "원화 (₩)"
        case .usd: "달러 ($)"
        case .jpy: "엔화 (¥)"
        case .eur: "유로 (€)"
        }
    }
}

// MARK: - User Settings

struct UserSettings: Codable, Equatable {
    var salaryType: SalaryType = .yearly
    var salaryAmount: Double = 0
    var workingDays: Set<Weekday> = [.mon, .tue, .wed, .thu, .fri]
    var checkInMinutes: Int = 9 * 60    // 09:00, minutes from midnight
    var checkOutMinutes: Int = 18 * 60  // 18:00
    var startDate: Date = UserSettings.defaultStartDate
    var currency: Currency = .krw
    var appLockEnabled: Bool = false
    var notificationsEnabled: Bool = true   // 퇴근 10분 전 알림 (기본 켜짐)

    /// 올해 1월 1일 — 계산 시작 날짜 기본값.
    static var defaultStartDate: Date {
        var components = Calendar.current.dateComponents([.year], from: .now)
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Calendar.current.startOfDay(for: .now)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case salaryType, salaryAmount, workingDays
        case checkInMinutes, checkOutMinutes, startDate, currency
        case appLockEnabled, notificationsEnabled
    }

    // Tolerant decoding so settings saved by older versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        salaryType = try c.decodeIfPresent(SalaryType.self, forKey: .salaryType) ?? .yearly
        salaryAmount = try c.decodeIfPresent(Double.self, forKey: .salaryAmount) ?? 0
        workingDays = try c.decodeIfPresent(Set<Weekday>.self, forKey: .workingDays) ?? [.mon, .tue, .wed, .thu, .fri]
        checkInMinutes = try c.decodeIfPresent(Int.self, forKey: .checkInMinutes) ?? 9 * 60
        checkOutMinutes = try c.decodeIfPresent(Int.self, forKey: .checkOutMinutes) ?? 18 * 60
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate) ?? UserSettings.defaultStartDate
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .krw
        appLockEnabled = try c.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }
}

// MARK: - Earnings Engine

struct EarningsEngine {
    let settings: UserSettings

    private var workingDaysPerWeek: Double { Double(max(settings.workingDays.count, 1)) }

    /// Daily working time is derived from the check-in/check-out span
    /// (an overnight shift rolls past midnight).
    private var minutesPerDay: Double {
        let diff = settings.checkOutMinutes - settings.checkInMinutes
        return Double(diff > 0 ? diff : diff + 1440)
    }
    private var hoursPerDay: Double { max(minutesPerDay / 60, 0.01) }
    private var secondsPerDay: Double { minutesPerDay * 60 }

    /// Whole minutes worked per day — exposed for the UI's earnings breakdown.
    var dailyWorkMinutes: Int { Int(minutesPerDay) }

    /// Normalized weekly earnings, regardless of salary type.
    var perWeek: Double {
        switch settings.salaryType {
        case .hourly:  settings.salaryAmount * hoursPerDay * workingDaysPerWeek
        case .weekly:  settings.salaryAmount
        case .monthly: settings.salaryAmount * 12 / 52
        case .yearly:  settings.salaryAmount / 52
        }
    }

    var perSecond: Double { perWeek / (workingDaysPerWeek * secondsPerDay) }
    var perMinute: Double { perSecond * 60 }
    var perHour:   Double { perSecond * 3600 }
    var perDay:    Double { perSecond * secondsPerDay }
    var perMonth:  Double { perWeek * 52 / 12 }
    var perYear:   Double { perWeek * 52 }

    // MARK: Today's schedule

    func checkIn(on date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
            .addingTimeInterval(TimeInterval(settings.checkInMinutes * 60))
    }

    /// True when the shift crosses midnight (퇴근 시각이 출근 시각보다 이르거나 같음).
    var isOvernight: Bool { settings.checkOutMinutes <= settings.checkInMinutes }

    func checkOut(on date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        var out = start.addingTimeInterval(TimeInterval(settings.checkOutMinutes * 60))
        // Overnight shift: check-out earlier than check-in rolls to next day.
        if isOvernight {
            out.addTimeInterval(86_400)
        }
        return out
    }

    func isWorkingDay(_ date: Date) -> Bool {
        let weekday = Weekday.from(calendarWeekday: Calendar.current.component(.weekday, from: date))
        return settings.workingDays.contains(weekday)
    }

    enum WorkPhase {
        case dayOff
        case beforeWork(startsIn: TimeInterval)
        case working(elapsed: TimeInterval, remaining: TimeInterval)
        case afterWork
    }

    func phase(at now: Date) -> WorkPhase {
        // An overnight shift that began *yesterday* can still be running after
        // midnight. Check that tail first so crossing 00:00 doesn't drop us out
        // of the "working" state.
        if isOvernight,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
           isWorkingDay(yesterday) {
            let start = checkIn(on: yesterday)
            let end = checkOut(on: yesterday) // rolls into today
            if now >= start && now < end {
                return .working(elapsed: now.timeIntervalSince(start),
                                remaining: end.timeIntervalSince(now))
            }
        }

        guard isWorkingDay(now) else { return .dayOff }
        let start = checkIn(on: now)
        let end = checkOut(on: now)
        if now < start { return .beforeWork(startsIn: start.timeIntervalSince(now)) }
        if now >= end { return .afterWork }
        return .working(elapsed: now.timeIntervalSince(start),
                        remaining: end.timeIntervalSince(now))
    }

    /// Money earned in the given period up to `now`. Weeks start on Monday.
    /// Accrual never starts before `settings.startDate`.
    func earned(_ scope: PeriodScope, at now: Date) -> Double {
        guard scope != .today else { return earnedToday(at: now) }
        return Double(completedWorkingDays(scope, at: now)) * perDay + earnedToday(at: now)
    }

    /// Number of working days in the period that are already behind us
    /// (today excluded — it accrues live via `earnedToday`).
    func completedWorkingDays(_ scope: PeriodScope, at now: Date) -> Int {
        guard scope != .today else { return 0 }

        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday

        let component: Calendar.Component = switch scope {
        case .today: .day
        case .week:  .weekOfYear
        case .month: .month
        case .year:  .year
        }
        guard let interval = calendar.dateInterval(of: component, for: now) else { return 0 }

        var count = 0
        var day = calendar.startOfDay(for: max(interval.start, settings.startDate))
        let todayStart = calendar.startOfDay(for: now)
        while day < todayStart {
            if isWorkingDay(day) { count += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    /// The next day with work after `date`, searching a week ahead.
    func nextWorkingDay(after date: Date) -> Date? {
        let calendar = Calendar.current
        for offset in 1...7 {
            if let day = calendar.date(byAdding: .day, value: offset, to: date),
               isWorkingDay(day) {
                return day
            }
        }
        return nil
    }

    /// Money earned within today's calendar day up to `now`.
    func earnedToday(at now: Date) -> Double {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400)
        let startDate = calendar.startOfDay(for: settings.startDate)
        let lowerBound = max(todayStart, startDate)
        let upperBound = min(now, todayEnd)
        guard upperBound > lowerBound else { return 0 }

        let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86_400)
        var earnedSeconds: TimeInterval = 0

        for shiftDay in [yesterday, todayStart] where isWorkingDay(shiftDay) {
            let overlapStart = max(checkIn(on: shiftDay), lowerBound)
            let overlapEnd = min(checkOut(on: shiftDay), upperBound)
            if overlapEnd > overlapStart {
                earnedSeconds += overlapEnd.timeIntervalSince(overlapStart)
            }
        }

        return earnedSeconds * perSecond
    }

    /// Remaining scheduled work time for the shift that starts on `day`.
    func remainingWorkSeconds(on day: Date, at now: Date) -> TimeInterval {
        guard isWorkingDay(day) else { return 0 }
        let start = checkIn(on: day)
        let end = checkOut(on: day)
        if now <= start { return end.timeIntervalSince(start) }
        if now >= end { return 0 }
        return end.timeIntervalSince(now)
    }

    /// Remaining scheduled work time in the current Monday-starting week.
    func remainingWorkSecondsThisWeek(at now: Date) -> TimeInterval {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return remainingWorkSeconds(in: interval, at: now, calendar: calendar)
    }

    /// Remaining scheduled work time in the current calendar month.
    func remainingWorkSecondsThisMonth(at now: Date) -> TimeInterval {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return remainingWorkSeconds(in: interval, at: now, calendar: calendar)
    }

    /// Number of working days that still have work left in the current month.
    func remainingWorkingDaysThisMonth(at now: Date) -> Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return remainingWorkingDays(in: interval, at: now, calendar: calendar)
    }

    private func remainingWorkSeconds(in interval: DateInterval,
                                      at now: Date,
                                      calendar: Calendar) -> TimeInterval {
        var total: TimeInterval = 0
        let lowerBound = max(now, interval.start)
        guard lowerBound < interval.end else { return 0 }

        let firstDay = calendar.startOfDay(for: interval.start)
        var day = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        while day < interval.end {
            if isWorkingDay(day) {
                let overlapStart = max(checkIn(on: day), lowerBound)
                let overlapEnd = min(checkOut(on: day), interval.end)
                if overlapEnd > overlapStart {
                    total += overlapEnd.timeIntervalSince(overlapStart)
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return total
    }

    private func remainingWorkingDays(in interval: DateInterval,
                                      at now: Date,
                                      calendar: Calendar) -> Int {
        var count = 0
        let lowerBound = max(now, interval.start)
        guard lowerBound < interval.end else { return 0 }

        let firstDay = calendar.startOfDay(for: interval.start)
        var day = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        while day < interval.end {
            if isWorkingDay(day) {
                let overlapStart = max(checkIn(on: day), lowerBound)
                let overlapEnd = min(checkOut(on: day), interval.end)
                if overlapEnd > overlapStart { count += 1 }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }
}

// MARK: - Period Scope (hero counter tap-cycle)

enum PeriodScope: Int, CaseIterable {
    case today, week, month, year

    var label: String {
        switch self {
        case .today: "오늘 벌어온 돈"
        case .week:  "이번 주 벌어온 돈"
        case .month: "이번 달 벌어온 돈"
        case .year:  "올해 벌어온 돈"
        }
    }

    var next: PeriodScope {
        PeriodScope(rawValue: (rawValue + 1) % Self.allCases.count)!
    }
}

// MARK: - App Model (persistence)

final class AppModel: ObservableObject {
    @Published var hasOnboarded: Bool {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }

    @Published var settings: UserSettings {
        didSet { persist() }
    }

    private static let storageKey = "userSettings.v1"

    init() {
        hasOnboarded = UserDefaults.standard.bool(forKey: "hasOnboarded")
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = saved
        } else {
            settings = UserSettings()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    var engine: EarningsEngine { EarningsEngine(settings: settings) }

    /// Wipes everything and returns the app to its fresh-install state.
    func resetAll() {
        settings = UserSettings()
        hasOnboarded = false
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: "hasOnboarded")
    }
}

// MARK: - Brand Colors

extension Color {
    /// Money-green accent used for every amount display.
    static let money = Color(red: 0.22, green: 0.86, blue: 0.49)
    /// Cool blue accent used for countdown and remaining-time displays.
    static let timeAccent = Color(red: 0.22, green: 0.58, blue: 1.0)
}

// MARK: - Formatting Helpers

enum MoneyFormat {
    private static let twoDecimals: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// "₩ 10,855.15" — pass a different symbol for other currencies.
    static func won(_ value: Double, symbol: String = "₩", decimals: Bool = true) -> String {
        let formatter = decimals ? twoDecimals : whole
        return symbol + " " + (formatter.string(from: NSNumber(value: value)) ?? "0")
    }
}

enum DateFormat {
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "EEEE"
        return f
    }()

    /// "내일" for tomorrow, otherwise "월요일" style weekday name.
    static func relativeWeekday(_ date: Date) -> String {
        Calendar.current.isDateInTomorrow(date) ? "내일" : weekdayFormatter.string(from: date)
    }

    private static let koreanDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy년 M월 d일"
        return f
    }()

    /// "2026년 1월 1일"
    static func koreanDate(_ date: Date) -> String {
        koreanDateFormatter.string(from: date)
    }

    /// "03:49:17" — local clock time without fractional seconds.
    static func clockTime(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}

enum DurationFormat {
    /// "5시간 48분" (omits the hour part when zero)
    static func hoursMinutes(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"
    }

    /// "8시간", "8시간 30분", "45분" — drops any zero part for a clean label.
    static func hoursMinutesCompact(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)시간 \(minutes)분" }
        if hours > 0 { return "\(hours)시간" }
        return "\(minutes)분"
    }

    /// "02:18:17.99" — countdown-style duration with hundredths.
    static func clockCountdown(_ interval: TimeInterval) -> String {
        let totalHundredths = max(0, Int((interval * 100).rounded(.down)))
        let hours = totalHundredths / 360_000
        let minutes = (totalHundredths / 6_000) % 60
        let seconds = (totalHundredths / 100) % 60
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, hundredths)
    }
}
