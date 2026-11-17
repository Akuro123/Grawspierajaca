import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var controller: SessionController
    @Query(sort: \ExerciseSessionRecord.date, order: .reverse) private var records: [ExerciseSessionRecord]

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rehab Runner").font(.game(34)).foregroundStyle(Theme.ink)
                            Text("Ćwicz przez zabawę").font(.game(16, .semibold)).foregroundStyle(Theme.ink.opacity(0.7))
                        }
                        Spacer()
                        Button { Sfx.shared.play(.tap); router.push(.settings) } label: {
                            Image(systemName: "gearshape.fill").font(.title2).foregroundStyle(Theme.ink)
                                .frame(width: 52, height: 52).background(Circle().fill(.white.opacity(0.8)))
                        }.accessibilityLabel("Ustawienia")
                    }
                    HeroView3D().frame(height: 340)
                    streakBanner
                    Button { Sfx.shared.play(.tap); router.push(.profile) } label: {
                        Label("Graj – sesja ćwiczeń", systemImage: "play.fill")
                    }.buttonStyle(GameButtonStyle(color: Theme.orange))
                    HStack(spacing: 12) {
                        Button { Sfx.shared.play(.tap); router.push(.stats) } label: { Label("Postępy", systemImage: "chart.bar.fill") }
                            .buttonStyle(GameButtonStyle(color: Theme.indigo, compact: true))
                        Button { Sfx.shared.play(.tap); router.push(.reminders) } label: { Label("Przypomnienia", systemImage: "bell.fill") }
                            .buttonStyle(GameButtonStyle(color: Theme.teal, compact: true))
                    }
                    Button { Sfx.shared.play(.tap); controller.startDemo(); router.push(.demo) } label: {
                        Label("Próba bez zegarka", systemImage: "gamecontroller.fill")
                    }.buttonStyle(GameButtonStyle(color: Theme.ink.opacity(0.75), compact: true))
                    Label(controller.watchStatusText, systemImage: controller.connectivity.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink.opacity(0.75))
                    Text("Aplikacja rozpoznaje ruch, ale nie ocenia poprawności ćwiczenia ani stanu zdrowia. Ćwicz zgodnie z zaleceniami terapeuty.")
                        .font(.caption).foregroundStyle(Theme.ink.opacity(0.65)).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var streakBanner: some View {
        let streak = Stats.currentStreak(records)
        let today = Stats.daily(records, days: 1).first
        return HStack(spacing: 12) {
            Image(systemName: "flame.fill").font(.title).foregroundStyle(streak > 0 ? Theme.orange : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak > 0 ? "Seria: \(streak) \(streak == 1 ? "dzień" : "dni")" : "Zacznij serię ćwiczeń").font(.game(18))
                Text("Dziś: \(today?.reps ?? 0) powtórzeń").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.9)))
        .accessibilityElement(children: .combine)
    }
}
