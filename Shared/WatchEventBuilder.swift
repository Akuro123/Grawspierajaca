import Foundation

/// Zamienia gesty na zdarzenia z ID sesji i powtórzenia. Filtruje wyłączone akcje.
/// Zdarzenia kucania i nogi mają dwie fazy (started/completed) z tym samym ID powtórzenia.
struct WatchEventBuilder {
    let sessionID: UUID
    var enabled: Set<ExerciseAction>
    private var nextRep = 1
    private var openRep: Int?

    init(sessionID: UUID, enabled: Set<ExerciseAction>, firstRepetitionID: Int = 1) {
        self.sessionID = sessionID
        self.enabled = enabled
        self.nextRep = firstRepetitionID
    }

    private func event(_ rep: Int, _ phase: EventPhase, _ action: ExerciseAction, _ now: Date) -> WatchEvent {
        WatchEvent(sessionID: sessionID, repetitionID: rep, phase: phase, action: action, sentAt: now)
    }

    mutating func make(from g: GestureEvent, now: Date = Date()) -> WatchEvent? {
        switch g {
        case .left: return instant(.left, now)
        case .right: return instant(.right, now)
        case .jump: return instant(.jump, now)
        case .slide: return instant(.slide, now)
        case .crouchStart: return open(.crouch, now)
        case .legRaised: return open(.legRaise, now)
        case .crouchEnd: return close(.crouch, now)
        case .legReturned: return close(.legRaise, now)
        }
    }

    private mutating func instant(_ a: ExerciseAction, _ now: Date) -> WatchEvent? {
        guard enabled.contains(a) else { return nil }
        let e = event(nextRep, .completed, a, now)
        nextRep += 1
        return e
    }

    private mutating func open(_ a: ExerciseAction, _ now: Date) -> WatchEvent? {
        guard enabled.contains(a) else { return nil }
        openRep = nextRep
        return event(nextRep, .started, a, now)
    }

    private mutating func close(_ a: ExerciseAction, _ now: Date) -> WatchEvent? {
        guard enabled.contains(a), let rep = openRep else { return nil }
        openRep = nil
        nextRep = rep + 1
        return event(rep, .completed, a, now)
    }
}
