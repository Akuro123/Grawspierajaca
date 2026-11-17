import Foundation

/// Jeden konfigurowalny ruch w siadzie. Zmiana nachylenia podudzia → .legRaised (skok w grze),
/// powrót do pozycji wyjściowej → .legReturned (pełne powtórzenie).
/// Wykrycie ruchu nie jest oceną poprawności techniki.
final class LegRepDetector {
    enum Phase: String { case unarmed, rest, raised, cooldown }

    var settings: LegSettings
    private(set) var phase: Phase = .unarmed
    private(set) var angleDeg = 0.0
    private var neutral: Vec3?
    private var candidateStart: TimeInterval?
    private var cooldownStart = 0.0

    init(settings: LegSettings = LegSettings()) { self.settings = settings.sanitized() }

    func setNeutral(_ pose: NeutralPose) {
        neutral = pose.gravity.normalized
        phase = .rest
        candidateStart = nil
    }

    func process(_ s: MotionSample) -> [GestureEvent] {
        guard let n = neutral else { return [] }
        let c = min(1, max(-1, s.gravity.normalized.dot(n)))
        angleDeg = acos(c) * 180 / .pi
        let st = settings
        var out: [GestureEvent] = []
        switch phase {
        case .unarmed: break
        case .rest:
            if angleDeg >= st.enterDeg {
                if let start = candidateStart {
                    if s.t - start >= st.hold { phase = .raised; candidateStart = nil; out.append(.legRaised) }
                } else { candidateStart = s.t }
            } else { candidateStart = nil }
        case .raised:
            if angleDeg <= st.exitDeg {
                if let start = candidateStart {
                    if s.t - start >= st.hold {
                        phase = .cooldown; cooldownStart = s.t; candidateStart = nil
                        out.append(.legReturned)
                    }
                } else { candidateStart = s.t }
            } else { candidateStart = nil }
        case .cooldown:
            if s.t - cooldownStart >= st.cooldown && angleDeg <= st.exitDeg { phase = .rest }
        }
        return out
    }
}
