import SceneKit
import UIKit
import simd

/// Scena 3D endless runnera: kamera za postacią, trzy tory, tor jazdy z kafelków Kenney, dekoracje zależne od strefy,
/// przeszkody, monety, animowana postać (RobotExpressive) i oświetlenie. Logika zostaje w `RunnerEngine`.
final class RunnerScene3D: NSObject {
    let engine: RunnerEngine
    let scene = SCNScene()
    var onSound: ((Sfx.Name) -> Void)?
    var zone: Zone = .park { didSet { if zone != oldValue { applyZone(animated: true) } } }

    // Geometria świata
    private let laneW: Float = 1.7
    private let tileLen: Float = 5.1
    private let tileCount = 20
    private var roadWidth: Float { laneW * 3 }

    // Węzły
    let cameraNode = SCNNode()
    private let ambient = SCNLight(), sun = SCNLight(), rim = SCNLight()
    private let sunNode = SCNNode(), rimNode = SCNNode()
    private let groundNode = SCNNode()
    private var roadTiles: [SCNNode] = []
    private var pavementTiles: [SCNNode] = []
    private var groundStrips: [SCNNode] = []
    private struct Slot { var node = SCNNode(); var variants: [String: SCNNode] = [:]; var shown: String? }
    private var nearSlots: [[Slot]] = [[], []]   // [lewa, prawa]
    private var farSlots: [[Slot]] = [[], []]
    private var obstacleNodes: [Int: SCNNode] = [:]
    private var coinNodes: [Int: SCNNode] = [:]
    private let world = SCNNode()

    // Postać
    private let playerRoot = SCNNode()
    private let playerTilt = SCNNode()
    private var robot: GLTFAsset?
    private var runClip: GLTFAsset.Clip?, jumpClip: GLTFAsset.Clip?, sitClip: GLTFAsset.Clip?, idleClip: GLTFAsset.Clip?
    private var runTime: Float = 0
    private var jumpW: Float = 0, sitW: Float = 0, slideW: Float = 0
    private var displayLane = 1.0
    private let blobShadow = SCNNode()
    private let dust = SCNParticleSystem()
    private var shake: Float = 0
    private var fovPulse: Float = 0
    private var hitFlash: Float = 0
    #if DEBUG
    /// Tylko do przeglądu wizualnego: zamraża pozę postaci („jump”, „slide”, „crouch”).
    var forcedPose: String?
    #endif
    private var stumble: Float = 0

    init(engine: RunnerEngine) {
        self.engine = engine
        super.init()
        buildLighting()
        buildWorld()
        buildPlayer()
        buildCamera()
        applyZone(animated: false)
    }

    // MARK: Budowa

    private func buildLighting() {
        ambient.type = .ambient
        let an = SCNNode(); an.light = ambient; scene.rootNode.addChildNode(an)
        sun.type = .directional
        sunNode.light = sun; scene.rootNode.addChildNode(sunNode)
        rim.type = .directional; rim.intensity = 350; rim.color = UIColor(red: 0.8, green: 0.9, blue: 1, alpha: 1)
        rimNode.light = rim; rimNode.eulerAngles = SCNVector3(-0.4, .pi, 0); scene.rootNode.addChildNode(rimNode)
        scene.rootNode.addChildNode(world)
    }

