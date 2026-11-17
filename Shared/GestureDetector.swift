import Foundation

enum GestureEvent: Equatable {
    case left, right, jump, slide, crouchStart, crouchEnd
    case legRaised, legReturned

    var name: String {
        switch self {
        case .left: return "Ruch w lewo"
        case .right: return "Ruch w prawo"
        case .jump: return "Ruch w górę"
        case .slide: return "Ślizg (ruch w dół)"
        case .crouchStart: return "Kucanie: początek"
        case .crouchEnd: return "Kucanie: koniec"
        case .legRaised: return "Noga: zmiana nachylenia"
        case .legReturned: return "Noga: powrót"
        }
    }
}

/// Układ odniesienia wyznaczony z pozycji neutralnej: góra, przód (wzdłuż przedramienia) i prawo.
struct MotionFrame {
    let up: Vec3
    let forward: Vec3
    let right: Vec3

    init(neutralGravity g: Vec3, wrist: Wrist) {
        let u = (g * -1).normalized
        func project(_ v: Vec3) -> Vec3 { v - u * v.dot(u) }
        var f = project(Vec3(0, 1, 0))
        if f.length < 0.2 { f = project(Vec3(1, 0, 0)) }
        f = f.normalized
        // Zegarek na prawym nadgarstku jest obrócony o 180° względem lewego.
        if wrist == .right { f = f * -1 }
        up = u
        forward = f
        right = f.cross(u)
    }
}

struct MotionReading: Equatable {
    var lateral = 0.0   // + prawo
    var vertical = 0.0  // + góra
    var rollDeg = 0.0   // wartość bezwzględna obrotu przedramienia względem neutralnej
    var pitchDeg = 0.0  // + przedramię w górę względem neutralnej (wymaga orientacji)
    var yawDeg = 0.0    // + w prawo względem neutralnej (wymaga orientacji)
    var hasAttitude = false
}

/// Detektor gestów ręki. Czysta logika: próbki wchodzą, zdarzenia wychodzą.
/// Zasady: ruch kierunkowy blokuje detektor do powrotu do pozycji neutralnej; kucanie wymaga
/// utrzymania obrotu bez gwałtownego ruchu; podczas kucania ruchy kierunkowe są ignorowane.
final class GestureDetector {
    enum Phase: String { case unarmed, armed, deciding, locked, crouching }

    var settings: MotionSettings
    private(set) var phase: Phase = .unarmed
    private(set) var reading = MotionReading()
    private var frame: MotionFrame?
    private var lastT: TimeInterval?

    private var decisionStart = 0.0
    private var entering: Direction = .right
    private var scores: [Direction: Double] = [:]
    private var crouchCandidateStart: TimeInterval?
    private var crouchExitStart: TimeInterval?
    private var lockSince = 0.0
    private var quietAccum = 0.0
    private var wrist: Wrist = .left
    private var neutralElevation = 0.0, neutralAzimuth = 0.0
    private var yawUsable = true
    private var angleCandidate: (dir: Direction, start: TimeInterval)?
    private var restTime = 0.0

    private enum Direction: Hashable { case left, right, up, down
        var opposite: Direction { switch self { case .left: return .right; case .right: return .left; case .up: return .down; case .down: return .up } }
    }

    init(settings: MotionSettings = MotionSettings()) { self.settings = settings.sanitized() }

    func setNeutral(_ pose: NeutralPose, wrist: Wrist) {
        frame = MotionFrame(neutralGravity: pose.gravity, wrist: wrist)
        self.wrist = wrist
        angleCandidate = nil; restTime = 0
        if let q = pose.attitude {
            let f = forearm(q)
            neutralElevation = asin(max(-1, min(1, f.z)))
            neutralAzimuth = atan2(f.y, f.x)
            // Gdy przedramię jest prawie pionowe, azimut jest niestabilny: wyłączamy ruchy w bok z orientacji.
            yawUsable = abs(f.z) < 0.85
        }
        phase = .armed
        lastT = nil
        crouchCandidateStart = nil
        crouchExitStart = nil
        quietAccum = 0
    }

