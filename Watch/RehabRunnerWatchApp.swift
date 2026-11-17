import SwiftUI

@main
struct RehabRunnerWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup { WatchRootView().environmentObject(model) }
    }
}

struct WatchRootView: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        NavigationStack {
            switch model.mode {
            case .idle: home
            case .calibrating: calibrating
            case .test: tester
            case .session: session
            }
        }
    }

    private var home: some View {
        List {
            Label(model.reachable ? "iPhone połączony" : "iPhone niedostępny", systemImage: model.reachable ? "iphone" : "iphone.slash")
                .font(.footnote)
            if let m = model.message { Text(m).font(.footnote).foregroundStyle(.orange) }
            Button { model.calibrateLocally() } label: { Label("Pozycja neutralna", systemImage: "scope") }
            Button { model.startLocalTest() } label: { Label("Tester gestów", systemImage: "hand.draw") }
                .disabled(!model.hasNeutral)
            NavigationLink { WatchSettingsView() } label: { Label("Ustawienia", systemImage: "slider.horizontal.3") }
        }
        .navigationTitle("Rehab Runner")
    }

    private var calibrating: some View {
        VStack(spacing: 8) {
            if let c = model.countdown { Text("\(c)").font(.system(size: 60, weight: .bold)) ; Text("Ułóż rękę") }
            else { ProgressView(); Text("Trzymaj nieruchomo") }
        }
    }

    private var tester: some View {
        VStack(spacing: 6) {
            Text("Tester").font(.footnote).foregroundStyle(.secondary)
            Text(model.lastGesture ?? "Wykonaj ruch").font(.title3.bold()).multilineTextAlignment(.center)
            Text(model.debugLine).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            Button("Zakończ") { model.stopLocally() }
        }
    }

    private var session: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.run").font(.largeTitle).foregroundStyle(.orange)
            Text("Ćwiczenie trwa").font(.headline)
            Text("Wysłane: \(model.sentEvents)").font(.footnote)
            if let g = model.lastGesture { Text(g).font(.caption2).foregroundStyle(.secondary) }
            Text(model.debugLine).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
            Button("Zatrzymaj", role: .destructive) { model.stopLocally() }
        }
    }
}

struct WatchSettingsView: View {
    @EnvironmentObject var model: WatchModel
    var body: some View {
        List { MotionSettingsEditor(store: model.store) }.navigationTitle("Ustawienia")
    }
}
