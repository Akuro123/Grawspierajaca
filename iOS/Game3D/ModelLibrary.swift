import SceneKit
import UIKit

/// Biblioteka modeli 3D (glb) z pamięcią podręczną. Pliki pochodzą z licencjonowanych paczek – patrz Resources/LICENSES.md.
enum Models {
    nonisolated(unsafe) private static var cache: [String: GLTFAsset] = [:]

    private static func resolver(for name: String) -> (String) -> UIImage? {
        { uri in
            let base = uri.hasSuffix("colormap.png") ? (name.hasPrefix("race_") ? "colormap_race" : "colormap_city") : (uri as NSString).deletingPathExtension
            return UIImage(named: base)
        }
    }

    /// Wczytuje świeży egzemplarz (np. postać z własnym stanem animacji).
    static func load(_ name: String) -> GLTFAsset? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "glb") else { assertionFailure("brak modelu \(name)"); return nil }
        return try? GLTFAsset(url: url, textureResolver: resolver(for: name))
    }

    /// Statyczny rekwizyt: współdzieli geometrię i materiały między klonami.
    static func prop(_ name: String) -> SCNNode {
        if cache[name] == nil { cache[name] = load(name) }
        return cache[name]?.root.clone() ?? SCNNode()
    }

    /// Wszystkie materiały modelu (do globalnych zmian, np. poświata nocą).
    static func materials(_ name: String) -> [SCNMaterial] {
        if cache[name] == nil { cache[name] = load(name) }
        var out: [SCNMaterial] = []
        cache[name]?.root.enumerateHierarchy { n, _ in if let g = n.geometry { out += g.materials } }
        return out
    }
}