    func reset() { phase = frame == nil ? .unarmed : .armed; lastT = nil; crouchCandidateStart = nil; crouchExitStart = nil; quietAccum = 0 }

    /// Oś przedramienia (kierunek palców) w układzie odniesienia. Zegarek na prawym nadgarstku bywa odwrócony.
    private func forearm(_ q: Quat) -> Vec3 { q.rotate(Vec3(0, wrist == .right ? -1 : 1, 0)) }

    func measure(_ s: MotionSample) -> MotionReading {
        guard let f = frame else { return MotionReading() }
        let gr = s.gravity.dot(f.right)
        let gu = -s.gravity.dot(f.up)
        var r = MotionReading(lateral: s.accel.dot(f.right),
                              vertical: s.accel.dot(f.up),
                              rollDeg: abs(atan2(gr, gu)) * 180 / .pi)
        if let q = s.attitude {
            let v = forearm(q)
            r.pitchDeg = (asin(max(-1, min(1, v.z))) - neutralElevation) * 180 / .pi
            if yawUsable {
                var d = atan2(v.y, v.x) - neutralAzimuth
                while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
                r.yawDeg = -d * 180 / .pi     // azymut rośnie w lewo, więc minus = w prawo
            }
            r.hasAttitude = true
        }
        return r
    }

    func process(_ s: MotionSample) -> [GestureEvent] {
        guard frame != nil else { return [] }
        let m = measure(s)
        reading = m
        let dt = lastT.map { max(0, s.t - $0) } ?? 0
        lastT = s.t
        let st = settings
        let quiet = abs(m.lateral) < st.exitAccel && abs(m.vertical) < st.exitAccel
        var out: [GestureEvent] = []

        switch phase {
        case .unarmed:
            break

        case .armed:
            adaptDrift(m, quiet: quiet, dt: dt)
            if st.mode != .flick, m.hasAttitude, let e = angleGesture(m, now: s.t) {
                out.append(e)
            } else if st.mode != .angle, let dir = crossing(m) {
                phase = .deciding
                decisionStart = s.t
                entering = dir
                scores = [:]
                crouchCandidateStart = nil
                accumulate(m)
                if let e = decideIfReady(now: s.t) { out.append(e) }
            } else {
                let gate = st.exitAccel * 2
                // Kucanie = obrót przedramienia przy spokojnym ramieniu: pochylenie/odchylenie muszą być małe (to rozróżnia je od ślizgu).
                let steady = !m.hasAttitude || (abs(m.pitchDeg) < st.pitchEnterDeg * 0.6 && abs(m.yawDeg) < st.yawEnterDeg * 0.6)
                if m.rollDeg >= st.crouchEnterDeg && abs(m.lateral) < gate && abs(m.vertical) < gate && steady {
                    if let start = crouchCandidateStart {
                        if s.t - start >= st.crouchHold {
                            phase = .crouching
                            crouchExitStart = nil
                            crouchCandidateStart = nil
                            out.append(.crouchStart)
                        }
                    } else {
                        crouchCandidateStart = s.t
                    }
                } else {
                    crouchCandidateStart = nil
                }
            }

        case .deciding:
            accumulate(m)
            if let e = decideIfReady(now: s.t) { out.append(e) }

        case .locked:
            let nearNeutral = !m.hasAttitude || st.mode == .flick || (abs(m.pitchDeg) < st.angleExitDeg && abs(m.yawDeg) < st.angleExitDeg)
            if s.t - lockSince >= st.minLock && quiet && m.rollDeg < st.crouchExitDeg && nearNeutral {
                quietAccum += dt
                if quietAccum >= st.neutralHold {
                    phase = .armed
                    quietAccum = 0
                }
            } else {
                quietAccum = 0
            }

        case .crouching:
            if m.rollDeg <= st.crouchExitDeg {
                if let start = crouchExitStart {
                    if s.t - start >= st.crouchReleaseHold {
                        out.append(.crouchEnd)
                        lock(at: s.t)
                    }
                } else {
                    crouchExitStart = s.t
                }
            } else {
                crouchExitStart = nil
            }
        }
        return out
    }

