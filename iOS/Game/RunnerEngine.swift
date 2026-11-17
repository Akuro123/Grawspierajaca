import Foundation

enum ObstacleKind { case lowBarrier, overheadBar, blocker }

struct Obstacle: Identifiable {
    let id: Int
    var kind: ObstacleKind
    var lane: Int          // 0...2 (nie dotyczy overheadBar, który obejmuje wszystkie tory)
    var z: Double
    var held = false       // w trybie ćwiczeń czeka przed graczem
    var cleared = false    // minięty bez sprawdzania kolizji
    var checked = false
}

struct Coin: Identifiable {
    let id: Int
    var lane: Int
    var z: Double
    var autoCollect = false
    var collected = false
}

enum RunnerEvent {
    case laneChanged(Int), jumped, slid, crouchBegan, crouchEnded
    case collision, coinCollected(Int), obstacleCleared
}

/// Logika świata gry bez grafiki. Scena SpriteKit tylko go rysuje; dotyk i zegarek wywołują `perform`.
final class RunnerEngine {
    enum Mode { case free, prompted }

    static let spawnZ = 55.0
    static let holdZ = 6.0
    static let challengeZ = 28.0
    static let jumpDuration = 0.75
    static let slideDuration = 0.60

    let mode: Mode
    var speed = 12.0
    var isPaused = false
    private(set) var lane = 1
    private(set) var jumpLeft = 0.0
    private(set) var slideLeft = 0.0
    private(set) var isCrouching = false
    fileprivate(set) var obstacles: [Obstacle] = []
    private(set) var coins: [Coin] = []
    private(set) var scroll = 0.0
    private(set) var stumbles = 0
    private(set) var coinsCollected = 0
    var onEvent: ((RunnerEvent) -> Void)?

    private var nextID = 1
    private var sinceSpawn = 0.0
    private var spawnGap = 16.0
    private var rng: RandomNumberGenerator

    init(mode: Mode, rng: RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.mode = mode
        self.rng = rng
    }

    var isJumping: Bool { jumpLeft > 0 }
    var isSliding: Bool { slideLeft > 0 }
    var jumpProgress: Double { isJumping ? 1 - jumpLeft / Self.jumpDuration : 0 }

    func perform(_ a: GameAction) {
        switch a {
        case .moveLeft: setLane(lane - 1)
        case .moveRight: setLane(lane + 1)
        case .jump:
            guard !isJumping else { return }
            slideLeft = 0
            jumpLeft = Self.jumpDuration
            onEvent?(.jumped)
        case .slide:
            guard !isSliding, !isJumping else { return }
            slideLeft = Self.slideDuration
            onEvent?(.slid)
        case .crouchBegan:
            guard !isCrouching else { return }
            isCrouching = true
            onEvent?(.crouchBegan)
        case .crouchEnded:
            guard isCrouching else { return }
            isCrouching = false
            onEvent?(.crouchEnded)
        }
    }

    /// Wraca na środkowy tor (tryb ćwiczeń po każdym powtórzeniu).
    func recenter() {
        if lane != 1 { lane = 1; onEvent?(.laneChanged(1)) }
    }

    private func setLane(_ l: Int) {
        let clamped = min(2, max(0, l))
        guard clamped != lane else { return }
        lane = clamped
        onEvent?(.laneChanged(clamped))
    }

    // MARK: Tryb ćwiczeń

    func presentChallenge(_ action: ExerciseAction) {
        let kind: ObstacleKind
        switch action {
        case .left, .right: kind = .blocker
        case .jump, .legRaise: kind = .lowBarrier
        case .slide, .crouch: kind = .overheadBar
        }
        var o = Obstacle(id: newID(), kind: kind, lane: 1, z: Self.challengeZ)
        o.held = true
        obstacles.append(o)
    }

    /// Powtórzenie ukończone: przeszkoda jedzie dalej, a za nią moneta.
    func resolveChallenge() {
        for i in obstacles.indices where obstacles[i].held {
            obstacles[i].held = false
            obstacles[i].cleared = true
            coins.append(Coin(id: newID(), lane: 1, z: obstacles[i].z + 1.5, autoCollect: true))
        }
    }

    var hasHeldObstacle: Bool { obstacles.contains { $0.held } }

    // MARK: Aktualizacja

    func update(_ dt: TimeInterval) {
        guard !isPaused, dt > 0, dt < 0.5 else { return }
        scroll += speed * dt
        jumpLeft = max(0, jumpLeft - dt)
        slideLeft = max(0, slideLeft - dt)

        for i in obstacles.indices {
            let before = obstacles[i].z
            if obstacles[i].held {
                obstacles[i].z = max(Self.holdZ, before - speed * dt)
            } else {
                obstacles[i].z -= speed * dt
                if before > 0, obstacles[i].z <= 0, !obstacles[i].checked {
                    obstacles[i].checked = true
                    evaluate(obstacles[i])
                }
            }
        }
        obstacles.removeAll { $0.z < -4 }

        for i in coins.indices where !coins[i].collected {
            let before = coins[i].z
            coins[i].z -= speed * dt
            if before > 0, coins[i].z <= 0, coins[i].autoCollect || coins[i].lane == lane {
                coins[i].collected = true
                coinsCollected += 1
                onEvent?(.coinCollected(coins[i].id))
            }
        }
        coins.removeAll { $0.z < -4 || $0.collected }

        if mode == .free { spawnIfNeeded(dt) }
    }

    private func evaluate(_ o: Obstacle) {
        if o.cleared { onEvent?(.obstacleCleared); return }
        let hit: Bool
        switch o.kind {
        case .lowBarrier: hit = o.lane == lane && !isJumping
        case .overheadBar: hit = !(isSliding || isCrouching)
        case .blocker: hit = o.lane == lane
        }
        if hit { stumbles += 1; onEvent?(.collision) } else { onEvent?(.obstacleCleared) }
    }

    private func spawnIfNeeded(_ dt: TimeInterval) {
        sinceSpawn += speed * dt
        guard sinceSpawn >= spawnGap else { return }
        sinceSpawn = 0
        spawnGap = Double.random(in: 14...22, using: &rng)
        let kind: ObstacleKind = [.lowBarrier, .overheadBar, .blocker, .blocker].randomElement(using: &rng)!
        let lane = Int.random(in: 0...2, using: &rng)
        obstacles.append(Obstacle(id: newID(), kind: kind, lane: lane, z: Self.spawnZ))
        // Szlak monet na innym torze.
        let coinLane = (lane + Int.random(in: 1...2, using: &rng)) % 3
        for k in 0..<5 {
            coins.append(Coin(id: newID(), lane: coinLane, z: Self.spawnZ - 6 + Double(k) * 2.2))
        }
    }

    private func newID() -> Int { defer { nextID += 1 }; return nextID }
}

#if DEBUG
extension RunnerEngine {
    /// Tylko dla testów: podmienia listę przeszkód.
    func obstaclesForTest(_ list: [Obstacle]) { obstacles = list }
}
#endif
