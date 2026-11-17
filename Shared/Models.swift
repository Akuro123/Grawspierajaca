import Foundation

enum Wrist: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? "Lewa" : "Prawa" }
}

enum ExerciseProfile: String, Codable, CaseIterable, Identifiable {
    case hand, leg
    var id: String { rawValue }
    var title: String { self == .hand ? "Ręka" : "Noga" }
}

/// Akcje ćwiczenia (to, co zegarek zgłasza i co gra pokazuje jako zadanie).
enum ExerciseAction: String, Codable, CaseIterable, Identifiable, Hashable {
    case left, right, jump, slide, crouch, legRaise

    var id: String { rawValue }

    static let handActions: [ExerciseAction] = [.left, .right, .jump, .slide, .crouch]
    static func actions(for profile: ExerciseProfile) -> [ExerciseAction] {
        profile == .hand ? handActions : [.legRaise]
    }

    var title: String {
        switch self {
        case .left: return "Ruch w lewo"
        case .right: return "Ruch w prawo"
        case .jump: return "Ruch w górę"
        case .slide: return "Krótki ruch w dół"
        case .crouch: return "Przekręć i utrzymaj"
        case .legRaise: return "Ruch podudzia w siadzie"
        }
    }

    var hint: String {
        switch self {
        case .left: return "Przesuń rękę w lewo"
        case .right: return "Przesuń rękę w prawo"
        case .jump: return "Unieś rękę w górę"
        case .slide: return "Krótko opuść rękę w dół"
        case .crouch: return "Lekko przekręć przedramię, utrzymaj, potem wróć"
        case .legRaise: return "Zmień nachylenie podudzia i wróć do pozycji wyjściowej"
        }
    }

    var symbolName: String {
        switch self {
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        case .jump: return "arrow.up.circle.fill"
        case .slide: return "arrow.down.circle.fill"
        case .crouch: return "arrow.triangle.2.circlepath.circle.fill"
        case .legRaise: return "arrow.up.right.circle.fill"
        }
    }
}

/// Akcje wykonywane w grze – wspólne dla dotyku, dema i zegarka.
enum GameAction: Equatable {
    case moveLeft, moveRight, jump, slide, crouchBegan, crouchEnded
}

enum SessionMode: String, Codable { case exercise, test }
enum EventPhase: String, Codable { case started, completed }

struct SessionConfig: Codable, Equatable {
    var sessionID: UUID
    var mode: SessionMode
    var profile: ExerciseProfile
    var enabledActions: Set<ExerciseAction>
    var plannedReps: Int
    var wrist: Wrist
    var motion: MotionSettings
    var leg: LegSettings
    /// Od jakiego ID zegarek ma numerować powtórzenia (ważne przy wznowieniu sesji po restarcie aplikacji zegarka).
    var firstRepetitionID = 1
    /// Limit czasu sesji w sekundach (nil = bez limitu). Zegarek go nie używa; sesją zarządza iPhone.
    var timeLimitSeconds: Int? = nil
}

/// Jedyne dane lecące z zegarka w trakcie sesji: żadnych surowych odczytów czujnika.
struct WatchEvent: Codable, Equatable, Hashable {
    var sessionID: UUID
    var repetitionID: Int
    var phase: EventPhase
    var action: ExerciseAction
    var sentAt: Date
}

enum PhoneMessage: Codable, Equatable {
    case start(SessionConfig)
    case stop(sessionID: UUID)
    case calibrate(requestID: UUID)
    /// Pomiar opóźnienia: zegarek odpowiada `.pong` z tym samym ID.
    case ping(id: UUID)
}

/// Podgląd diagnostyczny wysyłany z zegarka ~5 Hz tylko w trybie testera.
struct Telemetry: Codable, Equatable {
    var pitchDeg: Double      // + w górę
    var yawDeg: Double        // + w prawo
    var rollDeg: Double       // obrót przedramienia (wartość bezwzględna)
    var accelLateral: Double  // g
    var accelVertical: Double // g
    var phase: String
    var lastGesture: String?
    var sentAt: Date
}

enum WatchMessage: Codable, Equatable {
    case event(WatchEvent)
    case calibrated(requestID: UUID, success: Bool, reason: String?)
    case started(sessionID: UUID)
    case rejected(sessionID: UUID, reason: String)
    case heartbeat(sessionID: UUID?)
    /// Wynik testera gestów (tryb .test) – tylko nazwa, nie jest zaliczeniem.
    case gesture(sessionID: UUID, name: String)
    case telemetry(sessionID: UUID, Telemetry)
    case pong(id: UUID)
}

enum Wire {
    static let key = "payload"
    static func encode<T: Encodable>(_ value: T) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return [key: data]
    }
    static func decode<T: Decodable>(_ type: T.Type, from dict: [String: Any]) -> T? {
        guard let data = dict[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
