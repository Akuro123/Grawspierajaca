import Foundation

/// Konfigurowalne progi detektora ruchu ręki. Przyspieszenia w g (bez grawitacji), kąty w stopniach, czasy w sekundach.
enum GestureMode: String, Codable, CaseIterable, Identifiable {
    case angle, flick, both
    var id: String { rawValue }
    var title: String { ["angle": "Kąty (powolne ruchy)", "flick": "Machnięcia (szybkie)", "both": "Oba"][rawValue]! }
}

struct MotionSettings: Codable, Equatable {
    var lateralEnter = 0.55      // próg wejścia: lewo/prawo
    var upEnter = 0.70           // próg wejścia: w górę
    var downEnter = 0.60         // próg wejścia: w dół
    var exitAccel = 0.15         // poniżej tej wartości ruch uznajemy za ustały
    var decisionWindow = 0.12    // okno, w którym wybieramy dominujący kierunek
    var crouchEnterDeg = 25.0    // próg wejścia w kucanie (obrót względem neutralnej)
    var crouchExitDeg = 12.0     // próg wyjścia z kucania (histereza)
    var crouchHold = 0.40        // jak długo trzeba utrzymać obrót
    var crouchReleaseHold = 0.15 // jak długo trzeba być poniżej progu wyjścia
    var neutralHold = 0.30       // jak długo ręka musi być w neutralnej, by odblokować kolejną akcję
    var minLock = 0.35           // minimalna blokada po akcji
    var mode: GestureMode = .both
    var pitchEnterDeg = 25.0     // pochylenie przedramienia w górę/w dół (ruch powolny)
    var yawEnterDeg = 25.0       // odchylenie w lewo/prawo (ruch powolny)
    var angleExitDeg = 10.0      // powrót w tolerancji neutralnej
    var angleHold = 0.25         // jak długo utrzymać kąt, by uznać ruch za zamierzony

    init() {}
    /// Odporne na stare zapisy: brakujące pola dostają wartości domyślne (ustawienia użytkownika nie znikają).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = MotionSettings()
        lateralEnter = try c.decodeIfPresent(Double.self, forKey: .lateralEnter) ?? def.lateralEnter
        upEnter = try c.decodeIfPresent(Double.self, forKey: .upEnter) ?? def.upEnter
        downEnter = try c.decodeIfPresent(Double.self, forKey: .downEnter) ?? def.downEnter
        exitAccel = try c.decodeIfPresent(Double.self, forKey: .exitAccel) ?? def.exitAccel
        decisionWindow = try c.decodeIfPresent(Double.self, forKey: .decisionWindow) ?? def.decisionWindow
        crouchEnterDeg = try c.decodeIfPresent(Double.self, forKey: .crouchEnterDeg) ?? def.crouchEnterDeg
        crouchExitDeg = try c.decodeIfPresent(Double.self, forKey: .crouchExitDeg) ?? def.crouchExitDeg
        crouchHold = try c.decodeIfPresent(Double.self, forKey: .crouchHold) ?? def.crouchHold
        crouchReleaseHold = try c.decodeIfPresent(Double.self, forKey: .crouchReleaseHold) ?? def.crouchReleaseHold
        neutralHold = try c.decodeIfPresent(Double.self, forKey: .neutralHold) ?? def.neutralHold
        minLock = try c.decodeIfPresent(Double.self, forKey: .minLock) ?? def.minLock
        mode = try c.decodeIfPresent(GestureMode.self, forKey: .mode) ?? def.mode
        pitchEnterDeg = try c.decodeIfPresent(Double.self, forKey: .pitchEnterDeg) ?? def.pitchEnterDeg
        yawEnterDeg = try c.decodeIfPresent(Double.self, forKey: .yawEnterDeg) ?? def.yawEnterDeg
        angleExitDeg = try c.decodeIfPresent(Double.self, forKey: .angleExitDeg) ?? def.angleExitDeg
        angleHold = try c.decodeIfPresent(Double.self, forKey: .angleHold) ?? def.angleHold
    }

    func sanitized() -> MotionSettings {
        var s = self
        s.lateralEnter = max(0.15, s.lateralEnter)
        s.upEnter = max(0.15, s.upEnter)
        s.downEnter = max(0.15, s.downEnter)
        s.exitAccel = min(max(0.03, s.exitAccel), min(s.lateralEnter, s.upEnter, s.downEnter) * 0.9)
        s.decisionWindow = max(0.02, s.decisionWindow)
        s.crouchExitDeg = max(3, s.crouchExitDeg)
        s.crouchEnterDeg = max(s.crouchEnterDeg, s.crouchExitDeg + 5)
        s.crouchHold = max(0.1, s.crouchHold)
        s.crouchReleaseHold = max(0.02, s.crouchReleaseHold)
        s.neutralHold = max(0.05, s.neutralHold)
        s.minLock = max(0, s.minLock)
        s.pitchEnterDeg = max(8, s.pitchEnterDeg); s.yawEnterDeg = max(8, s.yawEnterDeg)
        s.angleExitDeg = min(max(3, s.angleExitDeg), min(s.pitchEnterDeg, s.yawEnterDeg) - 3)
        s.angleHold = max(0.05, s.angleHold)
        return s
    }
}

/// Ruch nogi w siadzie: zmiana nachylenia podudzia → skok, powrót → pełne powtórzenie.
struct LegSettings: Codable, Equatable {
    var enterDeg = 30.0
    var exitDeg = 12.0
    var hold = 0.15
    var cooldown = 0.4

    func sanitized() -> LegSettings {
        var s = self
        s.exitDeg = max(3, s.exitDeg)
        s.enterDeg = max(s.enterDeg, s.exitDeg + 5)
        s.hold = max(0.02, s.hold)
        s.cooldown = max(0, s.cooldown)
        return s
    }
}

final class MotionSettingsStore: ObservableObject {
    @Published var motion: MotionSettings { didSet { save() } }
    @Published var leg: LegSettings { didSet { save() } }
    @Published var wrist: Wrist { didSet { save() } }
    private let defaults: UserDefaults
    private let key: String

    private struct Stored: Codable { var motion: MotionSettings; var leg: LegSettings; var wrist: Wrist }

    init(defaults: UserDefaults = .standard, key: String = "motionSettings.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            motion = s.motion; leg = s.leg; wrist = s.wrist
        } else {
            motion = MotionSettings(); leg = LegSettings(); wrist = .left
        }
    }

    private func save() {
        let s = Stored(motion: motion, leg: leg, wrist: wrist)
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }

    func resetToDefaults() { motion = MotionSettings(); leg = LegSettings() }
}
