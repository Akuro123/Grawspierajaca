import Foundation

/// Logika sesji ćwiczeń po stronie iPhone'a: deduplikacja zdarzeń, zadania, zaliczanie powtórzeń,
/// utrata połączenia i ponowna kalibracja. Bez UI i bez WatchConnectivity, więc w pełni testowalna.
struct ExerciseSession {
    enum Phase: Equatable {
        case ready, running, connectionLost, awaitingCalibration
        case finished(completed: Bool)
    }

    enum Outcome: Equatable {
        case staleSession
        case duplicate
        case ignored            // zdarzenie niepasujące do zadania albo sesja nieaktywna
        case started(ExerciseAction)
        case counted(total: Int, finished: Bool)
    }

    let config: SessionConfig
    private(set) var phase: Phase = .ready
    private(set) var repetitions = 0
    private(set) var activeSeconds = 0.0
    private(set) var prompt: ExerciseAction?
    private(set) var isPaused = false
    private(set) var actionCounts: [ExerciseAction: Int] = [:]
    private(set) var endedByTime = false

    private struct Key: Hashable { var rep: Int; var phase: EventPhase }
    private var seen = Set<Key>()
    private var queue: [ExerciseAction] = []
    private var lastPrompt: ExerciseAction?
    var shuffle: ([ExerciseAction]) -> [ExerciseAction] = { $0.shuffled() }

    init(config: SessionConfig) { self.config = config }

    /// Następne wolne ID powtórzenia (do wznowienia numeracji na zegarku).
    var nextRepetitionID: Int { (seen.map(\.rep).max() ?? 0) + 1 }

    var isFinished: Bool { if case .finished = phase { return true }; return false }

    mutating func start() {
        guard phase == .ready else { return }
        phase = .running
        prompt = nextPrompt()
    }

    mutating func tick(_ dt: TimeInterval) {
        guard phase == .running, !isPaused else { return }
        activeSeconds += dt
        if let limit = config.timeLimitSeconds, limit > 0, activeSeconds >= Double(limit) {
            endedByTime = true
            phase = .finished(completed: true)   // upłynął zaplanowany czas: sesja zrealizowana
            prompt = nil
        }
    }

    /// Wstrzymanie w dowolnym momencie: czas nie płynie, zdarzenia z zegarka są pomijane.
    mutating func setPaused(_ paused: Bool) {
        guard !isFinished else { return }
        isPaused = paused
    }

    mutating func receive(_ e: WatchEvent) -> Outcome {
        guard e.sessionID == config.sessionID else { return .staleSession }
        guard !isPaused else { return .ignored }
        guard seen.insert(Key(rep: e.repetitionID, phase: e.phase)).inserted else { return .duplicate }
        switch phase {
        case .ready, .finished: return .ignored
        case .running, .connectionLost, .awaitingCalibration: break
        }
        guard e.action == prompt else { return .ignored }
        switch e.phase {
        case .started:
            return .started(e.action)
        case .completed:
            // Zaliczone powtórzenia nie giną, nawet gdy zdarzenie dociera już po utracie połączenia.
            repetitions += 1
            actionCounts[e.action, default: 0] += 1
            if repetitions >= config.plannedReps {
                phase = .finished(completed: true)
                prompt = nil
                return .counted(total: repetitions, finished: true)
            }
            prompt = nextPrompt()
            return .counted(total: repetitions, finished: false)
        }
    }

    mutating func connectionChanged(connected: Bool) {
        switch (phase, connected) {
        case (.running, false), (.awaitingCalibration, false): phase = .connectionLost
        case (.connectionLost, true): phase = .awaitingCalibration
        default: break
        }
    }

    mutating func calibrationConfirmed() {
        if phase == .awaitingCalibration { phase = .running }
    }

    mutating func stop() {
        guard !isFinished else { return }
        phase = .finished(completed: repetitions >= config.plannedReps)
        prompt = nil
    }

    private mutating func nextPrompt() -> ExerciseAction? {
        let pool = config.enabledActions.sorted { $0.rawValue < $1.rawValue }
        guard !pool.isEmpty else { return nil }
        if queue.isEmpty {
            queue = shuffle(pool)
            if pool.count > 1, queue.first == lastPrompt, queue.count > 1 { queue.swapAt(0, queue.count - 1) }
        }
        let next = queue.removeFirst()
        lastPrompt = next
        return next
    }
}

/// Wykrywa utratę łączności: brak osiągalności dłużej niż okres karencji albo brak jakiejkolwiek
/// wiadomości (np. heartbeatu) dłużej niż limit podczas aktywnej sesji.
struct LinkMonitor {
    var grace: TimeInterval = 2
    var silenceTimeout: TimeInterval = 8
    private var unreachableSince: Date?
    private var lastMessage: Date?

    mutating func messageReceived(at t: Date) { lastMessage = t }
    mutating func reset(now: Date) { unreachableSince = nil; lastMessage = now }

    mutating func isConnected(now: Date, reachable: Bool) -> Bool {
        if reachable { unreachableSince = nil } else if unreachableSince == nil { unreachableSince = now }
        if let since = unreachableSince, now.timeIntervalSince(since) >= grace { return false }
        if let last = lastMessage, now.timeIntervalSince(last) >= silenceTimeout { return false }
        return true
    }
}
