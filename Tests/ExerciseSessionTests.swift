import XCTest
@testable import RehabRunner

final class ExerciseSessionTests: XCTestCase {
    private func make(_ actions: Set<ExerciseAction> = [.left], planned: Int = 3) -> (ExerciseSession, SessionConfig) {
        let cfg = makeConfig(actions: actions, planned: planned)
        var s = ExerciseSession(config: cfg)
        s.start()
        return (s, cfg)
    }

    func testDuplicateEventIsNotCountedTwice() {
        var (s, cfg) = make()
        XCTAssertEqual(s.receive(completed(cfg, 1, .left)), .counted(total: 1, finished: false))
        XCTAssertEqual(s.receive(completed(cfg, 1, .left)), .duplicate)
        XCTAssertEqual(s.repetitions, 1)
    }

    func testStaleSessionEventsAreRejected() {
        var (s, _) = make()
        let old = makeConfig()
        XCTAssertEqual(s.receive(completed(old, 1, .left)), .staleSession)
        XCTAssertEqual(s.repetitions, 0)
    }

    func testNonMatchingActionIsIgnoredWithoutPenalty() {
        var (s, cfg) = make([.left])
        XCTAssertEqual(s.receive(completed(cfg, 1, .jump)), .ignored)
        XCTAssertEqual(s.prompt, .left)
        XCTAssertEqual(s.phase, .running)
    }

    func testSessionFinishesAtPlannedCount() {
        var (s, cfg) = make([.left], planned: 2)
        _ = s.receive(completed(cfg, 1, .left))
        XCTAssertEqual(s.receive(completed(cfg, 2, .left)), .counted(total: 2, finished: true))
        XCTAssertEqual(s.phase, .finished(completed: true))
        XCTAssertEqual(s.receive(completed(cfg, 3, .left)), .ignored)
    }

    func testPromptsOnlyUseEnabledActions() {
        var (s, cfg) = make([.jump, .slide], planned: 40)
        for i in 1...30 {
            XCTAssertTrue([.jump, .slide].contains(s.prompt!))
            _ = s.receive(completed(cfg, i, s.prompt!))
        }
    }

    func testConnectionLossKeepsCountedRepsAndRequiresCalibration() {
        var (s, cfg) = make([.left], planned: 5)
        _ = s.receive(completed(cfg, 1, .left))
        s.connectionChanged(connected: false)
        XCTAssertEqual(s.phase, .connectionLost)
        s.tick(5)
        XCTAssertEqual(s.activeSeconds, 0, "czas aktywny stoi podczas przerwy")
        // Zdarzenie zakolejkowane na zegarku dociera już po utracie łączności: nie ginie.
        XCTAssertEqual(s.receive(completed(cfg, 2, .left)), .counted(total: 2, finished: false))
        s.connectionChanged(connected: true)
        XCTAssertEqual(s.phase, .awaitingCalibration)
        s.calibrationConfirmed()
        XCTAssertEqual(s.phase, .running)
        XCTAssertEqual(s.repetitions, 2)
    }

    func testCalibrationConfirmedIsIgnoredOutsideAwaiting() {
        var (s, _) = make()
        s.connectionChanged(connected: false)
        s.calibrationConfirmed()
        XCTAssertEqual(s.phase, .connectionLost)
    }

    func testEarlyStopIsNotCompleted() {
        var (s, cfg) = make([.left], planned: 3)
        _ = s.receive(completed(cfg, 1, .left))
        s.stop()
        XCTAssertEqual(s.phase, .finished(completed: false))
    }

    func testCrouchStartedDoesNotCountUntilCompleted() {
        var (s, cfg) = make([.crouch], planned: 1)
        let started = WatchEvent(sessionID: cfg.sessionID, repetitionID: 1, phase: .started, action: .crouch, sentAt: Date())
        XCTAssertEqual(s.receive(started), .started(.crouch))
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.receive(completed(cfg, 1, .crouch)), .counted(total: 1, finished: true))
    }

    func testLinkMonitorGraceAndSilence() {
        var m = LinkMonitor()
        let t0 = Date()
        m.reset(now: t0)
        XCTAssertTrue(m.isConnected(now: t0.addingTimeInterval(1), reachable: false), "krótki zanik mieści się w karencji")
        XCTAssertFalse(m.isConnected(now: t0.addingTimeInterval(3.5), reachable: false))
        var m2 = LinkMonitor(); m2.reset(now: t0)
        XCTAssertFalse(m2.isConnected(now: t0.addingTimeInterval(9), reachable: true), "cisza dłuższa niż limit")
        m2.messageReceived(at: t0.addingTimeInterval(9))
        XCTAssertTrue(m2.isConnected(now: t0.addingTimeInterval(10), reachable: true))
    }
}

final class OtherLogicTests: XCTestCase {
    func testDemoEngineCollisionsAndPasses() {
        let e = RunnerEngine(mode: .free)
        // Brak ruchu przed przeszkodą w torze gracza = kolizja.
        e.obstaclesForTest([Obstacle(id: 1, kind: .blocker, lane: 1, z: 1)])
        e.update(0.2)
        XCTAssertEqual(e.stumbles, 1)
        // Zmiana toru pozwala ominąć blokadę.
        let e2 = RunnerEngine(mode: .free)
        e2.obstaclesForTest([Obstacle(id: 1, kind: .blocker, lane: 1, z: 1)])
        e2.perform(.moveLeft); e2.update(0.2)
        XCTAssertEqual(e2.stumbles, 0)
        // Ślizg i kucanie pozwalają przejść pod belką, skok nad niską przeszkodą.
        for (action, kind, ok) in [(GameAction.slide, ObstacleKind.overheadBar, true), (.crouchBegan, .overheadBar, true),
                                   (.jump, .lowBarrier, true), (.jump, .overheadBar, false)] {
            let g = RunnerEngine(mode: .free)
            g.obstaclesForTest([Obstacle(id: 1, kind: kind, lane: 1, z: 1)])
            g.perform(action); g.update(0.2)
            XCTAssertEqual(g.stumbles == 0, ok, "\(action) vs \(kind)")
        }
    }

    func testHistoryTotalsSeparateProfiles() {
        let a = ExerciseSessionRecord(id: UUID(), profile: .hand, date: Date(), plannedReps: 5); a.detectedReps = 5
        let b = ExerciseSessionRecord(id: UUID(), profile: .hand, date: Date(), plannedReps: 5); b.detectedReps = 2
        let c = ExerciseSessionRecord(id: UUID(), profile: .leg, date: Date(), plannedReps: 5); c.detectedReps = 4
        XCTAssertEqual(HistoryTotals.totals(for: .hand, in: [a, b, c]), HistoryTotals(sessions: 2, repetitions: 7))
        XCTAssertEqual(HistoryTotals.totals(for: .leg, in: [a, b, c]), HistoryTotals(sessions: 1, repetitions: 4))
    }

    func testReminderPlan() {
        var s = ReminderSettings(); s.enabled = true; s.weekdays = [2, 6]; s.hour = 7; s.minute = 30
        let r = ReminderPlan.requests(for: s)
        XCTAssertEqual(r.map(\.components.weekday), [2, 6])
        XCTAssertEqual(r.first?.components.hour, 7)
        s.enabled = false
        XCTAssertTrue(ReminderPlan.requests(for: s).isEmpty)
    }

    func testWireRoundTrip() {
        let cfg = makeConfig()
        let d = Wire.encode(PhoneMessage.start(cfg))!
        XCTAssertEqual(Wire.decode(PhoneMessage.self, from: d), .start(cfg))
    }
}
