import AVFoundation

/// Efekty dźwiękowe (własne, syntezowane – patrz Tools/GenerateSounds.py). Respektuje przełącznik w ustawieniach.
@MainActor
final class Sfx {
    static let shared = Sfx()
    enum Name: String, CaseIterable { case coin, jump, slide, lane, hit, rep, levelup, tap, reward, pause }

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sfx.enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sfx.enabled") }
    }
    private var players: [Name: [AVAudioPlayer]] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for n in Name.allCases {
            guard let url = Bundle.main.url(forResource: n.rawValue, withExtension: "wav") else { continue }
            players[n] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url); p?.prepareToPlay(); return p
            }
        }
    }

    func play(_ n: Name) {
        guard enabled, let pool = players[n] else { return }
        if let p = pool.first(where: { !$0.isPlaying }) ?? pool.first { p.currentTime = 0; p.play() }
    }
}
