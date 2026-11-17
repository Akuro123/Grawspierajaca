import SwiftUI

/// Ekran diagnostyczny: na żywo pokazuje to, co widzi zegarek (orientacja, przyspieszenie, stan detektora, ostatni gest)
/// oraz opóźnienie komunikacji (ping RTT). Wymaga zegarka z uruchomioną aplikacją i ustawioną pozycją neutralną.
struct DiagnosticsView: View {
    @EnvironmentObject var controller: SessionController

    private var rttMedian: Double? {
        let s = controller.rttMs.sorted(); return s.isEmpty ? nil : s[s.count / 2]
    }

    var body: some View {
        let t = controller.telemetry
        let mo = controller.settings.motion
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    Label(controller.watchStatusText, systemImage: controller.connectivity.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash").font(.headline)
                    if controller.calibration != .done {
                        Text("Najpierw ustaw pozycję neutralną (Kalibracja).").font(.footnote).foregroundStyle(Theme.coral)
                        Button("Ustaw pozycję neutralną") { controller.requestCalibration() }.buttonStyle(GameButtonStyle(color: Theme.indigo, compact: true))
                        if controller.calibration == .waiting { ProgressView("Trzymaj nieruchomo…") }
                        if case .failed(let m) = controller.calibration { Text(m).font(.footnote).foregroundStyle(Theme.coral) }
                    }
                    Button(controller.isTesting ? "Zatrzymaj podgląd" : "Uruchom podgląd na żywo") {
                        controller.isTesting ? controller.stopTest() : controller.startTest()
                    }.buttonStyle(GameButtonStyle(color: controller.isTesting ? Theme.coral : Theme.teal, compact: true))
                }
                Card {
                    Text("Orientacja przedramienia").font(.game(18))
                    AngleBar(title: "Góra / dół", value: t?.pitchDeg ?? 0, threshold: mo.pitchEnterDeg, positive: "góra", negative: "dół")
                    AngleBar(title: "Lewo / prawo", value: t?.yawDeg ?? 0, threshold: mo.yawEnterDeg, positive: "prawo", negative: "lewo")
                    AngleBar(title: "Obrót (kucanie)", value: t?.rollDeg ?? 0, threshold: mo.crouchEnterDeg, positive: "obrót", negative: "", oneSided: true)
                }
                Card {
                    Text("Przyspieszenie (g)").font(.game(18))
                    AngleBar(title: "Boczne", value: t?.accelLateral ?? 0, threshold: mo.lateralEnter, positive: "prawo", negative: "lewo", range: 2, unit: "g")
                    AngleBar(title: "Pionowe", value: t?.accelVertical ?? 0, threshold: mo.upEnter, positive: "góra", negative: "dół", range: 2, unit: "g")
                }
                Card {
                    Text("Detektor").font(.game(18))
                    LabeledContent("Stan", value: t?.phase ?? "—")
                    LabeledContent("Ostatni gest", value: t?.lastGesture ?? controller.testGesture ?? "—")
                    LabeledContent("Tryb", value: mo.mode.title)
                    if controller.gestureLog.isEmpty { Text("Wykonaj ruch…").foregroundStyle(.secondary) }
                    ForEach(Array(controller.gestureLog.enumerated()), id: \.offset) { _, e in
                        HStack { Text(e.date.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary); Text(e.name) }.font(.footnote)
                    }
                }
                Card {
                    Text("Komunikacja").font(.game(18))
                    LabeledContent("Ping (mediana RTT)", value: rttMedian.map { String(format: "%.0f ms", $0) } ?? "—")
                    LabeledContent("Ostatni / maks.", value: controller.rttMs.last.map { String(format: "%.0f / %.0f ms", $0, controller.rttMs.max() ?? $0) } ?? "—")
                    LabeledContent("Wiek ostatnich danych", value: controller.telemetryAge.map { String(format: "%.1f s", $0) } ?? "—")
                    if let age = controller.telemetryAge, age > 1.5, controller.isTesting {
                        Label("Brak świeżych danych z zegarka. Sprawdź, czy aplikacja zegarka jest otwarta.", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.coral)
                    }
                    Text("Jednokierunkowe opóźnienie ≈ połowa RTT. Zdarzenia gestów mają gwarantowaną dostawę zapasową, więc przy słabym łączu mogą dotrzeć później.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(SkyBackground())
        .navigationTitle("Diagnostyka")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.startPings() }
        .onDisappear { controller.stopPings(); controller.stopTest() }
    }
}

/// Pasek wartości z zaznaczonym progiem wykrycia.
struct AngleBar: View {
    let title: String, value: Double, threshold: Double, positive: String, negative: String
    var oneSided = false
    var range: Double? = nil
    var unit = "°"

    var body: some View {
        let span = range ?? max(60, threshold * 2)
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.subheadline.weight(.semibold)); Spacer()
                Text(String(format: "%+.\(unit == "g" ? 2 : 0)f %@", value, unit)).monospacedDigit().font(.subheadline) }
            GeometryReader { g in
                let w = g.size.width
                let center = oneSided ? 0 : w / 2
                let scale = (oneSided ? w : w / 2) / span
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.1))
                    let x = center + max(-span, min(span, value)) * scale
                    Capsule().fill(abs(value) >= threshold ? Theme.teal : Theme.indigo)
                        .frame(width: max(4, abs(x - center)))
                        .offset(x: min(x, center))
                    ForEach(oneSided ? [threshold] : [-threshold, threshold], id: \.self) { th in
                        Rectangle().fill(Theme.coral).frame(width: 2).offset(x: center + th * scale)
                    }
                }
            }.frame(height: 14)
            if !oneSided { HStack { Text(negative); Spacer(); Text(positive) }.font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
