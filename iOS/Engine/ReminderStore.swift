import Foundation
import UserNotifications

struct ReminderSettings: Codable, Equatable {
    var enabled = false
    var weekdays: Set<Int> = [2, 4, 6]   // Calendar: 1 = niedziela … 7 = sobota
    var hour = 18
    var minute = 0
}

enum ReminderPlan {
    /// Czysta funkcja: identyfikator + składniki daty dla każdego wybranego dnia.
    static func requests(for s: ReminderSettings) -> [(id: String, components: DateComponents)] {
        guard s.enabled else { return [] }
        return s.weekdays.sorted().map { day in
            (id: "reminder.weekday.\(day)", components: DateComponents(hour: s.hour, minute: s.minute, weekday: day))
        }
    }
}

@MainActor
final class ReminderStore: ObservableObject {
    @Published var settings: ReminderSettings { didSet { persist() } }
    @Published var statusMessage: String?
    private let defaults = UserDefaults.standard
    private let key = "reminders.v1"

    init() {
        if let d = defaults.data(forKey: key), let s = try? JSONDecoder().decode(ReminderSettings.self, from: d) {
            settings = s
        } else { settings = ReminderSettings() }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(settings) { defaults.set(d, forKey: key) }
    }

    func apply() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (1...7).map { "reminder.weekday.\($0)" })
        guard settings.enabled else { statusMessage = "Przypomnienia wyłączone."; return }
        guard !settings.weekdays.isEmpty else { statusMessage = "Wybierz przynajmniej jeden dzień."; return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else {
            statusMessage = "Brak zgody na powiadomienia. Włącz je w Ustawieniach systemu."
            return
        }
        for r in ReminderPlan.requests(for: settings) {
            let content = UNMutableNotificationContent()
            content.title = "Czas na sesję ćwiczeń"
            content.body = "Otwórz Rehab Runner, gdy będziesz gotowy."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: r.components, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
        statusMessage = "Zapisano przypomnienia lokalne."
    }
}
