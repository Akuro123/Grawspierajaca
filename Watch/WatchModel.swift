import Foundation
import CoreMotion
import WatchKit
import SwiftUI

@MainActor
final class WatchModel: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    enum Mode: Equatable { case idle, calibrating, test, session }

    @Published private(set) var mode: Mode = .idle
    @Published private(set) var countdown: Int?
    @Published private(set) var lastGesture: String?
    @Published private(set) var reachable = false
    @Published private(set) var hasNeutral = false
    @Published private(set) var sentEvents = 0
    @Published private(set) var message: String?
    @Published private(set) var debugLine = ""
    let store = MotionSettingsStore(key: "watch.motionSettings.v1")

    private let link = WatchLink()
    private let motion = CMMotionManager()
    private var neutral: NeutralPose?
    private var config: SessionConfig?
    private var hand: GestureDetector?
    private var leg: LegRepDetector?
    private var builder: WatchEventBuilder?
    private var calibrator: NeutralCalibrator?
    private var calibrationTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var runtime: WKExtendedRuntimeSession?
    private var isLocalSession = false
    private var lastTelemetry: TimeInterval = 0

    override init() {
        super.init()
        link.onMessage = { [weak self] in self?.handle($0) }
        link.onReachability = { [weak self] in self?.reachable = $0 }
        link.activate()
    }

    // MARK: Wiadomości z iPhone'a

    private func handle(_ m: PhoneMessage) {
        switch m {
        case .calibrate(let id): calibrate(requestID: id)
        case .ping(let id): link.send(.pong(id: id), guaranteed: false)
        case .start(let cfg): startSession(cfg)
        case .stop(let id): if id == config?.sessionID { stopSession() }
        }
    }

    // MARK: Kalibracja

    func calibrateLocally() { calibrate(requestID: nil) }

    private func calibrate(requestID: UUID?) {
        guard mode != .calibrating else { return }
        let resumeMode = mode
        calibrationTask?.cancel()
        mode = .calibrating
        message = nil
        startMotionIfNeeded()
        calibrationTask = Task { [weak self] in
            guard let self else { return }
            for n in [2, 1] {
                self.countdown = n
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self.countdown = nil
            self.calibrator = NeutralCalibrator()
            try? await Task.sleep(for: .seconds(1.2))
            if Task.isCancelled { return }
            let result = self.calibrator?.finish() ?? .failure(.tooFewSamples)
            self.calibrator = nil
            switch result {
            case .success(let pose):
                self.neutral = pose
                self.hasNeutral = true
                self.applyNeutralToDetectors()
                WKInterfaceDevice.current().play(.success)
                self.message = "Pozycja neutralna ustawiona"
                if let id = requestID { self.link.send(.calibrated(requestID: id, success: true, reason: nil), guaranteed: false) }
            case .failure(let f):
                WKInterfaceDevice.current().play(.failure)
                self.message = f.message
                if let id = requestID { self.link.send(.calibrated(requestID: id, success: false, reason: f.message), guaranteed: false) }
            }
            self.mode = resumeMode == .calibrating ? .idle : resumeMode
            self.stopMotionIfIdle()
        }
    }

    private func applyNeutralToDetectors() {
        guard let n = neutral else { return }
        hand?.setNeutral(n, wrist: config?.wrist ?? store.wrist)
        leg?.setNeutral(n)
    }

    // MARK: Sesja i tester

    func startLocalTest() {
        var cfg = SessionConfig(sessionID: UUID(), mode: .test, profile: .hand,
                                enabledActions: Set(ExerciseAction.handActions), plannedReps: 0,
                                wrist: store.wrist, motion: store.motion, leg: store.leg)
        cfg.firstRepetitionID = 1
        startSession(cfg, local: true)
    }

    private func startSession(_ cfg: SessionConfig, local: Bool = false) {
        if cfg.sessionID == config?.sessionID, mode == .session || mode == .test { return }
        guard let n = neutral else {
            link.send(.rejected(sessionID: cfg.sessionID, reason: "Najpierw ustaw pozycję neutralną."), guaranteed: false)
            message = "Najpierw ustaw pozycję neutralną."
            return
        }
        if mode == .session || mode == .test { stopSession() }
        config = cfg
        isLocalSession = local
        lastGesture = nil
        sentEvents = 0
        if cfg.profile == .leg {
            let d = LegRepDetector(settings: cfg.leg); d.setNeutral(n); leg = d; hand = nil
        } else {
            let d = GestureDetector(settings: cfg.motion); d.setNeutral(n, wrist: cfg.wrist); hand = d; leg = nil
        }
        builder = WatchEventBuilder(sessionID: cfg.sessionID, enabled: cfg.enabledActions, firstRepetitionID: cfg.firstRepetitionID)
        mode = cfg.mode == .test ? .test : .session
        startMotionIfNeeded()
        if cfg.mode == .exercise { startRuntimeSession(); startHeartbeat() }
        if !local { link.send(.started(sessionID: cfg.sessionID), guaranteed: false) }
    }

    func stopLocally() {
        guard let cfg = config else { return }
        if mode == .session {
            link.send(.rejected(sessionID: cfg.sessionID, reason: "Zatrzymano na zegarku."), guaranteed: true)
        }
        stopSession()
    }

    private func stopSession() {
        heartbeatTask?.cancel()
        runtime?.invalidate(); runtime = nil
        hand = nil; leg = nil; builder = nil; config = nil
        mode = .idle
        stopMotionIfIdle()
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.link.send(.heartbeat(sessionID: self?.config?.sessionID), guaranteed: false)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: Czujniki

    private func startMotionIfNeeded() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let s = MotionSample(t: dm.timestamp,
                                 accel: Vec3(dm.userAcceleration.x, dm.userAcceleration.y, dm.userAcceleration.z),
                                 gravity: Vec3(dm.gravity.x, dm.gravity.y, dm.gravity.z),
                                 attitude: Quat(w: dm.attitude.quaternion.w, x: dm.attitude.quaternion.x, y: dm.attitude.quaternion.y, z: dm.attitude.quaternion.z))
            self.handle(sample: s)
        }
    }

    private func stopMotionIfIdle() {
        if mode == .idle { motion.stopDeviceMotionUpdates() }
    }

    private func handle(sample s: MotionSample) {
        if mode == .calibrating { calibrator?.add(s); return }
        guard mode == .session || mode == .test, let cfg = config else { return }
        let gestures = hand?.process(s) ?? leg?.process(s) ?? []
        if let h = hand {
            let r = h.reading
            debugLine = String(format: "↕%.0f° ↔%.0f° ⟳%.0f° %@", r.pitchDeg, r.yawDeg, r.rollDeg, h.phase.rawValue)
            if cfg.mode == .test, !isLocalSession, s.t - lastTelemetry >= 0.2 {
                lastTelemetry = s.t
                link.send(.telemetry(sessionID: cfg.sessionID, Telemetry(pitchDeg: r.pitchDeg, yawDeg: r.yawDeg, rollDeg: r.rollDeg, accelLateral: r.lateral,
                                                                       accelVertical: r.vertical, phase: h.phase.rawValue, lastGesture: lastGesture, sentAt: Date())), guaranteed: false)
            }
        } else if let l = leg { debugLine = String(format: "∠%.0f° %@", l.angleDeg, l.phase.rawValue) }
        for g in gestures {
            if cfg.mode == .test {
                lastGesture = g.name
                WKInterfaceDevice.current().play(.click)
                if !isLocalSession { link.send(.gesture(sessionID: cfg.sessionID, name: g.name), guaranteed: false) }
            } else if var b = builder, let e = b.make(from: g) {
                builder = b
                lastGesture = g.name
                sentEvents += 1
                WKInterfaceDevice.current().play(e.phase == .completed ? .success : .click)
                link.send(.event(e), guaranteed: true)
            } else if var b = builder { _ = b.make(from: g); builder = b }
        }
    }

    // MARK: WKExtendedRuntimeSession

    private func startRuntimeSession() {
        runtime?.invalidate()
        let r = WKExtendedRuntimeSession()
        r.delegate = self
        r.start()
        runtime = r
    }

    nonisolated func extendedRuntimeSessionDidStart(_ s: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSessionWillExpire(_ s: WKExtendedRuntimeSession) {}
    nonisolated func extendedRuntimeSession(_ s: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {}
}
