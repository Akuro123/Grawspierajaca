import XCTest
@testable import RehabRunner

/// Testy detekcji opartej na orientacji (powolne, kontrolowane ruchy) na próbkach syntetycznych 50 Hz.
/// Uwaga: to NIE zastępuje testów na fizycznym zegarku (patrz README: „Co wymaga sprawdzenia na prawdziwym urządzeniu”).
extension Sim {
    /// Orientacja: najpierw obrót wokół osi przedramienia (roll), potem pochylenie (pitch, + w górę), potem odchylenie (yaw, + w prawo).
    static func attitude(pitch: Double, yawRight: Double, roll: Double) -> Quat {
        let r = Quat(axis: Vec3(0, 1, 0), angleRad: roll * .pi / 180)
        let p = Quat(axis: Vec3(1, 0, 0), angleRad: pitch * .pi / 180)
        let y = Quat(axis: Vec3(0, 0, 1), angleRad: -yawRight * .pi / 180)
        return y * p * r
    }

    mutating func pose(_ seconds: Double, pitch: Double = 0, yaw: Double = 0, roll: Double = 0, accel: Vec3 = .zero) {
        let q = Sim.attitude(pitch: pitch, yawRight: yaw, roll: roll)
        let n = Int((seconds / dt).rounded())
        for _ in 0..<n { samples.append(MotionSample(t: t, accel: accel, gravity: q.conjugate.rotate(Vec3(0, 0, -1)), attitude: q)); t += dt }
    }

    /// Płynne przejście między pozami (powolny ruch ⇒ znikome przyspieszenie).
    mutating func ramp(_ seconds: Double, from a: (p: Double, y: Double, r: Double), to b: (p: Double, y: Double, r: Double)) {
        let n = max(1, Int((seconds / dt).rounded()))
        for i in 1...n {
            let f = Double(i) / Double(n)
            let q = Sim.attitude(pitch: a.p + (b.p - a.p) * f, yawRight: a.y + (b.y - a.y) * f, roll: a.r + (b.r - a.r) * f)
            samples.append(MotionSample(t: t, accel: Vec3(0.03, 0.02, 0.03), gravity: q.conjugate.rotate(Vec3(0, 0, -1)), attitude: q)); t += dt
        }
    }
}

final class OrientationGestureTests: XCTestCase {
    private func detector(mode: GestureMode = .angle, wrist: Wrist = .left) -> GestureDetector {
        var s = MotionSettings(); s.mode = mode
        let d = GestureDetector(settings: s)
        d.setNeutral(NeutralPose(gravity: Sim.neutralG, attitude: Sim.attitude(pitch: 0, yawRight: 0, roll: 0)), wrist: wrist)
        return d
    }
    private let zero = (p: 0.0, y: 0.0, r: 0.0)

    private func slowGesture(_ target: (p: Double, y: Double, r: Double)) -> Sim {
        var sim = Sim()
        sim.pose(0.5)
        sim.ramp(1.5, from: zero, to: target)     // wolne unoszenie przez 1,5 s
        sim.pose(0.6, pitch: target.p, yaw: target.y, roll: target.r)
        sim.ramp(1.5, from: target, to: zero)
        sim.pose(1.0)
        return sim
    }

    func testSlowMovesAreRecognizedWithoutAnyAcceleration() {
        let cases: [((p: Double, y: Double, r: Double), GestureEvent)] = [
            ((35, 0, 0), .jump), ((-35, 0, 0), .slide), ((0, 35, 0), .right), ((0, -35, 0), .left)]
        for (target, expected) in cases {
            XCTAssertEqual(events(slowGesture(target), detector: detector()), [expected], "\(expected)")
        }
    }

    func testSlowGestureFiresOnceAndHoldingDoesNotRepeat() {
        var sim = Sim()
        sim.pose(0.4); sim.ramp(1.0, from: zero, to: (35, 0, 0)); sim.pose(6.0, pitch: 35)   // długie utrzymanie
        XCTAssertEqual(events(sim, detector: detector()), [.jump])
    }

    func testBriefTouchBelowHoldIsIgnored() {
        var sim = Sim()
        sim.pose(0.4); sim.pose(0.12, pitch: 40); sim.pose(1.0)
        XCTAssertEqual(events(sim, detector: detector()), [])
    }

    func testTremorAndSmallJitterAreIgnored() {
        var sim = Sim(); sim.pose(0.3)
        for i in 0..<300 {   // drżenie ±4° w obu osiach przez 6 s
            let a = sin(Double(i) * 0.9) * 4, b = cos(Double(i) * 1.3) * 4
            sim.pose(0.02, pitch: a, yaw: b, roll: sin(Double(i)) * 3)
        }
        XCTAssertEqual(events(sim, detector: detector()), [])
    }

    func testCrouchIsRollOnlyAndSlideIsPitchOnly() {
        // Obrót przedramienia przy spokojnym ramieniu → kucanie.
        var crouch = Sim(); crouch.pose(0.4); crouch.ramp(0.8, from: zero, to: (0, 0, 40)); crouch.pose(1.0, roll: 40)
        crouch.ramp(0.6, from: (0, 0, 40), to: zero); crouch.pose(0.8)
        XCTAssertEqual(events(crouch, detector: detector()), [.crouchStart, .crouchEnd])
        // Pochylenie w dół bez obrotu → ślizg, nigdy kucanie.
        XCTAssertEqual(events(slowGesture((-35, 0, 0)), detector: detector()), [.slide])
    }

