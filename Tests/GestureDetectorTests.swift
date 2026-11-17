import XCTest
@testable import RehabRunner

final class GestureDetectorTests: XCTestCase {
    // Prawo = +x, góra = +z w układzie testowym (zegarek płasko).
    func testRightSwipeFiresOnceAndReturnDoesNotFireLeft() {
        var sim = Sim()
        sim.hold(0.5)
        sim.burst(Vec3(1.0, 0, 0), seconds: 0.12)       // machnięcie w prawo
        sim.burst(Vec3(-0.9, 0, 0), seconds: 0.12)      // hamowanie / powrót ręki
        sim.hold(0.2, accel: Vec3(-0.5, 0, 0))          // dalszy powrót
        sim.hold(1.0)
        XCTAssertEqual(events(sim, detector: makeDetector()), [.right])
    }

    func testLeftJumpAndSlideAreRecognized() {
        for (accel, expected) in [(Vec3(-1, 0, 0), GestureEvent.left), (Vec3(0, 0, 1.2), .jump), (Vec3(0, 0, -1.0), .slide)] {
            var sim = Sim()
            sim.hold(0.4)
            sim.burst(accel, seconds: 0.12)
            sim.burst(accel * -0.9, seconds: 0.12)
            sim.hold(1.0)
            XCTAssertEqual(events(sim, detector: makeDetector()), [expected], "\(expected)")
        }
    }

    func testSlideNeverTriggersCrouchEvenIfArmStaysRotated() {
        var sim = Sim()
        sim.hold(0.4)
        sim.burst(Vec3(0, 0, -1.0), seconds: 0.12, roll: 10)
        sim.hold(1.5, roll: 40)    // ręka zostaje obrócona długo
        let got = events(sim, detector: makeDetector())
        XCTAssertEqual(got, [.slide])
    }

    func testCrouchNeedsHoldAndEndsOnReturnToNeutral() {
        var sim = Sim()
        sim.hold(0.4)
        sim.hold(0.2, roll: 40)    // za krótko
        sim.hold(0.4, roll: 0)
        XCTAssertEqual(events(sim, detector: makeDetector()), [])

        var sim2 = Sim()
        sim2.hold(0.4)
        sim2.hold(1.0, roll: 40)   // utrzymanie
        sim2.hold(0.5, roll: 0)    // powrót
        sim2.hold(0.8)
        XCTAssertEqual(events(sim2, detector: makeDetector()), [.crouchStart, .crouchEnd])
    }

    func testCrouchHysteresisDoesNotEndBetweenThresholds() {
        var sim = Sim()
        sim.hold(0.3)
        sim.hold(0.8, roll: 40)
        sim.hold(0.6, roll: 18)    // pomiędzy progiem wejścia (25) a wyjścia (12)
        let got = events(sim, detector: makeDetector())
        XCTAssertEqual(got, [.crouchStart])
    }

    func testReturnFromCrouchDoesNotTriggerDirectionalGesture() {
        var sim = Sim()
        sim.hold(0.3)
        sim.hold(0.8, roll: 40)
        sim.hold(0.3, accel: Vec3(0, 0, 0.9), roll: 5)   // gwałtowny powrót generuje przyspieszenie
        sim.hold(1.0)
        XCTAssertEqual(events(sim, detector: makeDetector()), [.crouchStart, .crouchEnd])
    }

    func testNextActionBlockedUntilNeutral() {
        var sim = Sim()
        sim.hold(0.3)
        sim.burst(Vec3(1, 0, 0), seconds: 0.12)
        sim.hold(0.2, accel: Vec3(0.4, 0, 0))   // ręka wciąż w ruchu, drugi impuls
        sim.burst(Vec3(1, 0, 0), seconds: 0.12)
        let first = events(sim, detector: makeDetector())
        XCTAssertEqual(first, [.right])
        // Po powrocie do spoczynku kolejny gest działa.
        var sim2 = sim
        sim2.hold(1.0)
        sim2.burst(Vec3(-1, 0, 0), seconds: 0.12)
        sim2.hold(1.0)
        XCTAssertEqual(events(sim2, detector: makeDetector()), [.right, .left])
    }

    func testRightWristMirrorsLeftRight() {
        var sim = Sim()
        sim.hold(0.3); sim.burst(Vec3(1, 0, 0), seconds: 0.12); sim.hold(1.0)
        XCTAssertEqual(events(sim, detector: makeDetector(wrist: .right)), [.left])
    }

    func testThresholdsAreConfigurable() {
        var strict = MotionSettings(); strict.lateralEnter = 1.5
        var sim = Sim()
        sim.hold(0.3); sim.burst(Vec3(1, 0, 0), seconds: 0.12); sim.hold(1.0)
        XCTAssertEqual(events(sim, detector: makeDetector(settings: strict)), [])
    }

    func testNeutralCalibratorRejectsMotionAndAcceptsStillness() {
        var good = NeutralCalibrator()
        var t = 0.0
        for _ in 0..<60 { good.add(MotionSample(t: t, accel: Vec3(0.01, 0, 0), gravity: Vec3(0, 0.1, -0.99))); t += 0.02 }
        if case .failure = good.finish() { XCTFail("powinno się udać") }
        var bad = NeutralCalibrator()
        for i in 0..<60 { bad.add(MotionSample(t: t, accel: Vec3(i == 20 ? 0.8 : 0, 0, 0), gravity: Vec3(0, 0, -1))); t += 0.02 }
        XCTAssertEqual(bad.finish(), .failure(.moved))
    }
}

final class LegRepDetectorTests: XCTestCase {
    func samples(angles: [(Double, Double)]) -> [MotionSample] {
        var t = 0.0; var out: [MotionSample] = []
        for (deg, sec) in angles {
            for _ in 0..<Int(sec / 0.02) {
                out.append(MotionSample(t: t, accel: .zero, gravity: Sim.gravity(rollDeg: deg))); t += 0.02
            }
        }
        return out
    }

    func testRaiseThenReturnCountsOneRep() {
        let d = LegRepDetector(); d.setNeutral(NeutralPose(gravity: Sim.neutralG))
        let ev = samples(angles: [(0, 0.3), (45, 0.6), (0, 0.6)]).flatMap { d.process($0) }
        XCTAssertEqual(ev, [.legRaised, .legReturned])
    }

    func testHalfMovementDoesNotComplete() {
        let d = LegRepDetector(); d.setNeutral(NeutralPose(gravity: Sim.neutralG))
        let ev = samples(angles: [(0, 0.3), (45, 0.6), (20, 1.0)]).flatMap { d.process($0) }   // nie wrócił poniżej progu wyjścia
        XCTAssertEqual(ev, [.legRaised])
    }

    func testWatchEventBuilderFiltersDisabledAndPairsPhases() {
        let id = UUID()
        var b = WatchEventBuilder(sessionID: id, enabled: [.left, .crouch])
        XCTAssertNil(b.make(from: .right))
        let l = b.make(from: .left)!
        let cs = b.make(from: .crouchStart)!, ce = b.make(from: .crouchEnd)!
        XCTAssertEqual(l.repetitionID, 1)
        XCTAssertEqual(cs.repetitionID, 2); XCTAssertEqual(ce.repetitionID, 2)
        XCTAssertEqual([cs.phase, ce.phase], [.started, .completed])
        XCTAssertNil(b.make(from: .crouchEnd))   // koniec bez początku
    }
}
