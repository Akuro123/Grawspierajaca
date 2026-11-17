import SwiftUI

/// Profil pacjenta i zestaw ćwiczeń przed sesją. Duże, czytelne elementy.
struct ProfileView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var controller: SessionController

    var body: some View {
        ZStack {
            SkyBackground()
            if let p = controller.patient { content(p) } else { ProgressView() }
        }
        .navigationTitle("Twoja sesja")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ p: PatientProfile) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    Text("Imię (opcjonalnie)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("Pacjent", text: Binding(get: { p.name }, set: { p.name = $0; controller.patientChanged() }))
                        .font(.game(22)).textInputAutocapitalization(.words)
                }
                Card {
                    Text("Ćwiczona kończyna").font(.game(20))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(Limb.allCases) { l in
                            Button {
                                p.limb = l; p.enabledActions = Set(ExerciseAction.actions(for: l.profile))
                                controller.patientChanged(); Sfx.shared.play(.tap)
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: l.symbol).font(.system(size: 28))
                                    Text(l.title).font(.game(16))
                                }
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .foregroundStyle(p.limb == l ? .white : Theme.ink)
                                .background(RoundedRectangle(cornerRadius: 18).fill(p.limb == l ? Theme.indigo : Theme.ink.opacity(0.07)))
                            }.buttonStyle(.plain)
                             .accessibilityAddTraits(p.limb == l ? .isSelected : [])
                        }
                    }
                    if p.limb.profile == .leg {
                        Label("Noga: zegarek mocuje się na podudziu lub kostce, a ruch wykonuje się w siadzie. Czujnik nie ocenia pracy stawu, tylko zmianę nachylenia zegarka.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Card {
                    Text("Ćwiczenia w grze").font(.game(20))
                    ForEach(ExerciseAction.actions(for: p.limb.profile)) { a in
                        Toggle(isOn: Binding(get: { p.enabledActions.contains(a) }, set: { _ in controller.toggle(a) })) {
                            Label { VStack(alignment: .leading) { Text(a.title).font(.headline); Text(a.hint).font(.caption).foregroundStyle(.secondary) } }
                                icon: { Image(systemName: a.symbolName).foregroundStyle(Theme.orange) }
                        }.tint(Theme.teal)
                    }
                }
                Card {
                    Text("Tempo i cel").font(.game(20))
                    Picker("Poziom", selection: Binding(get: { p.difficulty }, set: { p.difficulty = $0; controller.patientChanged() })) {
                        ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(p.difficulty.detail).font(.footnote).foregroundStyle(.secondary)
                    Stepper(value: Binding(get: { p.plannedReps }, set: { p.plannedReps = $0; controller.patientChanged() }), in: 1...100) {
                        Text("Powtórzenia: **\(p.plannedReps)**").font(.headline)
                    }
                    Stepper(value: Binding(get: { p.sessionMinutes }, set: { p.sessionMinutes = $0; controller.patientChanged() }), in: 0...60, step: 5) {
                        Text(p.sessionMinutes == 0 ? "Czas sesji: **bez limitu**" : "Czas sesji: **\(p.sessionMinutes) min**").font(.headline)
                    }
                    Text("To Ty ustalasz tempo. Gra czeka na Twój ruch bez limitu czasu i nie karze za powolność. Sesja kończy się po osiągnięciu liczby powtórzeń albo upływie ustawionego czasu.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Card {
                    Toggle(isOn: Binding(get: { p.therapistApproved }, set: { p.therapistApproved = $0; controller.patientChanged() })) {
                        Text("Zestaw zatwierdzony przez fizjoterapeutę").font(.headline)
                    }.tint(Theme.teal)
                    TextField("Notatka terapeuty (zakres ruchu, zalecenia)", text: Binding(get: { p.therapistNote }, set: { p.therapistNote = $0; controller.patientChanged() }), axis: .vertical)
                        .lineLimit(1...4).textFieldStyle(.roundedBorder)
                    if !p.therapistApproved {
                        Label("Zestaw ćwiczeń i zakresy ruchu powinien zatwierdzić fizjoterapeuta, zanim zaczniesz regularne ćwiczenia.", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.coral)
                    }
                }
                Button { Sfx.shared.play(.tap); router.push(.calibration) } label: { Label("Dalej: kalibracja", systemImage: "scope") }
                    .buttonStyle(GameButtonStyle(color: Theme.orange))
                Text("Ćwiczenie możesz wstrzymać w dowolnym momencie.").font(.footnote).foregroundStyle(Theme.ink.opacity(0.7))
            }
            .padding(16)
        }
    }
}
