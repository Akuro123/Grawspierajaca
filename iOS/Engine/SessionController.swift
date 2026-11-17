import Foundation
import SwiftData
import UIKit
import Combine

struct SessionSummary: Equatable {
    var profile: ExerciseProfile
    var planned: Int
    var detected: Int
    var activeSeconds: Double
    var completed: Bool
    var coins = 0
    var score = 0
    var level = 1
    var stars = 0
    var endedByTime = false
    var actionCounts: [ExerciseAction: Int] = [:]
    var newBadges: [Badge] = []
}

enum CalibrationState: Equatable {
    case idle, waiting, done
    case failed(String)
}

/// Łączy zegarek (WatchConnectivity), logikę sesji, grę i zapis SwiftData.
@MainActor
final class SessionController: ObservableObject {
    enum Kind { case none, exercise, demo }

    let connectivity = PhoneConnectivity()
    let settings = MotionSettingsStore()

    /// Profil pacjenta (SwiftData). Wszystkie parametry sesji pochodzą z niego.
    @Published private(set) var patient: PatientProfile?
    @Published private(set) var level = 1
    @Published private(set) var score = 0
    @Published private(set) var isPaused = false
    @Published private(set) var zone: Zone = .park
    var profile: ExerciseProfile { patient?.limb.profile ?? .hand }
    var enabledActions: Set<ExerciseAction> { patient?.enabledActions ?? Set(ExerciseAction.handActions) }
    var plannedReps: Int { patient?.plannedReps ?? 10 }
    var difficulty: Difficulty { patient?.difficulty ?? .gentle }
    @Published private(set) var calibration: CalibrationState = .idle
    @Published private(set) var testGesture: String?
    @Published private(set) var isTesting = false
    @Published private(set) var telemetry: Telemetry?
    @Published private(set) var gestureLog: [(date: Date, name: String)] = []
    @Published private(set) var telemetryAge: TimeInterval?
    @Published private(set) var rttMs: [Double] = []
    private var pingTask: Task<Void, Never>?
    private var pendingPings: [UUID: Date] = [:]
    private var lastTelemetryAt: Date?
    @Published private(set) var kind: Kind = .none
    @Published private(set) var session: ExerciseSession?
    @Published private(set) var summary: SessionSummary?
    @Published var errorMessage: String?
    @Published private(set) var coins = 0

    private(set) var engine: RunnerEngine?
    private(set) var scene: RunnerScene3D?
    var modelContext: ModelContext? { didSet { loadPatient() } }

    /// Wczytuje (lub tworzy) jedyny lokalny profil pacjenta.
    func loadPatient() {
        guard let ctx = modelContext else { return }
        if let p = try? ctx.fetch(FetchDescriptor<PatientProfile>(sortBy: [SortDescriptor(\.createdAt)])).first { patient = p }
        else { let p = PatientProfile(); ctx.insert(p); try? ctx.save(); patient = p }
        syncWristWithPatient()
    }

    /// Wywołuj po zmianie profilu (kończyna/trudność/ćwiczenia), by zapisać i odświeżyć widoki.
    func patientChanged() {
        try? modelContext?.save()
        syncWristWithPatient()
        objectWillChange.send()
    }

    private func syncWristWithPatient() { if let p = patient, settings.wrist != p.limb.wrist { settings.wrist = p.limb.wrist } }

    private var record: ExerciseSessionRecord?
    private var link = LinkMonitor()
    private var tickTask: Task<Void, Never>?
    private var nextChallengeTask: Task<Void, Never>?
    private var pendingCalibration: UUID?
    private var testSessionID: UUID?
    private var messageSinceLoss = false
    private var lastTick = Date()
    private var watchless = false
    private var settingsSink: AnyCancellable?