    /// Dryf żyroskopu: gdy ręka długo spoczywa blisko neutralnej, neutralne kąty powoli podążają za odczytem.
    private func adaptDrift(_ m: MotionReading, quiet: Bool, dt: TimeInterval) {
        guard m.hasAttitude, quiet, abs(m.pitchDeg) < 8, abs(m.yawDeg) < 8, m.rollDeg < settings.crouchExitDeg else { restTime = 0; return }
        restTime += dt
        guard restTime > 2 else { return }
        let k = min(1, 0.3 * dt) * .pi / 180
        neutralElevation += m.pitchDeg * k
        neutralAzimuth -= m.yawDeg * k
    }

    /// Ruch powolny: kąt pochylenia/odchylenia utrzymany przez `angleHold`, przy małym obrocie przedramienia
    /// i bez znaczącego ruchu w drugiej osi. Nie zależy od szybkości ruchu.
    private func angleGesture(_ m: MotionReading, now: TimeInterval) -> GestureEvent? {
        let st = settings
        let p = m.pitchDeg / st.pitchEnterDeg
        let y = m.yawDeg / st.yawEnterDeg
        let rollOK = m.rollDeg < st.crouchEnterDeg * 0.6
        var dir: Direction?
        if rollOK {
            if abs(p) >= 1, abs(y) < 0.6 { dir = p > 0 ? .up : .down }
            else if abs(y) >= 1, abs(p) < 0.6 { dir = y > 0 ? .right : .left }
        }
        guard let d = dir else { angleCandidate = nil; return nil }
        if let c = angleCandidate, c.dir == d {
            if now - c.start >= st.angleHold {
                angleCandidate = nil
                lock(at: now)
                switch d { case .left: return .left; case .right: return .right; case .up: return .jump; case .down: return .slide }
            }
        } else { angleCandidate = (d, now) }
        return nil
    }

    private func lock(at t: TimeInterval) {
        phase = .locked
        lockSince = t
        quietAccum = 0
        crouchCandidateStart = nil
        crouchExitStart = nil
    }

    private func crossing(_ m: MotionReading) -> Direction? {
        let st = settings
        var best: (Direction, Double)?
        func consider(_ d: Direction, _ score: Double) {
            if score >= 1, score > (best?.1 ?? 0) { best = (d, score) }
        }
        consider(.right, m.lateral / st.lateralEnter)
        consider(.left, -m.lateral / st.lateralEnter)
        consider(.up, m.vertical / st.upEnter)
        consider(.down, -m.vertical / st.downEnter)
        return best?.0
    }

    private func accumulate(_ m: MotionReading) {
        let st = settings
        func bump(_ d: Direction, _ v: Double) { scores[d] = max(scores[d] ?? 0, v) }
        bump(.right, m.lateral / st.lateralEnter)
        bump(.left, -m.lateral / st.lateralEnter)
        bump(.up, m.vertical / st.upEnter)
        bump(.down, -m.vertical / st.downEnter)
    }

    private func decideIfReady(now: TimeInterval) -> GestureEvent? {
        guard now - decisionStart >= settings.decisionWindow else { return nil }
        // Przeciwny kierunek na tej samej osi to hamowanie lub powrót ręki, nie osobny gest.
        let candidates = scores.filter { $0.value >= 1 && $0.key != entering.opposite }
        let winner = candidates.max { $0.value < $1.value }?.key ?? entering
        lock(at: now)
        switch winner {
        case .left: return .left
        case .right: return .right
        case .up: return .jump
        case .down: return .slide
        }
    }
}
