import SwiftUI

struct RemindersView: View {
    @EnvironmentObject var store: ReminderStore
    // Kolejność: Pn … Nd. Wartości zgodne z Calendar (1 = niedziela).
    private let days: [(label: String, value: Int)] = [("Pn", 2), ("Wt", 3), ("Śr", 4), ("Cz", 5), ("Pt", 6), ("Sb", 7), ("Nd", 1)]

    private var timeBinding: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: store.settings.hour, minute: store.settings.minute)) ?? Date()
        } set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            store.settings.hour = c.hour ?? 18; store.settings.minute = c.minute ?? 0
        }
    }

    var body: some View {
        Form {
            Section { Toggle("Przypomnienia o sesji", isOn: $store.settings.enabled) }
            if store.settings.enabled {
                Section("Dni") {
                    HStack {
                        ForEach(days, id: \.value) { d in
                            let on = store.settings.weekdays.contains(d.value)
                            Button(d.label) {
                                if on { store.settings.weekdays.remove(d.value) } else { store.settings.weekdays.insert(d.value) }
                            }
                            .buttonStyle(.borderedProminent).tint(on ? .orange : .gray.opacity(0.5))
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Section("Godzina") { DatePicker("Godzina", selection: timeBinding, displayedComponents: .hourAndMinute) }
            }
            if let m = store.statusMessage { Section { Text(m).font(.footnote) } }
        }
        .navigationTitle("Przypomnienia")
        .task(id: store.settings) { await store.apply() }
    }
}