    private func buildWorld() {
        let g = SCNPlane(width: 600, height: 600)
        let gm = SCNMaterial(); gm.lightingModel = .constant; g.materials = [gm]
        groundNode.geometry = g; groundNode.eulerAngles.x = -.pi / 2; groundNode.position = SCNVector3(0, -0.06, -150)
        world.addChildNode(groundNode)

        for _ in 0..<tileCount {
            let r = Models.prop("city_road-straight")
            r.scale = SCNVector3(roadWidth, 1, tileLen)
            addLaneMarkings(to: r)
            world.addChildNode(r); roadTiles.append(r)
        }
        for _ in 0..<(tileCount * 2) {
            var strips: [SCNNode] = []
            for name in ["city_grass", "city_pavement"] {
                let g = Models.prop(name); g.scale = SCNVector3(10, 1, tileLen); g.position = SCNVector3(0, -0.02, 0)
                strips.append(g)
            }
            let holder = SCNNode(); strips.forEach { holder.addChildNode($0) }
            world.addChildNode(holder); groundStrips.append(holder)
            let p = Models.prop("city_pavement")
            p.scale = SCNVector3(1.5, 1, tileLen)
            world.addChildNode(p); pavementTiles.append(p)
        }
        for side in 0..<2 {
            nearSlots[side] = (0..<tileCount).map { _ in Slot() }
            farSlots[side] = (0..<(tileCount / 2)).map { _ in Slot() }
            for i in nearSlots[side].indices { world.addChildNode(nearSlots[side][i].node) }
            for i in farSlots[side].indices { world.addChildNode(farSlots[side][i].node) }
        }
        let allNames = Set(Zone.allCases.flatMap { $0.nearRow + $0.farRow })
        for side in 0..<2 {
            for i in nearSlots[side].indices {
                for n in allNames { let v = Models.prop(n); v.isHidden = true; nearSlots[side][i].node.addChildNode(v); nearSlots[side][i].variants[n] = v }
            }
            for i in farSlots[side].indices {
                for n in allNames { let v = Models.prop(n); v.isHidden = true; farSlots[side][i].node.addChildNode(v); farSlots[side][i].variants[n] = v }
            }
        }
    }

    /// Kafelek Kenney ma środkową linię dla dwóch pasów; zakrywamy ją i rysujemy linie między naszymi trzema torami.
    private func addLaneMarkings(to tile: SCNNode) {
        let sx = 1 / roadWidth, sz = 1 / tileLen   // odwrotność skali kafelka: wymiary podajemy w metrach świata
        func flat(_ w: Float, _ l: Float, _ color: UIColor, x: Float, z: Float, y: Float) {
            let plane = SCNPlane(width: CGFloat(w * sx), height: CGFloat(l * sz))
            let m = SCNMaterial(); m.diffuse.contents = color; m.lightingModel = .blinn; m.specular.contents = UIColor.black; plane.materials = [m]
            let n = SCNNode(geometry: plane); n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(x * sx, y, z * sz)
            tile.addChildNode(n)
        }
        flat(0.6, tileLen + 0.02, UIColor(red: 0.2, green: 0.2, blue: 0.225, alpha: 1), x: 0, z: 0, y: 0.056)
        for sign in [-1, 1] as [Float] {
            for k in 0..<2 {   // dwie kreski na kafelek
                flat(0.12, 1.25, UIColor(red: 0.93, green: 0.94, blue: 1, alpha: 1), x: sign * laneW / 2, z: (Float(k) - 0.5) * tileLen * 0.5, y: 0.06)
            }
        }
    }

