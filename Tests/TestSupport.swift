import Foundation
@testable import RehabRunner

/// Generator syntetycznych próbek 50 Hz dla detektora (układ: zegarek płasko, ekranem do góry, 12:00 do przodu).
struct Sim {
    var t = 0.0
    let dt = 0.02
    var samples: [MotionSample] = []
    static let neutralG = Vec3(0, 0, -1)

    /// Grawitacja obrócona wokół osi przedramienia (osi y) o `rollDeg`.
    static func gravity(rollDeg: Double) -> Vec3 {
        let r = rollDeg * .pi / 180
        return Vec3(sin(r) * -1 * -1, 0, -cos(r)) // x rośnie z obrotem
    }

    mutating func hold(_ seconds: Double, accel: Vec3 = .zero, roll: Double = 0) {
        let n = Int((seconds / dt).rounded())
        for _ in 0..<n { samples.append(MotionSample(t: t, accel: accel, gravity: Sim.gravity(rollDeg: roll))); t += dt }
    }
    /// Krótki impuls przyspieszenia.
    mutating func burst(_ accel: Vec3, seconds: Double = 0.1, roll: Double = 0) { hold(seconds, accel: accel, roll: roll) }
}

func events(_ sim: Sim, detector: GestureDetector) -> [GestureEvent] {
    sim.samples.flatMap { detector.process($0) }
}

func makeDetector(wrist: Wrist = .left, settings: MotionSettings = MotionSettings()) -> GestureDetector {
    let d = GestureDetector(settings: settings)
    d.setNeutral(NeutralPose(gravity: Sim.neutralG), wrist: wrist)
    return d
}

func makeConfig(profile: ExerciseProfile = .hand, actions: Set<ExerciseAction>? = nil, planned: Int = 3) -> SessionConfig {
    SessionConfig(sessionID: UUID(), mode: .exercise, profile: profile,
                  enabledActions: actions ?? Set(ExerciseAction.actions(for: profile)),
                  plannedReps: planned, wrist: .left, motion: MotionSettings(), leg: LegSettings())
}

func completed(_ cfg: SessionConfig, _ rep: Int, _ a: ExerciseAction) -> WatchEvent {
    WatchEvent(sessionID: cfg.sessionID, repetitionID: rep, phase: .completed, action: a, sentAt: Date())
}
