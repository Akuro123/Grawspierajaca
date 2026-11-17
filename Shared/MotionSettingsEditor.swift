import SwiftUI

/// Edytor progów – wstawiany do Form (iPhone) lub List (Watch).
struct MotionSettingsEditor: View {
    @ObservedObject var store: MotionSettingsStore

    var body: some View {
        Group {
            Picker("Ręka z zegarkiem", selection: $store.wrist) {
                ForEach(Wrist.allCases) { Text($0.title).tag($0) }
            }
            Picker("Tryb rozpoznawania", selection: $store.motion.mode) { ForEach(GestureMode.allCases) { Text($0.title).tag($0) } }
            row("Kąt: góra/dół", $store.motion.pitchEnterDeg, 8...60, 1, "°")
            row("Kąt: lewo/prawo", $store.motion.yawEnterDeg, 8...60, 1, "°")
            row("Kąt: powrót do neutralnej", $store.motion.angleExitDeg, 3...30, 1, "°")
            row("Utrzymanie kąta", $store.motion.angleHold, 0.05...1.0, 0.05, "s")
            row("Próg: lewo/prawo", $store.motion.lateralEnter, 0.2...2.0, 0.05, "g")
            row("Próg: w górę", $store.motion.upEnter, 0.2...2.0, 0.05, "g")
            row("Próg: w dół", $store.motion.downEnter, 0.2...2.0, 0.05, "g")
            row("Próg ustania ruchu", $store.motion.exitAccel, 0.05...0.5, 0.01, "g")
            row("Obrót: wejście", $store.motion.crouchEnterDeg, 10...70, 1, "°")
            row("Obrót: wyjście", $store.motion.crouchExitDeg, 3...40, 1, "°")
            row("Przytrzymanie kucania", $store.motion.crouchHold, 0.1...2.0, 0.05, "s")
            row("Czas w neutralnej", $store.motion.neutralHold, 0.05...1.5, 0.05, "s")
            row("Minimalna blokada", $store.motion.minLock, 0...1.5, 0.05, "s")
            row("Noga: wejście", $store.leg.enterDeg, 10...80, 1, "°")
            row("Noga: wyjście", $store.leg.exitDeg, 3...40, 1, "°")
            row("Noga: przytrzymanie", $store.leg.hold, 0.05...1.0, 0.05, "s")
            Button("Przywróć domyślne", role: .destructive) { store.resetToDefaults() }
        }
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double, _ unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote)
                Text(String(format: "%.2f %@", value.wrappedValue, unit)).font(.body.monospacedDigit())
            }
        }
    }
}