    private func buildPlayer() {
        scene.rootNode.addChildNode(playerRoot)
        playerRoot.addChildNode(playerTilt)
        if let r = Models.load("RobotExpressive") {
            robot = r
            runClip = r.clips["running"]; jumpClip = r.clips["jump"]; sitClip = r.clips["sitting"]; idleClip = r.clips["idle"]
            let model = r.root
            let (mn, mx) = model.boundingBox
            let h = max(0.001, mx.y - mn.y)
            let s = 2.0 / h
            let holder = SCNNode()
            holder.addChildNode(model)
            holder.scale = SCNVector3(s, s, s)
            holder.position = SCNVector3(0, -mn.y * s, 0)
            holder.eulerAngles.y = Self.robotYaw
            playerTilt.addChildNode(holder)
            if let run = runClip { r.pose(run, at: 0) }
        }
        // Cień blob pod postacią
        let plane = SCNPlane(width: 1.5, height: 1.5)
        let sm = SCNMaterial(); sm.diffuse.contents = UIImage(named: "shadow"); sm.lightingModel = .constant
        sm.isDoubleSided = true; sm.blendMode = .alpha; sm.writesToDepthBuffer = false
        plane.materials = [sm]
        blobShadow.geometry = plane; blobShadow.eulerAngles.x = -.pi / 2; blobShadow.position = SCNVector3(0, 0.03, 0)
        blobShadow.renderingOrder = -1
        scene.rootNode.addChildNode(blobShadow)
        // Kurz spod stóp
        dust.birthRate = 0; dust.particleLifeSpan = 0.55; dust.particleLifeSpanVariation = 0.15
        dust.particleImage = UIImage(named: "dust"); dust.particleSize = 0.13; dust.particleSizeVariation = 0.05
        dust.particleVelocity = 1.2; dust.particleVelocityVariation = 0.8; dust.spreadingAngle = 40
        dust.emittingDirection = SCNVector3(0, 1, 1); dust.acceleration = SCNVector3(0, 0.4, 8)
        dust.particleColor = UIColor(white: 1, alpha: 0.16); dust.blendMode = .alpha
        dust.particleColorVariation = SCNVector4(0, 0, 0, 0.1)
        dust.isAffectedByGravity = false; dust.isLightingEnabled = false
        let sizeAnim = CAKeyframeAnimation(); sizeAnim.values = [0.5, 0.9, 1.2]
        let ctrl = SCNParticlePropertyController(animation: sizeAnim); dust.propertyControllers = [.size: ctrl]
        playerRoot.addParticleSystem(dust)
    }

    /// Kierunek, w którym patrzy model w pliku (RobotExpressive patrzy w +Z, kamera jest za plecami postaci).
    private static let robotYaw: Float = .pi

