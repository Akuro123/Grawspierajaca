import Foundation
import SwiftData

/// Rehabilitowana kończyna (strona + rodzaj).
enum Limb: String, Codable, CaseIterable, Identifiable {
    case leftArm, rightArm, leftLeg, rightLeg
    var id: String { rawValue }
    var title: String {
        switch self {
        case .leftArm: return "Lewa ręka"
        case .rightArm: return "Prawa ręka"
        case .leftLeg: return "Lewa noga"
        case .rightLeg: return "Prawa noga"
        }
    }
    var profile: ExerciseProfile { self == .leftArm || self == .rightArm ? .hand : .leg }
    var wrist: Wrist { self == .leftArm || self == .leftLeg ? .left : .right }
    var symbol: String { profile == .hand ? "hand.raised.fill" : "figure.walk" }
}

/// Poziom trudności dopasowany do możliwości – nigdy nie wymusza szybkości.
enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case gentle, standard, active
    var id: String { rawValue }
    var title: String { ["gentle": "Łagodny", "standard": "Standardowy", "active": "Aktywny"][rawValue]! }
    var detail: String {
        switch self {
        case .gentle: return "Najniższe progi, dłuższe przerwy, spokojne tempo świata."
        case .standard: return "Domyślne progi i przerwy."
        case .active: return "Wyższe progi i krótsze przerwy. Nadal bez limitu czasu na ruch."
        }
    }
    /// Pauza między zadaniami (s). Gra czeka na pacjenta bez limitu – to tylko oddech po powtórzeniu.
    var restBetweenPrompts: Double { [Difficulty.gentle: 2.5, .standard: 1.2, .active: 0.6][self]! }
    /// Prędkość wizualna świata w trybie ćwiczeń.
    var worldSpeed: Double { [Difficulty.gentle: 7.0, .standard: 10.0, .active: 13.0][self]! }
    var thresholdFactor: Double { [Difficulty.gentle: 0.8, .standard: 1.0, .active: 1.2][self]! }
    var holdFactor: Double { [Difficulty.gentle: 1.4, .standard: 1.0, .active: 0.9][self]! }

    func apply(to m: MotionSettings) -> MotionSettings {
        var s = m
        s.lateralEnter *= thresholdFactor; s.upEnter *= thresholdFactor; s.downEnter *= thresholdFactor
        s.crouchHold *= holdFactor
        s.pitchEnterDeg *= thresholdFactor; s.yawEnterDeg *= thresholdFactor
        // Łagodny i standardowy: tylko kąty, bez wymogu szybkiego ruchu. Aktywny dopuszcza też machnięcia.
        if self != .active { s.mode = .angle } else { s.mode = .both }
        return s.sanitized()
    }
}

/// Profil pacjenta (lokalnie, bez konta). Zakres ćwiczeń powinien zatwierdzić fizjoterapeuta.
@Model
final class PatientProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var limbRaw: String
    var difficultyRaw: String
    var plannedReps: Int
    var sessionMinutes: Int          // 0 = bez limitu
    var enabledActionsRaw: [String]
    var therapistApproved: Bool
    var therapistNote: String
    var createdAt: Date

    init(name: String = "Pacjent", limb: Limb = .rightArm) {
        id = UUID(); self.name = name
        limbRaw = limb.rawValue; difficultyRaw = Difficulty.gentle.rawValue
        plannedReps = 10; sessionMinutes = 0
        enabledActionsRaw = ExerciseAction.actions(for: limb.profile).map(\.rawValue)
        therapistApproved = false; therapistNote = ""; createdAt = Date()
    }

    var limb: Limb { get { Limb(rawValue: limbRaw) ?? .rightArm } set { limbRaw = newValue.rawValue } }
    var difficulty: Difficulty { get { Difficulty(rawValue: difficultyRaw) ?? .gentle } set { difficultyRaw = newValue.rawValue } }
    var enabledActions: Set<ExerciseAction> {
        get {
            let valid = Set(ExerciseAction.actions(for: limb.profile))
            let s = Set(enabledActionsRaw.compactMap(ExerciseAction.init(rawValue:))).intersection(valid)
            return s.isEmpty ? valid : s
        }
        set { enabledActionsRaw = newValue.map(\.rawValue) }
    }
}

// MARK: Poziomy i nagrody (czyste funkcje, testowalne)

enum Progression {
    static let repsPerLevel = 5
    static func level(forReps reps: Int) -> Int { 1 + max(0, reps) / repsPerLevel }
    static func score(reps: Int, coins: Int) -> Int { reps * 100 + coins * 10 }
    /// Gwiazdki za udział (bez kar): 1 za rozpoczęcie z choć jednym powtórzeniem, 2 za połowę, 3 za cały plan.
    static func stars(reps: Int, planned: Int, completed: Bool) -> Int {
        guard reps > 0 else { return 0 }
        if completed { return 3 }
        return Double(reps) >= Double(planned) / 2 ? 2 : 1
    }
}

