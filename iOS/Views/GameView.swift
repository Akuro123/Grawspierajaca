import SwiftUI

struct GameView: View {
    let demo: Bool
    @EnvironmentObject var controller: SessionController
    @EnvironmentObject var router: Router
    @State private var swipeFired = false
    @State private var crouchHeld = false
    @State private var zoneBanner: String?

    var body: some View {
        ZStack {
            if let scene = controller.scene {
                Game3DView(runner: scene).ignoresSafeArea()
            } else { Color.black.ignoresSafeArea() }

            if demo { demoLayer } else { exerciseLayer }

            if let zoneBanner {
                Text(zoneBanner).font(.game(30)).foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Capsule().fill(Theme.indigo)).overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 3))
                    .transition(.scale.combined(with: .opacity)).offset(y: -140)
            }
            if controller.isPaused { pauseOverlay.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.isPaused)
        .animation(.spring(duration: 0.4), value: zoneBanner)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: controller.zone) { _, z in
            zoneBanner = "Poziom \(controller.level): \(z.title)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { zoneBanner = nil }
        }
        .onChange(of: controller.session?.isFinished) { _, finished in
            if finished == true, !demo {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { router.showSummary() }
            }
        }
        .onDisappear { if demo { controller.leaveGame() } }
    }

    // MARK: HUD

    private func hud(trailing: some View) -> some View {
        HStack(spacing: 8) {
            HUDPill(text: "\(controller.coins)", symbol: "circle.fill", color: Theme.gold)
            HUDPill(text: "Poz. \(controller.level)", symbol: "star.fill", color: Theme.teal)
            Spacer()
            trailing
            Button { controller.setPaused(true) } label: {
                Image(systemName: "pause.fill").font(.title3.bold()).foregroundStyle(.white)
                    .frame(width: 48, height: 48).background(Circle().fill(Theme.ink.opacity(0.65)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1.5))
            }.accessibilityLabel("Pauza")
        }.padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: Demo

    private var demoLayer: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        guard !swipeFired, !controller.isPaused else { return }
                        let dx = v.translation.width, dy = v.translation.height
                        swipeFired = true
                        if abs(dx) > abs(dy) { controller.perform(dx < 0 ? .moveLeft : .moveRight) }
                        else { controller.perform(dy < 0 ? .jump : .slide) }
                    }
                    .onEnded { _ in swipeFired = false })
            VStack {
                hud(trailing: EmptyView())
                Text("Próba bez zegarka: przesuwaj palcem. Kucanie: przytrzymaj przycisk.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(10).background(Capsule().fill(Theme.ink.opacity(0.55))).padding(.top, 6)
                Spacer()
                HStack {
                    Spacer()
                    Circle().fill(crouchHeld ? Theme.orange : Theme.indigo)
                        .frame(width: 92, height: 92)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 3))
                        .overlay(VStack { Image(systemName: "arrow.down.to.line"); Text("Kucaj").font(.caption.bold()) }.foregroundStyle(.white))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in if !crouchHeld, !controller.isPaused { crouchHeld = true; controller.perform(.crouchBegan) } }
                            .onEnded { _ in crouchHeld = false; controller.perform(.crouchEnded) })
                        .padding(24)
                }
            }
        }
    }

    // MARK: Sesja ćwiczeń

    private var exerciseLayer: some View {
        let s = controller.session
        return VStack(spacing: 10) {
            hud(trailing: Text("\(s?.repetitions ?? 0) / \(s?.config.plannedReps ?? 0)")
                .font(.game(20)).monospacedDigit().foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(Theme.indigo))
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2)).accessibilityLabel("Powtórzenia"))
            if let limit = s?.config.timeLimitSeconds, limit > 0, let s {
                ProgressView(value: min(1, s.activeSeconds / Double(limit)))
                    .tint(Theme.teal).padding(.horizontal, 20)
                    .accessibilityLabel("Pozostały czas sesji")
            }
            if let phase = s?.phase {
                switch phase {
                case .running: promptCard(s?.prompt)
                case .connectionLost: overlayCard(title: "Utracono połączenie z zegarkiem",
                                                  text: "Gra jest wstrzymana. Zaliczone powtórzenia są zachowane. Otwórz aplikację na zegarku.", showCalibrate: false)
                case .awaitingCalibration: overlayCard(title: "Połączenie wróciło",
                                                       text: "Ustaw pozycję neutralną przed wznowieniem.", showCalibrate: true)
                case .finished(let completed): overlayCard(title: completed ? "Sesja ukończona!" : "Sesja zakończona", text: "Przechodzę do podsumowania…", showCalibrate: false)
                case .ready: EmptyView()
                }
            }
            Spacer()
            #if DEBUG
            if let p = s?.prompt, case .running = s?.phase, let s { debugButtons(p, s).padding(.bottom, 8) }
            #endif
        }
    }

    private func promptCard(_ a: ExerciseAction?) -> some View {
        VStack(spacing: 6) {
            if let a {
                Image(systemName: a.symbolName).font(.system(size: 76)).foregroundStyle(Theme.gold)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                    .symbolEffect(.pulse, options: .repeating)
                Text(a.title).font(.game(26)).foregroundStyle(.white)
                Text(a.hint).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center)
            }
        }
        .padding(16).frame(maxWidth: 330)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.ink.opacity(0.62)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 2))
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func overlayCard(title: String, text: String, showCalibrate: Bool) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.game(22)).multilineTextAlignment(.center)
            Text(text).multilineTextAlignment(.center)
            if showCalibrate || controller.connectivity.isReachable {
                if controller.calibration == .waiting { ProgressView("Trzymaj nieruchomo…") }
                else {
                    Button("Ustaw pozycję neutralną") { controller.requestCalibration() }.buttonStyle(GameButtonStyle(color: Theme.indigo, compact: true))
                    if case .failed(let m) = controller.calibration { Text(m).font(.footnote).foregroundStyle(Theme.coral) }
                }
            }
        }
        .padding(20).frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.regularMaterial))
    }

    // MARK: Pauza

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("Pauza").font(.game(40)).foregroundStyle(.white)
                Text("Odpocznij. Czas nie płynie, a ruchy są ignorowane.").font(.callout).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                Button { controller.setPaused(false) } label: { Label("Wznów", systemImage: "play.fill") }
                    .buttonStyle(GameButtonStyle(color: Theme.teal))
                Button {
                    if demo { controller.setPaused(false); router.home() } else { controller.setPaused(false); controller.stopExercise() }
                } label: { Label(demo ? "Wyjdź" : "Zakończ sesję", systemImage: "xmark") }
                    .buttonStyle(GameButtonStyle(color: Theme.coral, compact: true))
            }.padding(28).frame(maxWidth: 360)
        }
    }

    #if DEBUG
    /// Tylko do testów na symulatorze: wstrzykuje zdarzenia tak, jakby przyszły z zegarka.
    private func debugButtons(_ p: ExerciseAction, _ s: ExerciseSession) -> some View {
        Button("DEBUG: wykonaj") {
            let id = s.nextRepetitionID
            let now = Date()
            if p == .crouch || p == .legRaise {
                controller.handleEvent(WatchEvent(sessionID: s.config.sessionID, repetitionID: id, phase: .started, action: p, sentAt: now))
            }
            controller.handleEvent(WatchEvent(sessionID: s.config.sessionID, repetitionID: id, phase: .completed, action: p, sentAt: now))
        }.buttonStyle(.bordered).tint(.white)
    }
    #endif
}
