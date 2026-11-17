import SwiftUI
import SwiftData
import Charts

/// Panel postępów: wykresy aktywności (dzień/tydzień/miesiąc), regularność, serie, odznaki i historia per kończyna.
struct StatsView: View {
    @Query(sort: \ExerciseSessionRecord.date, order: .reverse) private var records: [ExerciseSessionRecord]
    @State private var range: StatsRange = .week
    @State private var limbFilter: Limb?

    private var filtered: [ExerciseSessionRecord] { limbFilter == nil ? records : records.filter { $0.limb == limbFilter } }

    var body: some View {
        ZStack {
            SkyBackground()
            ScrollView {
                VStack(spacing: 14) {
                    tiles
                    Card {
                        Picker("Zakres", selection: $range) { ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                        chart
                    }
                    Card {
                        Text("Kończyna").font(.game(18))
                        Picker("Kończyna", selection: $limbFilter) {
                            Text("Wszystkie").tag(Limb?.none)
                            ForEach(Limb.allCases) { Text($0.title).tag(Limb?.some($0)) }
                        }.pickerStyle(.menu)
                    }
                    actions
                    badges
                    history
                    Text("Dane pokazują liczbę sesji i wykrytych powtórzeń. Nie oznaczają poprawy sprawności ani poprawności ćwiczeń. Wszystko jest zapisane tylko na tym urządzeniu.")
                        .font(.footnote).foregroundStyle(Theme.ink.opacity(0.7)).multilineTextAlignment(.center)
                }.padding(16)
            }
        }
        .navigationTitle("Postępy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tiles: some View {
        let reg = Stats.regularity(filtered)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(value: "\(filtered.count)", label: "Sesje", symbol: "figure.strengthtraining.traditional", color: Theme.indigo)
            StatTile(value: "\(filtered.filter(\.completed).count)", label: "Ukończone", symbol: "checkmark.seal.fill", color: Theme.teal)
            StatTile(value: "\(filtered.reduce(0) { $0 + $1.detectedReps })", label: "Powtórzenia", symbol: "repeat", color: Theme.orange)
            StatTile(value: "\(Stats.currentStreak(filtered))", label: "Seria dni (rekord \(Stats.longestStreak(filtered)))", symbol: "flame.fill", color: Theme.coral)
            StatTile(value: "\(Int((reg * 100).rounded()))%", label: "Regularność (30 dni)", symbol: "calendar", color: Theme.indigo)
            StatTile(value: formatDuration(filtered.reduce(0) { $0 + $1.activeSeconds }), label: "Łączny czas", symbol: "timer", color: Theme.teal)
        }
    }

    @ViewBuilder private var chart: some View {
        if range == .day {
            let today = Stats.daily(filtered, days: 1).first
            let todays = filtered.filter { Calendar.current.isDateInToday($0.date) }
            Text("Dziś: \(today?.reps ?? 0) powtórzeń w \(today?.sessions ?? 0) sesjach").font(.headline)
            if todays.isEmpty { Text("Dzisiaj jeszcze nie ćwiczyłeś. Zacznij, kiedy będziesz gotowy.").font(.footnote).foregroundStyle(.secondary) }
            else {
                Chart(todays) { r in
                    BarMark(x: .value("Godzina", r.date, unit: .hour), y: .value("Powtórzenia", r.detectedReps)).foregroundStyle(Theme.orange).cornerRadius(6)
                }.frame(height: 190)
            }
        } else {
            let data = Stats.daily(filtered, days: range.days)
            if data.allSatisfy({ $0.reps == 0 }) {
                Text("Brak powtórzeń w tym okresie. Wykres pojawi się po pierwszej sesji.").font(.footnote).foregroundStyle(.secondary)
            }
            Chart(data) { d in
                BarMark(x: .value("Dzień", d.day, unit: .day), y: .value("Powtórzenia", d.reps)).foregroundStyle(Theme.orange).cornerRadius(5)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.defaultDigits)) } }
            .frame(height: 190)
            .accessibilityLabel("Wykres powtórzeń z ostatnich \(range.days) dni")
        }
    }

    @ViewBuilder private var actions: some View {
        let t = Stats.actionTotals(filtered)
        if !t.isEmpty {
            Card {
                Text("Wykonane ruchy").font(.game(18))
                Chart(t, id: \.0) { a, n in
                    BarMark(x: .value("Liczba", n), y: .value("Ruch", a.title)).foregroundStyle(Theme.indigo).cornerRadius(5)
                }.frame(height: CGFloat(t.count) * 38 + 20)
            }
        }
    }

    private var badges: some View {
        let got = Rewards.unlocked(from: records)
        return Card {
            Text("Odznaki").font(.game(18))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Rewards.all) { b in
                    let on = got.contains(b.id)
                    VStack(spacing: 4) {
                        Image(systemName: b.symbol).font(.system(size: 30)).foregroundStyle(on ? Theme.gold : .gray.opacity(0.4))
                        Text(b.title).font(.caption.weight(.bold)).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).opacity(on ? 1 : 0.6)
                    .accessibilityElement(children: .combine).accessibilityHint(b.detail + (on ? ", zdobyta" : ", jeszcze nie zdobyta"))
                }
            }
        }
    }

    private var history: some View {
        Card {
            Text("Historia sesji").font(.game(18))
            if filtered.isEmpty { Text("Brak zapisanych sesji.").foregroundStyle(.secondary) }
            ForEach(filtered.prefix(40)) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\((r.limb?.title ?? r.profile.title)) · \(r.date.formatted(date: .abbreviated, time: .shortened))").font(.subheadline.bold())
                    Text("Powtórzenia: \(r.detectedReps) z \(r.plannedReps) · \(r.completed ? "ukończona" : "przerwana") · \(formatDuration(r.activeSeconds)) · \(r.difficulty.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
            }
        }
    }
}