struct Badge: Identifiable, Equatable {
    let id: String, title: String, detail: String, symbol: String
}

enum Rewards {
    static let all: [Badge] = [
        Badge(id: "first", title: "Pierwszy krok", detail: "Pierwsza ukończona sesja", symbol: "flag.fill"),
        Badge(id: "five", title: "Stała praktyka", detail: "5 ukończonych sesji", symbol: "calendar.badge.checkmark"),
        Badge(id: "streak3", title: "Trzy dni z rzędu", detail: "Ćwiczenia 3 dni pod rząd", symbol: "flame.fill"),
        Badge(id: "reps100", title: "Setka", detail: "100 wykrytych powtórzeń", symbol: "100.circle.fill"),
        Badge(id: "reps500", title: "Maraton ruchu", detail: "500 wykrytych powtórzeń", symbol: "figure.run"),
        Badge(id: "level5", title: "Nowe okolice", detail: "Poziom 5 w jednej sesji", symbol: "map.fill"),
    ]

    static func unlocked(from records: [ExerciseSessionRecord], calendar: Calendar = .current) -> Set<String> {
        var r = Set<String>()
        let done = records.filter(\.completed).count
        if done >= 1 { r.insert("first") }
        if done >= 5 { r.insert("five") }
        let reps = records.reduce(0) { $0 + $1.detectedReps }
        if reps >= 100 { r.insert("reps100") }
        if reps >= 500 { r.insert("reps500") }
        if records.contains(where: { $0.level >= 5 }) { r.insert("level5") }
        if Stats.longestStreak(records, calendar: calendar) >= 3 { r.insert("streak3") }
        return r
    }
}

// MARK: Statystyki

struct DayStat: Identifiable, Equatable {
    var id: Date { day }
    let day: Date
    var reps: Int
    var sessions: Int
    var seconds: Double
}

enum StatsRange: String, CaseIterable, Identifiable {
    case day = "Dzień", week = "Tydzień", month = "Miesiąc"
    var id: String { rawValue }
    var days: Int { self == .day ? 1 : (self == .week ? 7 : 30) }
}

enum Stats {
    /// Serie dni (od najstarszego); dni bez ćwiczeń mają zera.
    static func daily(_ records: [ExerciseSessionRecord], days: Int, now: Date = Date(), calendar: Calendar = .current) -> [DayStat] {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: DayStat] = [:]
        for i in 0..<days {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            buckets[d] = DayStat(day: d, reps: 0, sessions: 0, seconds: 0)
        }
        for r in records {
            let d = calendar.startOfDay(for: r.date)
            guard var b = buckets[d] else { continue }
            b.reps += r.detectedReps; b.sessions += 1; b.seconds += r.activeSeconds
            buckets[d] = b
        }
        return buckets.values.sorted { $0.day < $1.day }
    }

    static func currentStreak(_ records: [ExerciseSessionRecord], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(records.filter { $0.detectedReps > 0 }.map { calendar.startOfDay(for: $0.date) })
        var d = calendar.startOfDay(for: now)
        if !days.contains(d) { d = calendar.date(byAdding: .day, value: -1, to: d)! }   // dziś jeszcze można ćwiczyć
        var n = 0
        while days.contains(d) { n += 1; d = calendar.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    static func longestStreak(_ records: [ExerciseSessionRecord], calendar: Calendar = .current) -> Int {
        let days = Set(records.filter { $0.detectedReps > 0 }.map { calendar.startOfDay(for: $0.date) }).sorted()
        var best = 0, cur = 0, prev: Date?
        for d in days {
            if let p = prev, calendar.date(byAdding: .day, value: 1, to: p) == d { cur += 1 } else { cur = 1 }
            best = max(best, cur); prev = d
        }
        return best
    }

    /// Regularność: odsetek dni z ćwiczeniami w ostatnich `days` dniach.
    static func regularity(_ records: [ExerciseSessionRecord], days: Int = 30, now: Date = Date(), calendar: Calendar = .current) -> Double {
        let series = daily(records, days: days, now: now, calendar: calendar)
        return Double(series.filter { $0.sessions > 0 }.count) / Double(days)
    }

    static func actionTotals(_ records: [ExerciseSessionRecord]) -> [(ExerciseAction, Int)] {
        var t: [ExerciseAction: Int] = [:]
        for r in records { for (a, n) in r.actionCounts { t[a, default: 0] += n } }
        return t.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
