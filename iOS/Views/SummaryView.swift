import SwiftUI

struct SummaryView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var controller: SessionController
    @State private var shown = 0

    var body: some View {
        let s = controller.summary
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 16) {
                    Text((s?.completed ?? false) ? "Świetna sesja!" : "Sesja zakończona").font(.game(34)).foregroundStyle(Theme.ink)
                    if s?.endedByTime == true { Text("Upłynął ustawiony czas sesji.").font(.callout.weight(.semibold)).foregroundStyle(Theme.ink.opacity(0.75)) }
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < shown ? "star.fill" : "star")
                                .font(.system(size: 54)).foregroundStyle(i < shown ? Theme.gold : Theme.ink.opacity(0.25))
                                .scaleEffect(i < shown ? 1 : 0.8).animation(.spring(duration: 0.5, bounce: 0.5), value: shown)
                        }
                    }.accessibilityElement().accessibilityLabel("Gwiazdki: \(s?.stars ?? 0) z 3")
                    if let s {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            StatTile(value: "\(s.detected)/\(s.planned)", label: "Wykryte powtórzenia", symbol: "repeat", color: Theme.indigo)
                            StatTile(value: formatDuration(s.activeSeconds), label: "Aktywny czas", symbol: "timer", color: Theme.teal)
                            StatTile(value: "\(s.coins)", label: "Monety", symbol: "circle.fill", color: Theme.gold)
                            StatTile(value: "\(s.score)", label: "Punkty · poziom \(s.level)", symbol: "star.fill", color: Theme.orange)
                        }
                        if !s.actionCounts.isEmpty {
                            Card {
                                Text("Ćwiczenia w tej sesji").font(.game(18))
                                ForEach(s.actionCounts.sorted { $0.value > $1.value }, id: \.key) { a, n in
                                    HStack { Image(systemName: a.symbolName).foregroundStyle(Theme.orange); Text(a.title); Spacer(); Text("\(n)").bold() }
                                }
                            }
                        }
                        if !s.newBadges.isEmpty {
                            Card {
                                Text("Nowe odznaki!").font(.game(18))
                                ForEach(s.newBadges) { b in
                                    Label { VStack(alignment: .leading) { Text(b.title).bold(); Text(b.detail).font(.caption).foregroundStyle(.secondary) } }
                                        icon: { Image(systemName: b.symbol).font(.title2).foregroundStyle(Theme.gold) }
                                }
                            }
                        }
                    }
                    Text("Liczba powtórzeń to zapis tego, co wykryto. Nie jest oceną techniki, sprawności ani poprawy zdrowia.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.7)).multilineTextAlignment(.center)
                    Button { controller.leaveGame(); router.path = [.stats] } label: { Label("Zobacz postępy", systemImage: "chart.bar.fill") }
                        .buttonStyle(GameButtonStyle(color: Theme.indigo, compact: true))
                    Button { controller.leaveGame(); router.home() } label: { Label("Wróć na start", systemImage: "house.fill") }
                        .buttonStyle(GameButtonStyle(color: Theme.orange))
                }.padding(20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let n = s?.stars ?? 0
            if n > 0 { Sfx.shared.play(.reward) }
            for i in 1...max(1, n) where n > 0 { try? await Task.sleep(for: .milliseconds(350)); shown = i }
        }
    }
}
