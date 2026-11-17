import SwiftUI
import SceneKit

/// Hostuje scenę 3D gry. Krok symulacji wykonuje CADisplayLink na głównym wątku (silnik gry nie jest wielowątkowy).
struct Game3DView: UIViewRepresentable {
    let runner: RunnerScene3D

    func makeCoordinator() -> Coordinator { Coordinator(runner) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = runner.scene
        v.pointOfView = runner.cameraNode
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false   // dotyk obsługuje warstwa SwiftUI
        context.coordinator.start()
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject {
        let runner: RunnerScene3D
        private var link: CADisplayLink?
        private var last: CFTimeInterval = 0
        init(_ r: RunnerScene3D) { runner = r }
        func start() {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            l.add(to: .main, forMode: .common)
            link = l
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func tick(_ l: CADisplayLink) {
            let dt = last == 0 ? 0 : l.timestamp - last
            last = l.timestamp
            runner.step(dt)
        }
        deinit { link?.invalidate() }
    }
}

/// Postać na ekranie głównym: ten sam model 3D co w grze, w pętli „Idle” i machania.
struct HeroView3D: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.scene = context.coordinator.scene
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.isPlaying = true
        v.isUserInteractionEnabled = false
        context.coordinator.start()
        return v
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject {
        let scene = SCNScene()
        private var robot: GLTFAsset?
        private var link: CADisplayLink?
        private var t: Float = 0
        private var last: CFTimeInterval = 0
        private let holder = SCNNode()

        override init() {
            super.init()
            let amb = SCNLight(); amb.type = .ambient; amb.intensity = 700
            let an = SCNNode(); an.light = amb; scene.rootNode.addChildNode(an)
            let sun = SCNLight(); sun.type = .directional; sun.intensity = 1100
            let sn = SCNNode(); sn.light = sun; sn.eulerAngles = SCNVector3(-0.7, 0.6, 0); scene.rootNode.addChildNode(sn)
            if let r = Models.load("RobotExpressive") {
                robot = r
                let (mn, mx) = r.root.boundingBox
                let s = 3.1 / max(0.001, mx.y - mn.y)
                let inner = SCNNode(); inner.addChildNode(r.root)
                inner.scale = SCNVector3(s, s, s); inner.position = SCNVector3(0, -mn.y * s - 1.55, 0)
                holder.addChildNode(inner)
                scene.rootNode.addChildNode(holder)
            }
            let cam = SCNCamera(); cam.fieldOfView = 36
            let cn = SCNNode(); cn.camera = cam; cn.position = SCNVector3(0, 0.2, 5.4)
            scene.rootNode.addChildNode(cn)
        }
        func start() {
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
            l.add(to: .main, forMode: .common); link = l
        }
        func stop() { link?.invalidate(); link = nil }
        @objc private func tick(_ l: CADisplayLink) {
            let dt = last == 0 ? 0 : Float(l.timestamp - last); last = l.timestamp
            t += dt
            guard let r = robot else { return }
            // 4 s oddechu (Idle), potem 2,5 s machania, w pętli; krótkie mieszanie klipów.
            let cycle = t.truncatingRemainder(dividingBy: 6.5)
            if cycle < 4, let idle = r.clips["idle"] { r.pose(idle, at: cycle.truncatingRemainder(dividingBy: max(0.1, idle.duration))) }
            else if let wave = r.clips["wave"] { r.pose(wave, at: (cycle - 4).truncatingRemainder(dividingBy: max(0.1, wave.duration))) }
            holder.eulerAngles.y = sin(t * 0.5) * 0.25
        }
        deinit { link?.invalidate() }
    }
}