    private func buildCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 62; cam.zNear = 0.1; cam.zFar = 140
        cam.wantsHDR = false
        cam.wantsDepthOfField = false
        cameraNode.camera = cam
        cameraNode.position = SCNVector3(0, 2.7, 5.2)
        scene.rootNode.addChildNode(cameraNode)
        scene.fogStartDistance = 28; scene.fogEndDistance = 105; scene.fogDensityExponent = 1.4
    }

    // MARK: Strefy

    private func applyZone(animated: Bool) {
        let z = zone
        let apply = {
            self.scene.background.contents = UIImage(named: "sky_\(z.key)")
            self.scene.fogColor = z.fog
            (self.groundNode.geometry?.firstMaterial)?.diffuse.contents = z.ground
            self.ambient.color = z.ambient.0; self.ambient.intensity = z.ambient.1
            self.sun.color = z.sun.0; self.sun.intensity = z.sun.1; self.sunNode.eulerAngles = z.sun.2
            self.rim.intensity = z == .night ? 500 : 300
        }
        if animated { SCNTransaction.begin(); SCNTransaction.animationDuration = 0.8; apply(); SCNTransaction.commit() } else { apply() }
        // Poświata okien nocą/o zachodzie (wspólne materiały modeli).
        let glow = z.windowGlow
        for n in ["city_building-small-a", "city_building-small-b", "city_building-small-c", "city_building-small-d", "city_building-garage"] {
            for m in Models.materials(n) {
                m.emission.contents = glow > 0 ? m.diffuse.contents : nil
                m.emission.intensity = CGFloat(glow)
            }
        }
        let grassy = z == .park || z == .sunset
        for h in groundStrips { h.childNodes[0].isHidden = !grassy; h.childNodes[1].isHidden = grassy }
        for s in 0..<2 { for i in nearSlots[s].indices { nearSlots[s][i].shown = nil }; for i in farSlots[s].indices { farSlots[s][i].shown = nil } }
        if animated { fovPulse = 1 }
    }

    // MARK: Krok symulacji (wywoływany z CADisplayLink na głównym wątku)

    func step(_ dt: TimeInterval) {
        let d = min(dt, 0.05)
        engine.update(d)
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        render(Float(d))
        SCNTransaction.commit()
    }

    private func hash(_ a: Int, _ b: Int) -> Int {
        var h = UInt64(truncatingIfNeeded: a) &* 0x9E3779B97F4A7C15 &+ UInt64(truncatingIfNeeded: b) &* 0xBF58476D1CE4E5B9
        h ^= h >> 31; h = h &* 0x94D049BB133111EB; h ^= h >> 29
        return Int(h & 0x7FFFFFFF)
    }

    private func render(_ dt: Float) {
        let scroll = Float(engine.scroll)
        let off = scroll.truncatingRemainder(dividingBy: tileLen)
        let seg = Int(floor(scroll / tileLen))
        let baseZ = tileLen * 2

        // Droga i chodniki.
        for (i, t) in roadTiles.enumerated() {
            let z = baseZ - Float(i) * tileLen + off
            t.position = SCNVector3(0, 0, z)
            t.isHidden = false
        }
        let padX = roadWidth / 2 + 0.75
        for i in 0..<tileCount {
            let z = baseZ - Float(i) * tileLen + off
            pavementTiles[i * 2].position = SCNVector3(-padX, 0.01, z)
            pavementTiles[i * 2 + 1].position = SCNVector3(padX, 0.01, z)
            groundStrips[i * 2].position = SCNVector3(-(padX + 0.75 + 5), 0, z)
            groundStrips[i * 2 + 1].position = SCNVector3(padX + 0.75 + 5, 0, z)
        }
        // Dekoracje: pierwszy rząd.
        let nearX = roadWidth / 2 + 1.5 + 1.35
        for side in 0..<2 {
            let sx: Float = side == 0 ? -1 : 1
            for i in 0..<tileCount {
                let z = baseZ - Float(i) * tileLen + off
                let g = seg + i
                let names = zone.nearRow
                let name = names[hash(g, side + 1 + zone.rawValue * 7) % names.count]
                var slot = nearSlots[side][i]
                if slot.shown != name {
                    if let old = slot.shown { slot.variants[old]?.isHidden = true }
                    slot.variants[name]?.isHidden = false
                    slot.shown = name
                    let isTree = name.contains("grass")
                    let s: Float = isTree ? 2.7 : (name.contains("small-c") ? 2.7 : 2.6)
                    slot.node.scale = SCNVector3(s, s * (isTree ? 1.15 : 1), s)
                    slot.node.eulerAngles.y = side == 0 ? .pi / 2 : -.pi / 2   // fasada do drogi
                    nearSlots[side][i] = slot
                }
                nearSlots[side][i].node.position = SCNVector3(sx * nearX, 0, z)
            }
        }
        // Drugi rząd (tło): co dwa kafelki, większe bryły.
        let farLen = tileLen * 2
        let offFar = scroll.truncatingRemainder(dividingBy: farLen)
        let segFar = Int(floor(scroll / farLen))
        let farX = nearX + 2.6 + 3.6
        for side in 0..<2 {
            let sx: Float = side == 0 ? -1 : 1
            for i in farSlots[side].indices {
                let z = baseZ - Float(i) * farLen + offFar
                let names = zone.farRow
                let name = names[hash(segFar + i, side + 11 + zone.rawValue * 5) % names.count]
                var slot = farSlots[side][i]
                if slot.shown != name {
                    if let old = slot.shown { slot.variants[old]?.isHidden = true }
                    slot.variants[name]?.isHidden = false
                    slot.shown = name
                    let s: Float = name.contains("grass") ? 5.2 : 5.0
                    slot.node.scale = SCNVector3(s, s * (name.contains("grass") ? 1.3 : 1.0), s)
                    slot.node.eulerAngles.y = side == 0 ? .pi / 2 : -.pi / 2
                    farSlots[side][i] = slot
                }
                farSlots[side][i].node.position = SCNVector3(sx * farX, 0, z)
            }
        }

        updatePlayer(dt)
        updateObstacles()
        updateCoins(dt)
        updateCamera(dt)
        blobShadow.position = SCNVector3(playerRoot.position.x, 0.03, 0)
        let jumpH = max(0, playerRoot.position.y)
        blobShadow.scale = SCNVector3(1 - min(0.5, jumpH * 0.25), 1 - min(0.5, jumpH * 0.25), 1)
        blobShadow.opacity = CGFloat(1 - min(0.6, jumpH * 0.3))
    }

    // MARK: Postać

    private func updatePlayer(_ dt: Float) {
        let target = Double(engine.lane)
        displayLane += (target - displayLane) * min(1, Double(dt) * 11)
        let x = Float(displayLane - 1) * laneW
        var jumping = engine.isJumping, sliding = engine.isSliding, crouching = engine.isCrouching
        var jumpProgress = engine.jumpProgress
        #if DEBUG
        if let f = forcedPose { jumping = f == "jump"; sliding = f == "slide"; crouching = f == "crouch"; jumpProgress = 0.5 }
        #endif
        let jumpHeight: Float = jumping ? sin(.pi * Float(jumpProgress)) * 1.9 : 0
        playerRoot.position = SCNVector3(x, jumpHeight, 0)
        let lean = Float(target - displayLane)
        // Pochylenie w stronę zmiany toru + lekkie skręcenie.
        stumble = max(0, stumble - dt * 3)
        playerTilt.eulerAngles = SCNVector3(-stumble * 0.35, -lean * 0.45, -lean * 0.32)

        let k = min(1, dt * 14)
        let wantJump: Float = jumping ? 1 : 0
        let wantSit: Float = (crouching || sliding) ? 1 : 0
        let wantSlide: Float = sliding ? 1 : 0
        jumpW += (wantJump - jumpW) * k
        sitW += (wantSit - sitW) * min(1, dt * 12)
        slideW += (wantSlide - slideW) * k

        guard let r = robot, let run = runClip else { return }
        let moving = !engine.isPaused
        if moving {
            // Tempo kroków dopasowane do prędkości świata.
            let rate = Float(max(0.7, min(1.6, engine.speed / 10)))
            runTime += dt * rate
        }
        let rt = runTime.truncatingRemainder(dividingBy: max(0.1, run.duration))
        if !moving, let idle = idleClip {
            r.pose(idle, at: runTime.truncatingRemainder(dividingBy: max(0.1, idle.duration)))
        } else if jumpW > 0.02, let jump = jumpClip {
            let jt = Float(jumpProgress) * max(0.1, jump.duration) * 0.98
            r.pose(run, at: rt, jump, at: jt, blend: min(1, jumpW))
        } else if sitW > 0.02, let sit = sitClip {
            // Kucanie: klip „Sitting” zatrzymany tuż po przyjęciu pozycji.
            let st = sit.duration * min(1, sitW)
            r.pose(run, at: rt, sit, at: st, blend: min(1, sitW))
        } else { r.pose(run, at: rt) }

        // Ślizg: cały korpus pochylony do tyłu i obniżony.
        let slideTilt = slideW
        playerTilt.eulerAngles.x += slideTilt * 0.38
        playerTilt.position = SCNVector3(0, -0.5 * slideTilt - 0.3 * sitW * (1 - slideTilt), 0)
        dust.birthRate = (moving && !jumping) ? CGFloat(slideTilt > 0.3 ? 22 : 9) : 0
    }

    // MARK: Przeszkody i monety

    private func makeObstacle(_ o: Obstacle) -> SCNNode {
        let n = SCNNode()
        switch o.kind {
        case .blocker:
            let names = ["race_vehicle-truck-red", "race_vehicle-truck-yellow", "race_vehicle-truck-green", "race_vehicle-truck-purple", "race_vehicle-motorcycle"]
            let m = Models.prop(names[o.id % names.count])
            let s: Float = 1.15
            m.scale = SCNVector3(s, s, s)
            m.position = SCNVector3(0, 0.3 * s, 0)
            n.addChildNode(m)
        case .lowBarrier:
            // Niska zapora z klocków: trzeba przeskoczyć.
            for k in 0..<3 {
                let b = Models.prop("plat_brick")
                b.scale = SCNVector3(0.55, 0.7, 0.8)
                b.position = SCNVector3((Float(k) - 1) * 0.56, 0, 0)
                n.addChildNode(b)
            }
        case .overheadBar:
            n.addChildNode(Self.makeGantry(width: roadWidth + 0.4))
        }
        return n
    }

    /// Bramka ze znakiem „ślizg/kucnij”: słupy i belka (proste bryły z paletą Kenney) oraz wygenerowana tablica.
    private static func makeGantry(width: Float) -> SCNNode {
        let n = SCNNode()
        let metal = SCNMaterial(); metal.diffuse.contents = UIColor(red: 0.55, green: 0.6, blue: 0.7, alpha: 1); metal.lightingModel = .blinn
        let dark = SCNMaterial(); dark.diffuse.contents = UIColor(red: 0.2, green: 0.2, blue: 0.3, alpha: 1)
        for sx in [-1, 1] as [Float] {
            let post = SCNBox(width: 0.22, height: 2.9, length: 0.22, chamferRadius: 0.04); post.materials = [metal]
            let p = SCNNode(geometry: post); p.position = SCNVector3(sx * width / 2, 1.45, 0); n.addChildNode(p)
            let foot = SCNBox(width: 0.5, height: 0.14, length: 0.5, chamferRadius: 0.04); foot.materials = [dark]
            let f = SCNNode(geometry: foot); f.position = SCNVector3(sx * width / 2, 0.07, 0); n.addChildNode(f)
        }
        let sign = SCNBox(width: CGFloat(width), height: 1.05, length: 0.3, chamferRadius: 0.08)
        let face = SCNMaterial(); face.diffuse.contents = UIImage(named: "obs_gantry"); face.lightingModel = .blinn
        face.emission.contents = UIImage(named: "obs_gantry"); face.emission.intensity = 0.35
        let side = SCNMaterial(); side.diffuse.contents = UIColor(red: 0.85, green: 0.2, blue: 0.22, alpha: 1)
        sign.materials = [face, side, side, side, side, side]
        let s = SCNNode(geometry: sign); s.position = SCNVector3(0, 2.35, 0); n.addChildNode(s)
        return n
    }

    private func updateObstacles() {
        let live = Set(engine.obstacles.map(\.id))
        for (id, node) in obstacleNodes where !live.contains(id) { node.removeFromParentNode(); obstacleNodes[id] = nil }
        for o in engine.obstacles {
            let node: SCNNode
            if let n = obstacleNodes[o.id] { node = n } else { node = makeObstacle(o); world.addChildNode(node); obstacleNodes[o.id] = node }
            let x = o.kind == .overheadBar ? 0 : Float(o.lane - 1) * laneW
            node.position = SCNVector3(x, 0, -Float(o.z))
            node.opacity = o.z < -1 ? CGFloat(max(0, 1 + (Float(o.z) + 1) / 3)) : (o.z > 50 ? CGFloat(max(0, (55 - Float(o.z)) / 5)) : 1)
        }
    }

    private func updateCoins(_ dt: Float) {
        let live = Set(engine.coins.filter { !$0.collected }.map(\.id))
        for (id, node) in coinNodes where !live.contains(id) { node.removeFromParentNode(); coinNodes[id] = nil }
        let t = Float(engine.scroll)
        for c in engine.coins where !c.collected {
            let node: SCNNode
            if let n = coinNodes[c.id] { node = n } else {
                let holder = SCNNode()
                let coin = Models.prop("plat_coin")
                coin.scale = SCNVector3(1.7, 1.7, 1.7)
                coin.position = SCNVector3(0, -0.25, 0)
                holder.addChildNode(coin)
                holder.name = "coin"
                world.addChildNode(holder); coinNodes[c.id] = holder; node = holder
            }
            node.position = SCNVector3(Float(c.lane - 1) * laneW, 0.95 + sin(t * 3 + Float(c.id)) * 0.08, -Float(c.z))
            node.eulerAngles.y = t * 0.6 + Float(c.id)
        }
    }

    // MARK: Kamera

    private func updateCamera(_ dt: Float) {
        shake = max(0, shake - dt * 2.2)
        fovPulse = max(0, fovPulse - dt * 1.6)
        let px = playerRoot.position.x
        let sx = shake * 0.18 * Float.random(in: -1...1)
        let sy = shake * 0.12 * Float.random(in: -1...1)
        let jy = playerRoot.position.y * 0.35
        let target = SCNVector3(px * 0.55 + sx, 2.7 + jy + sy, 5.2)
        cameraNode.position = SCNVector3(cameraNode.position.x + (target.x - cameraNode.position.x) * min(1, dt * 8),
                                         cameraNode.position.y + (target.y - cameraNode.position.y) * min(1, dt * 10), target.z)
        cameraNode.look(at: SCNVector3(px * 0.35, 1.15 + jy * 0.5, -7), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        cameraNode.camera?.fieldOfView = CGFloat(62 + fovPulse * 8)
        // Błysk po zderzeniu: chwilowo czerwone światło otoczenia.
        hitFlash = max(0, hitFlash - dt * 3)
        if hitFlash > 0 {
            ambient.color = UIColor(red: 1, green: 0.45 + CGFloat(1 - hitFlash) * 0.4, blue: 0.45 + CGFloat(1 - hitFlash) * 0.4, alpha: 1)
            ambient.intensity = zone.ambient.1 + CGFloat(hitFlash) * 500
        } else if ambient.color as? UIColor != zone.ambient.0 { ambient.color = zone.ambient.0; ambient.intensity = zone.ambient.1 }
    }

    // MARK: Zdarzenia

    func handle(_ e: RunnerEvent) {
        switch e {
        case .collision:
            onSound?(.hit); shake = 1; hitFlash = 1; stumble = 1
            burst(at: SCNVector3(playerRoot.position.x, 1.1, 0), count: 18, color: UIColor(red: 1, green: 0.5, blue: 0.4, alpha: 1))
        case .coinCollected:
            onSound?(.coin)
            burst(at: SCNVector3(playerRoot.position.x, 1.2, -0.3), count: 14, color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
        case .jumped: onSound?(.jump)
        case .slid: onSound?(.slide)
        case .laneChanged: onSound?(.lane)
        case .crouchBegan, .crouchEnded, .obstacleCleared: break
        }
    }

    func celebrate() {
        fovPulse = 1
        burst(at: SCNVector3(playerRoot.position.x, 2.2, -1), count: 60, color: UIColor(red: 1, green: 0.9, blue: 0.4, alpha: 1), size: 0.2, speed: 6)
    }

    private func burst(at p: SCNVector3, count: Int, color: UIColor, size: CGFloat = 0.14, speed: CGFloat = 3.2) {
        let ps = SCNParticleSystem()
        ps.loops = false; ps.birthRate = CGFloat(count) * 20
        ps.particleLifeSpan = 0.55; ps.particleLifeSpanVariation = 0.2
        ps.particleImage = UIImage(named: "spark"); ps.particleSize = size; ps.particleSizeVariation = size * 0.4
        ps.particleVelocity = speed; ps.particleVelocityVariation = speed * 0.5; ps.spreadingAngle = 180
        ps.emitterShape = nil; ps.blendMode = .additive; ps.particleColor = color; ps.isLightingEnabled = false
        ps.isAffectedByGravity = false; ps.acceleration = SCNVector3(0, -2, 0)
        let holder = SCNNode(); holder.position = p
        holder.addParticleSystem(ps)
        scene.rootNode.addChildNode(holder)
        // Jedna salwa: po 50 ms emisja jest zatrzymywana (loops=false samo tego nie gwarantuje).
        holder.runAction(.sequence([.wait(duration: 0.05), .run { _ in ps.birthRate = 0 }, .wait(duration: 1.0), .removeFromParentNode()]))
    }
}