    init() {
        connectivity.onMessage = { [weak self] in self?.handle($0) }
        connectivity.activate()
        settingsSink = settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var watchStatusText: String {
        if !connectivity.isPaired { return "Brak sparowanego Apple Watcha" }
        if !connectivity.isWatchAppInstalled { return "Aplikacja nie jest zainstalowana na zegarku" }
        return connectivity.isReachable ? "Zegarek połączony" : "Otwórz aplikację na zegarku"
    }

    // MARK: Konfiguracja

    func toggle(_ action: ExerciseAction) {
        guard let p = patient else { return }
        var set = p.enabledActions
        if set.contains(action) { if set.count > 1 { set.remove(action) } } else { set.insert(action) }
        p.enabledActions = set
        patientChanged()
    }

    private func makeConfig(mode: SessionMode, id: UUID = UUID()) -> SessionConfig {
        SessionConfig(sessionID: id, mode: mode, profile: profile, enabledActions: enabledActions,
                      plannedReps: plannedReps, wrist: settings.wrist, motion: difficulty.apply(to: settings.motion),
                      leg: settings.leg.sanitized(),
                      timeLimitSeconds: (patient?.sessionMinutes ?? 0) > 0 ? (patient!.sessionMinutes * 60) : nil)
    }

    // MARK: Kalibracja i tester

    func requestCalibration() {
        let id = UUID()
        pendingCalibration = id
        calibration = .waiting
        if !connectivity.send(.calibrate(requestID: id)) {
            calibration = .failed("Zegarek jest nieosiągalny. Otwórz aplikację na zegarku.")
            pendingCalibration = nil
        }
    }

    func resetCalibrationState() { calibration = .idle }

    func startTest() {
        let id = UUID()
        testSessionID = id
        testGesture = nil; gestureLog = []
        if connectivity.send(.start(makeConfig(mode: .test, id: id))) { isTesting = true }
        else { errorMessage = "Zegarek jest nieosiągalny."; testSessionID = nil }
    }

    /// Co sekundę wysyła ping do zegarka (RTT/2 ≈ opóźnienie jednokierunkowe; nie wymaga zsynchronizowanych zegarów).
    func startPings() {
        pingTask?.cancel(); rttMs = []; pendingPings = [:]
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let id = UUID()
                self.pendingPings[id] = Date()
                self.connectivity.send(.ping(id: id))
                self.pendingPings = self.pendingPings.filter { Date().timeIntervalSince($0.value) < 5 }
                if let t = self.lastTelemetryAt { self.telemetryAge = Date().timeIntervalSince(t) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func stopPings() { pingTask?.cancel(); pingTask = nil }

    func stopTest() {
        if let id = testSessionID { connectivity.send(.stop(sessionID: id), requireReachable: false) }
        testSessionID = nil
        isTesting = false
        telemetry = nil
    }

    // MARK: Sesja ćwiczeń

    func beginExercise(requireWatch: Bool = true) {
        stopTest()
        let config = makeConfig(mode: .exercise)
        guard connectivity.send(.start(config)) || !requireWatch else {
            errorMessage = "Nie można wysłać startu do zegarka. Sprawdź połączenie."
            return
        }
        watchless = !requireWatch
        var s = ExerciseSession(config: config)
        s.start()
        session = s
        summary = nil
        coins = 0; level = 1; score = 0; isPaused = false; zone = .park
        kind = .exercise
        messageSinceLoss = false
        link.reset(now: Date())

        let e = RunnerEngine(mode: .prompted)
        e.speed = difficulty.worldSpeed
        engine = e
        let sc = RunnerScene3D(engine: e)
        sc.onSound = { Sfx.shared.play($0) }
        e.onEvent = { [weak sc] in sc?.handle($0) }
        scene = sc
        if let p = s.prompt { e.presentChallenge(p) }

        let r = ExerciseSessionRecord(id: config.sessionID, profile: profile, date: Date(), plannedReps: plannedReps)
        r.limbRaw = patient?.limb.rawValue ?? ""
        r.difficultyRaw = difficulty.rawValue
        r.timeLimitSeconds = config.timeLimitSeconds ?? 0
        r.patientID = patient?.id
        modelContext?.insert(r)
        record = r
        saveRecord()
        startTicking()
    }

    func stopExercise() {
        guard var s = session, !s.isFinished else { return }
        s.stop()
        session = s
        connectivity.send(.stop(sessionID: s.config.sessionID), requireReachable: false)
        finish()
    }

    private func finish() {
        guard let s = session else { return }
        tickTask?.cancel(); nextChallengeTask?.cancel()
        engine?.isPaused = false
        var completed = false
        if case .finished(let c) = s.phase { completed = c }
        let before = Rewards.unlocked(from: allRecords().filter { $0.id != s.config.sessionID })
        syncRecord()
        let after = Rewards.unlocked(from: allRecords())
        summary = SessionSummary(profile: s.config.profile, planned: s.config.plannedReps,
                                 detected: s.repetitions, activeSeconds: s.activeSeconds, completed: completed,
                                 coins: coins, score: score, level: level,
                                 stars: Progression.stars(reps: s.repetitions, planned: s.config.plannedReps, completed: completed),
                                 endedByTime: s.endedByTime, actionCounts: s.actionCounts,
                                 newBadges: Rewards.all.filter { after.contains($0.id) && !before.contains($0.id) })
        if !s.endedByTime || completed { Sfx.shared.play(completed ? .levelup : .pause) }
        if completed { connectivity.send(.stop(sessionID: s.config.sessionID), requireReachable: false) }
    }

    private func syncRecord() {
        guard let s = session, let r = record else { return }
        r.detectedReps = s.repetitions
        r.activeSeconds = s.activeSeconds
        r.coins = coins; r.score = score; r.level = level
        r.actionCounts = s.actionCounts
        if case .finished(let c) = s.phase { r.completed = c }
        saveRecord()
    }

    private func saveRecord() { try? modelContext?.save() }

    private func allRecords() -> [ExerciseSessionRecord] {
        (try? modelContext?.fetch(FetchDescriptor<ExerciseSessionRecord>())) ?? []
    }

    var isSessionFinished: Bool { session?.isFinished ?? false }

    // MARK: Zdarzenia z zegarka

    private func handle(_ message: WatchMessage) {
        link.messageReceived(at: Date())
        messageSinceLoss = true
        switch message {
        case .event(let e): handleEvent(e)
        case .calibrated(let id, let ok, let reason): handleCalibrated(id, ok, reason)
        case .rejected(let id, let reason):
            if id == session?.config.sessionID { errorMessage = "Zegarek odrzucił sesję: \(reason)"; stopExercise() }
            else if id == testSessionID { errorMessage = reason; isTesting = false }
        case .gesture(let id, let name):
            if id == testSessionID { testGesture = name; gestureLog.insert((Date(), name), at: 0); if gestureLog.count > 12 { gestureLog.removeLast() } }
        case .telemetry(let id, let t):
            if id == testSessionID { telemetry = t; lastTelemetryAt = Date(); testGesture = t.lastGesture ?? testGesture }
        case .pong(let id):
            if let sent = pendingPings.removeValue(forKey: id) {
                rttMs.append(Date().timeIntervalSince(sent) * 1000)
                if rttMs.count > 40 { rttMs.removeFirst() }
            }
        case .started, .heartbeat: break
        }
    }

    private func handleCalibrated(_ id: UUID, _ ok: Bool, _ reason: String?) {
        guard id == pendingCalibration else { return }
        pendingCalibration = nil
        calibration = ok ? .done : .failed(reason ?? "Kalibracja nie powiodła się.")
        guard ok, var s = session else { return }
        if s.phase == .connectionLost { s.connectionChanged(connected: true) }
        s.calibrationConfirmed()
        session = s
        if s.phase == .running {
            engine?.isPaused = false
            link.reset(now: Date())
            // Zegarek mógł zostać zrestartowany: przywróć sesję z kolejnym wolnym ID powtórzenia.
            var cfg = s.config
            cfg.firstRepetitionID = s.nextRepetitionID
            connectivity.send(.start(cfg))
        }
    }

    func handleEvent(_ e: WatchEvent) {
        guard var s = session else { return }
        let outcome = s.receive(e)
        session = s
        switch outcome {
        case .staleSession, .duplicate, .ignored:
            return
        case .started(let a):
            engine?.perform(a == .crouch ? .crouchBegan : .jump)
        case .counted(let total, let finished):
            coins = total
            score = Progression.score(reps: total, coins: total)
            let newLevel = Progression.level(forReps: total)
            if newLevel > level {
                level = newLevel; zone = Zone.forLevel(newLevel)
                scene?.zone = zone; scene?.celebrate(); Sfx.shared.play(.levelup)
            } else { Sfx.shared.play(.rep) }
            if let game = completionAction(e.action) { engine?.perform(game) }
            engine?.resolveChallenge()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            syncRecord()
            if finished { finish() } else { scheduleNextChallenge(for: s.prompt) }
        }
    }

    private func completionAction(_ a: ExerciseAction) -> GameAction? {
        switch a {
        case .left: return .moveLeft
        case .right: return .moveRight
        case .jump: return .jump
        case .slide: return .slide
        case .crouch: return .crouchEnded
        case .legRaise: return nil
        }
    }

    private func scheduleNextChallenge(for prompt: ExerciseAction?) {
        nextChallengeTask?.cancel()
        guard let prompt else { return }
        nextChallengeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int((self?.difficulty.restBetweenPrompts ?? 1.2) * 1000)))
            guard !Task.isCancelled, let self, let e = self.engine else { return }
            while self.isPaused && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(200)) }
            e.recenter()
            e.presentChallenge(prompt)
        }
    }

    // MARK: Pauza

    /// Wstrzymuje ćwiczenie w dowolnym momencie: świat stoi, czas nie płynie, ruchy z zegarka są pomijane.
    func setPaused(_ paused: Bool) {
        if kind == .demo { isPaused = paused; engine?.isPaused = paused; Sfx.shared.play(.pause); return }
        guard var s = session, !s.isFinished else { return }
        s.setPaused(paused)
        session = s
        isPaused = paused
        engine?.isPaused = paused || s.phase != .running
        Sfx.shared.play(.pause)
    }

    // MARK: Pętla zegara i łączność

    private func startTicking() {
        tickTask?.cancel()
        lastTick = Date()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard var s = session, kind == .exercise, !s.isFinished else { return }
        s.tick(dt)
        if s.isFinished { session = s; finish(); return }   // upłynął zaplanowany czas
        if watchless { session = s; return }
        let reachable = connectivity.isReachable
        switch s.phase {
        case .running, .awaitingCalibration:
            if !link.isConnected(now: now, reachable: reachable) {
                s.connectionChanged(connected: false)
                messageSinceLoss = false
                engine?.isPaused = true
            }
        case .connectionLost:
            if reachable && messageSinceLoss {
                s.connectionChanged(connected: true)
                calibration = .idle
            }
        default: break
        }
        session = s
    }

    // MARK: Demo

    func startDemo() {
        summary = nil
        session = nil
        record = nil
        kind = .demo
        let e = RunnerEngine(mode: .free)
        engine = e
        let sc = RunnerScene3D(engine: e)
        sc.onSound = { Sfx.shared.play($0) }
        e.onEvent = { [weak self, weak sc] event in
            sc?.handle(event)
            if case .coinCollected = event, let self {
                self.coins = e.coinsCollected
                self.score = self.coins * 10
                let lv = 1 + self.coins / 12
                if lv > self.level { self.level = lv; self.zone = Zone.forLevel(lv); sc?.zone = self.zone; sc?.celebrate(); Sfx.shared.play(.levelup) }
            }
        }
        scene = sc
        coins = 0; level = 1; score = 0; zone = .park; isPaused = false
    }

    func perform(_ a: GameAction) { engine?.perform(a) }

    #if DEBUG
    func debugSetZone(_ z: Zone) { zone = z; level = z.rawValue + 1; scene?.zone = z }
    #endif

    func leaveGame() {
        isPaused = false
        tickTask?.cancel(); nextChallengeTask?.cancel()
        engine?.onEvent = nil
        engine = nil; scene = nil
        kind = .none
    }
}