    func testAmbiguousCombinedMotionIsRejected() {
        var sim = Sim(); sim.pose(0.4); sim.ramp(0.8, from: zero, to: (-35, 0, 40)); sim.pose(2.0, pitch: -35, roll: 40)
        XCTAssertEqual(events(sim, detector: detector()), [], "pochylenie i obrót naraz to nie ślizg ani kucanie")
        var diag = Sim(); diag.pose(0.4); diag.ramp(0.8, from: zero, to: (35, 35, 0)); diag.pose(2.0, pitch: 35, yaw: 35)
        XCTAssertEqual(events(diag, detector: detector()), [], "ruch po przekątnej jest odrzucany")
    }

    func testNextGestureRequiresReturnToNeutral() {
        var sim = Sim(); sim.pose(0.4)
        sim.ramp(0.8, from: zero, to: (0, 35, 0)); sim.pose(0.5, yaw: 35)
        sim.ramp(0.6, from: (0, 35, 0), to: (0, 18, 0)); sim.pose(0.8, yaw: 18)   // wraca tylko częściowo
        sim.ramp(0.6, from: (0, 18, 0), to: (35, 18, 0)); sim.pose(0.6, pitch: 35, yaw: 18)
        XCTAssertEqual(events(sim, detector: detector()), [.right], "bez powrotu do neutralnej nie ma kolejnych gestów")
    }

    func testModesSeparateSlowAndFastMovement() {
        let slow = slowGesture((35, 0, 0))
        XCTAssertEqual(events(slow, detector: detector(mode: .flick)), [], "tryb szybki ignoruje powolny ruch")
        var flick = Sim(); flick.hold(0.4); flick.burst(Vec3(0, 0, 1.2), seconds: 0.12); flick.burst(Vec3(0, 0, -1.0), seconds: 0.12); flick.hold(1.0)
        XCTAssertEqual(events(flick, detector: detector(mode: .angle)), [], "tryb kątów ignoruje samo przyspieszenie")
        XCTAssertEqual(events(flick, detector: detector(mode: .flick)), [.jump])
        XCTAssertEqual(events(slow, detector: detector(mode: .both)), [.jump])
    }

    func testSlowGyroDriftAtRestDoesNotFire() {
        var sim = Sim(); sim.pose(0.3)
        for i in 0..<1500 { sim.pose(0.02, pitch: Double(i) * 0.03 * 0.02 * 50 / 50 * 1.5, yaw: Double(i) * 0.02 * 1.0) }   // ~1,5°/s i ~1°/s przez 30 s
        XCTAssertEqual(events(sim, detector: detector()), [], "dryf neutralnej jest kompensowany")
    }

    func testReadingExposesPitchYawRoll() {
        let d = detector()
        var sim = Sim(); sim.pose(0.5, pitch: 20, yaw: -15, roll: 10)
        _ = events(sim, detector: d)
        XCTAssertEqual(d.reading.pitchDeg, 20, accuracy: 0.5)
        XCTAssertEqual(d.reading.yawDeg, -15, accuracy: 0.5)
        XCTAssertEqual(d.reading.rollDeg, 10, accuracy: 0.5)
    }

    func testCalibratorStoresAttitude() {
        var c = NeutralCalibrator()
        let q = Sim.attitude(pitch: 5, yawRight: 30, roll: 0)
        for i in 0..<60 { c.add(MotionSample(t: Double(i) * 0.02, accel: Vec3(0.01, 0, 0), gravity: Sim.neutralG, attitude: q)) }
        guard case .success(let pose) = c.finish() else { return XCTFail("kalibracja powinna się udać") }
        XCTAssertEqual(pose.attitude, q)
    }

    func testOldSavedSettingsDecodeWithoutLosingValues() throws {
        let old = #"{"lateralEnter":0.9,"upEnter":0.7,"downEnter":0.6,"exitAccel":0.15,"decisionWindow":0.12,"crouchEnterDeg":30,"crouchExitDeg":12,"crouchHold":0.4,"crouchReleaseHold":0.15,"neutralHold":0.3,"minLock":0.35}"#
        let s = try JSONDecoder().decode(MotionSettings.self, from: Data(old.utf8))
        XCTAssertEqual(s.lateralEnter, 0.9); XCTAssertEqual(s.crouchEnterDeg, 30)
        XCTAssertEqual(s.mode, .both); XCTAssertEqual(s.pitchEnterDeg, 25)
    }

    func testTelemetryAndPingRoundTrip() throws {
        let t = Telemetry(pitchDeg: 1, yawDeg: -2, rollDeg: 3, accelLateral: 0.1, accelVertical: 0.2, phase: "armed", lastGesture: nil, sentAt: Date())
        let sid = UUID()
        let d = try XCTUnwrap(Wire.encode(WatchMessage.telemetry(sessionID: sid, t)))
        XCTAssertEqual(Wire.decode(WatchMessage.self, from: d), .telemetry(sessionID: sid, t))
        let pid = UUID()
        XCTAssertEqual(Wire.decode(PhoneMessage.self, from: try XCTUnwrap(Wire.encode(PhoneMessage.ping(id: pid)))), .ping(id: pid))
        XCTAssertEqual(Wire.decode(WatchMessage.self, from: try XCTUnwrap(Wire.encode(WatchMessage.pong(id: pid)))), .pong(id: pid))
    }

    func testDifficultyMapsToGestureMode() {
        XCTAssertEqual(Difficulty.gentle.apply(to: MotionSettings()).mode, .angle)
        XCTAssertEqual(Difficulty.active.apply(to: MotionSettings()).mode, .both)
        XCTAssertLessThan(Difficulty.gentle.apply(to: MotionSettings()).pitchEnterDeg, MotionSettings().pitchEnterDeg)
    }
}
