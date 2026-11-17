import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var controller: SessionController

    var body: some View {
        Form {
            Section("Zegarek") {
                Label(controller.watchStatusText, systemImage: controller.connectivity.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                Picker("Ręka z zegarkiem", selection: Binding(get: { controller.settings.wrist }, set: { controller.settings.wrist = $0 })) {
                    ForEach(Wrist.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
            Section {
                Button { controller.requestCalibration() } label: {
                    Label("Ustaw pozycję neutralną", systemImage: "scope")
                }
                switch controller.calibration {
                case .idle: Text("Wygodnie usiądź, ułóż rękę (lub nogę) w pozycji wyjściowej i naciśnij przycisk. Zegarek odliczy 2 s i przez chwilę zmierzy pozycję. Trzymaj ją nieruchomo.").font(.footnote)
                case .waiting: HStack { ProgressView(); Text("Trzymaj nieruchomo…") }
                case .done: Label("Pozycja neutralna ustawiona", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed(let m): Label(m, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } header: { Text("Pozycja neutralna") }
            Section {
                if controller.isTesting {
                    Text(controller.testGesture ?? "Wykonaj ruch…").font(.title2.bold()).frame(maxWidth: .infinity)
                    Button("Zakończ test", role: .cancel) { controller.stopTest() }
                } else {
                    Button("Tester gestów") { controller.startTest() }
                        .disabled(controller.calibration != .done)
                }
            } header: { Text("Tester") } footer: {
                Text("Pokazuje nazwę wykrytego gestu. Nic nie jest zaliczane ani zapisywane.")
            }
            Section {
                Button { router.push(.diagnostics) } label: { Label("Ekran diagnostyczny", systemImage: "waveform.path.ecg") }
            } footer: { Text("Podgląd orientacji, przyspieszenia, rozpoznanego gestu i opóźnienia komunikacji w czasie rzeczywistym.") }
            Section("Progi i czasy") {
                DisclosureGroup("Zaawansowane") { MotionSettingsEditor(store: controller.settings) }
            }
            Section {
                Button("Rozpocznij sesję") {
                    controller.beginExercise()
                    if controller.errorMessage == nil { router.push(.game) }
                }
                .bold().disabled(controller.calibration != .done)
            }
        }
        .scrollContentBackground(.hidden)
        .background(SkyBackground())
        .navigationTitle("Kalibracja")
        .onAppear { controller.resetCalibrationState() }
        .onDisappear { controller.stopTest() }
        .alert("Uwaga", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(controller.errorMessage ?? "") }
    }
}
