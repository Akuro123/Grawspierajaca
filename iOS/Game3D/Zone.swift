import SceneKit
import UIKit

/// Strefa otoczenia – zmienia się wraz z poziomem. Określa niebo, mgłę, oświetlenie i zestaw dekoracji.
enum Zone: Int, CaseIterable {
    case park, city, sunset, night
    var key: String { ["park", "city", "sunset", "night"][rawValue] }
    var title: String { ["Park", "Miasto", "Zachód słońca", "Nocna ulica"][rawValue] }
    static func forLevel(_ level: Int) -> Zone { Zone(rawValue: max(0, level - 1) % Zone.allCases.count) ?? .park }

    var fog: UIColor { [UIColor(red: 0.93, green: 0.96, blue: 0.86, alpha: 1), UIColor(red: 0.75, green: 0.88, blue: 1, alpha: 1),
                        UIColor(red: 1.0, green: 0.70, blue: 0.45, alpha: 1), UIColor(red: 0.16, green: 0.20, blue: 0.43, alpha: 1)][rawValue] }
    var ground: UIColor { [UIColor(red: 0.45, green: 0.74, blue: 0.34, alpha: 1), UIColor(red: 0.50, green: 0.56, blue: 0.64, alpha: 1),
                           UIColor(red: 0.52, green: 0.38, blue: 0.62, alpha: 1), UIColor(red: 0.10, green: 0.14, blue: 0.30, alpha: 1)][rawValue] }
    var ambient: (UIColor, CGFloat) { [(UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), 650), (UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), 620),
                                       (UIColor(red: 1, green: 0.78, blue: 0.7, alpha: 1), 520), (UIColor(red: 0.45, green: 0.52, blue: 1, alpha: 1), 420)][rawValue] }
    var sun: (UIColor, CGFloat, SCNVector3) {
        [(UIColor(red: 1, green: 0.96, blue: 0.85, alpha: 1), 1100, SCNVector3(-0.9, 0.5, 0)),
         (UIColor(red: 1, green: 1, blue: 0.95, alpha: 1), 1150, SCNVector3(-1.1, 0.3, 0)),
         (UIColor(red: 1, green: 0.62, blue: 0.35, alpha: 1), 1300, SCNVector3(-0.45, 0.9, 0)),
         (UIColor(red: 0.55, green: 0.65, blue: 1, alpha: 1), 650, SCNVector3(-0.9, -0.5, 0))][rawValue]
    }
    /// Dekoracje pierwszego rzędu (przy chodniku) i drugiego (tło) – nazwy modeli.
    var nearRow: [String] {
        switch self {
        case .park: return ["city_grass-trees", "city_grass-trees-tall", "city_grass-trees", "city_grass-trees-tall", "city_building-small-a", "city_grass-trees"]
        case .city: return ["city_building-small-a", "city_building-small-b", "city_building-small-c", "city_building-small-d", "city_building-garage", "city_building-small-c"]
        case .sunset: return ["city_building-small-a", "city_grass-trees-tall", "city_building-small-d", "city_building-small-c", "city_grass-trees", "city_building-small-b"]
        case .night: return ["city_building-small-a", "city_building-small-b", "city_building-small-c", "city_building-small-d", "city_building-garage"]
        }
    }
    var farRow: [String] {
        switch self {
        case .park: return ["city_grass-trees-tall", "city_grass-trees-tall", "city_building-small-c", "city_grass-trees-tall"]
        case .city, .sunset, .night: return ["city_building-small-c", "city_building-small-c", "city_building-small-d", "city_building-small-b", "city_building-small-c"]
        }
    }
    var windowGlow: Float { self == .night ? 0.55 : (self == .sunset ? 0.12 : 0) }
}
