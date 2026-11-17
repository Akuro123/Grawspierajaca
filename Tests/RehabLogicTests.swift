import XCTest
import SwiftData
@testable import RehabRunner

final class RehabLogicTests: XCTestCase {
    private func record(daysAgo: Int, reps: Int, completed: Bool = true, level: Int = 1, now: Date) -> ExerciseSessionRecord {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        let r = ExerciseSessionRecord(id: UUID(), profile: .hand, date: d, plannedReps: 10)
        r.detectedReps = reps; r.completed = completed; r.activeSeconds = 60; r.level = level
        return r
    }

    func testPauseStopsTimeAndIgnoresEvents() {
        let cfg = makeConfig(planned: 5)
        var s = ExerciseSession(config: cfg); s.start()
        s.setPaused(true)
        s.tick(10)
        XCTAssertEqual(s.activeSeconds, 0)
        let a = s.prompt!
        XCTAssertEqual(s.receive(completed(cfg, 1, a)), .ignored)
        XCTAssertEqual(s.repetitions, 0)
        s.setPaused(false)
        s.tick(2)
        XCTAssertEqual(s.activeSeconds, 2)
        // Zdarzenie z tym samym ID po wznowieniu nie zostało "zużyte" przez pauzę.
        if case .counted = s.receive(completed(cfg, 1, a)) {} else { XCTFail("powtórzenie powinno się zaliczyć") }
    }

    func testTimeLimitEndsSessionAsCompleted() {
        var cfg = makeConfig(planned: 50); cfg.timeLimitSeconds = 60
        var s = ExerciseSession(config: cfg); s.start()
        s.tick(59); XCTAssertFalse(s.isFinished)
        s.tick(2)
        XCTAssertEqual(s.phase, .finished(completed: true)); XCTAssertTrue(s.endedByTime)
    }

    func testActionCountsAccumulate() {
        let cfg = makeConfig(actions: [.jump], planned: 3)
        var s = ExerciseSession(config: cfg); s.start()
        _ = s.receive(completed(cfg, 1, .jump)); _ = s.receive(completed(cfg, 2, .jump))
        XCTAssertEqual(s.actionCounts[.jump], 2)
    }

    func testDifficultyNeverUsesTimePressureAndScalesThresholds() {
        let base = MotionSettings()
        XCTAssertLessThan(Difficulty.gentle.apply(to: base).lateralEnter, base.lateralEnter)
        XCTAssertGreaterThan(Difficulty.gentle.apply(to: base).crouchHold, base.crouchHold)
        XCTAssertGreaterThan(Difficulty.gentle.restBetweenPrompts, Difficulty.active.restBetweenPrompts)
        XCTAssertGreaterThanOrEqual(Difficulty.gentle.apply(to: base).exitAccel, 0.03)
    }

    func testProgressionAndStars() {
        XCTAssertEqual(Progression.level(forReps: 0), 1)
        XCTAssertEqual(Progression.level(forReps: 5), 2)
        XCTAssertEqual(Progression.stars(reps: 0, planned: 10, completed: false), 0)
        XCTAssertEqual(Progression.stars(reps: 2, planned: 10, completed: false), 1)
        XCTAssertEqual(Progression.stars(reps: 5, planned: 10, completed: false), 2)
        XCTAssertEqual(Progression.stars(reps: 10, planned: 10, completed: true), 3)
        XCTAssertEqual(Zone.forLevel(1), .park); XCTAssertEqual(Zone.forLevel(5), .park); XCTAssertEqual(Zone.forLevel(2), .city)
    }

    func testStreakDailySeriesAndRegularity() {
        let now = Date()
        let recs = [record(daysAgo: 0, reps: 5, now: now), record(daysAgo: 1, reps: 5, now: now), record(daysAgo: 2, reps: 5, now: now), record(daysAgo: 5, reps: 5, now: now)]
        XCTAssertEqual(Stats.currentStreak(recs, now: now), 3)
        XCTAssertEqual(Stats.longestStreak(recs), 3)
        let week = Stats.daily(recs, days: 7, now: now)
        XCTAssertEqual(week.count, 7); XCTAssertEqual(week.map(\.reps).reduce(0, +), 20)
        XCTAssertEqual(Stats.regularity(recs, days: 30, now: now), 4.0 / 30, accuracy: 1e-9)
    }

    func testStreakSurvivesIfTodayNotYetExercised() {
        let now = Date()
        XCTAssertEqual(Stats.currentStreak([record(daysAgo: 1, reps: 3, now: now), record(daysAgo: 2, reps: 3, now: now)], now: now), 2)
        XCTAssertEqual(Stats.currentStreak([record(daysAgo: 3, reps: 3, now: now)], now: now), 0)
    }

    func testBadges() {
        let now = Date()
        let recs = (0..<5).map { record(daysAgo: $0, reps: 25, level: 6, now: now) }
        let got = Rewards.unlocked(from: recs)
        XCTAssertTrue(["first", "five", "streak3", "reps100", "level5"].allSatisfy(got.contains))
        XCTAssertFalse(got.contains("reps500"))
    }

    func testActionCountsPersistInRecord() {
        let r = ExerciseSessionRecord(id: UUID(), profile: .hand, date: Date(), plannedReps: 5)
        r.actionCounts = [.jump: 3, .slide: 1]
        XCTAssertEqual(r.actionCounts[.jump], 3); XCTAssertEqual(r.actionCounts[.slide], 1)
    }

    @MainActor func testSwiftDataPersistsProfileAndSessions() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let c = try ModelContainer(for: ExerciseSessionRecord.self, PatientProfile.self, configurations: config)
        let p = PatientProfile(name: "Test", limb: .leftLeg)
        p.sessionMinutes = 10; p.enabledActions = [.legRaise]
        c.mainContext.insert(p)
        let r = ExerciseSessionRecord(id: UUID(), profile: .leg, date: Date(), plannedReps: 8)
        r.limbRaw = Limb.leftLeg.rawValue; r.detectedReps = 8
        c.mainContext.insert(r)
        try c.mainContext.save()
        let profiles = try c.mainContext.fetch(FetchDescriptor<PatientProfile>())
        XCTAssertEqual(profiles.first?.limb, .leftLeg); XCTAssertEqual(profiles.first?.sessionMinutes, 10)
        XCTAssertEqual(try c.mainContext.fetch(FetchDescriptor<ExerciseSessionRecord>()).first?.limb, .leftLeg)
    }

    func testLimbMapping() {
        XCTAssertEqual(Limb.leftArm.wrist, .left); XCTAssertEqual(Limb.rightLeg.wrist, .right)
        XCTAssertEqual(Limb.rightLeg.profile, .leg); XCTAssertEqual(Limb.leftArm.profile, .hand)
    }

    func testOldSessionConfigDecodesWithoutTimeLimit() throws {
        let cfg = makeConfig()
        let data = try JSONEncoder().encode(cfg)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "timeLimitSeconds")
        let back = try JSONDecoder().decode(SessionConfig.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.timeLimitSeconds)
    }
}
