import Foundation
import SwiftData

/// Zapis sesji ćwiczeń. Tylko podsumowanie: bez surowych danych czujnika.
/// Nowe pola mają wartości domyślne, więc istniejące dane migrują się automatycznie.
@Model
final class ExerciseSessionRecord {
    @Attribute(.unique) var id: UUID
    var profileRaw: String
    var date: Date
    var activeSeconds: Double
    var plannedReps: Int
    var detectedReps: Int
    var completed: Bool
    var limbRaw: String = ""
    var difficultyRaw: String = Difficulty.standard.rawValue
    var coins: Int = 0
    var score: Int = 0
    var level: Int = 1
    var timeLimitSeconds: Int = 0
    /// JSON: [rawValueAkcji: liczba powtórzeń].
    var actionCountsData: Data?
    var patientID: UUID?

    init(id: UUID, profile: ExerciseProfile, date: Date, plannedReps: Int) {
        self.id = id
        self.profileRaw = profile.rawValue
        self.date = date
        self.activeSeconds = 0
        self.plannedReps = plannedReps
        self.detectedReps = 0
        self.completed = false
    }

    var profile: ExerciseProfile { ExerciseProfile(rawValue: profileRaw) ?? .hand }
    var limb: Limb? { Limb(rawValue: limbRaw) }
    var difficulty: Difficulty { Difficulty(rawValue: difficultyRaw) ?? .standard }
    var actionCounts: [ExerciseAction: Int] {
        get {
            guard let d = actionCountsData, let raw = try? JSONDecoder().decode([String: Int].self, from: d) else { return [:] }
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in ExerciseAction(rawValue: k).map { ($0, v) } })
        }
        set { actionCountsData = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })) }
    }
}

struct HistoryTotals: Equatable {
    var sessions = 0
    var repetitions = 0

    static func totals(for profile: ExerciseProfile, in records: [ExerciseSessionRecord]) -> HistoryTotals {
        records.filter { $0.profile == profile }.reduce(into: HistoryTotals()) {
            $0.sessions += 1
            $0.repetitions += $1.detectedReps
        }
    }
}
