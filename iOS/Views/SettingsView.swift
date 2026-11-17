import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var controller: SessionController
    @Environment(\.modelContext) private var context
    @State private var sound = Sfx.shared.enabled
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Dźwięk") {
                Toggle("Efekty dźwiękowe", isOn: Binding(get: { sound }, set: { sound = $0; Sfx.shared.enabled = $0 }))
            }
            Section("Zegarek") {
                Label(controller.watchStatusText, systemImage: "applewatch")
                Button("Kalibracja i tester gestów") { router.push(.calibration) }
                Button("Ekran diagnostyczny") { router.push(.diagnostics) }
                DisclosureGroup("Czułość i progi (zaawansowane)") { MotionSettingsEditor(store: controller.settings) }
            }
            Section("Przypomnienia") {
                Button("Zaplanuj przypomnienia") { router.push(.reminders) }
            }
            Section {
                Button("Usuń wszystkie zapisane sesje", role: .destructive) { confirmDelete = true }
            } footer: { Text("Dane są przechowywane wyłącznie na tym iPhonie. Aplikacja nie wymaga konta.") }
            Section("Informacje") {
                Text("Rehab Runner nie jest wyrobem medycznym. Rozpoznaje ruch zegarka, ale nie ocenia poprawności ćwiczenia, zakresu ruchu w stawie ani poprawy stanu zdrowia. Zestaw ćwiczeń i zakresy ruchu powinien zatwierdzić fizjoterapeuta. Grafika i dźwięki są własne (licencje: Resources/LICENSES.md).")
                    .font(.footnote)
            }
        }
        .navigationTitle("Ustawienia")
        .confirmationDialog("Usunąć wszystkie sesje?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Usuń", role: .destructive) {
                try? context.delete(model: ExerciseSessionRecord.self); try? context.save()
            }
        } message: { Text("Tej operacji nie można cofnąć.") }
    }
}
