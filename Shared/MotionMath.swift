import Foundation

struct Vec3: Codable, Equatable {
    var x: Double, y: Double, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    static let zero = Vec3(0, 0, 0)
    func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    func cross(_ o: Vec3) -> Vec3 { Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x) }
    var length: Double { dot(self).squareRoot() }
    var normalized: Vec3 { let l = length; return l > 1e-9 ? self * (1 / l) : self }
    static func * (v: Vec3, k: Double) -> Vec3 { Vec3(v.x * k, v.y * k, v.z * k) }
    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
}

/// Kwaternion orientacji urządzenia względem układu odniesienia z osią Z w górę (CMAttitudeReferenceFrame.xArbitraryZVertical).
struct Quat: Codable, Equatable {
    var w: Double, x: Double, y: Double, z: Double
    init(w: Double, x: Double, y: Double, z: Double) { self.w = w; self.x = x; self.y = y; self.z = z }
    init(axis: Vec3, angleRad: Double) {
        let a = axis.normalized, h = angleRad / 2, s = sin(h)
        self.init(w: cos(h), x: a.x * s, y: a.y * s, z: a.z * s)
    }
    static let identity = Quat(w: 1, x: 0, y: 0, z: 0)
    static func * (a: Quat, b: Quat) -> Quat {
        Quat(w: a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z, x: a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
             y: a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x, z: a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w)
    }
    var conjugate: Quat { Quat(w: w, x: -x, y: -y, z: -z) }
    /// Obrót wektora z układu urządzenia do układu odniesienia.
    func rotate(_ v: Vec3) -> Vec3 {
        let p = Quat(w: 0, x: v.x, y: v.y, z: v.z)
        let r = self * p * conjugate
        return Vec3(r.x, r.y, r.z)
    }
}

/// Jedna próbka ruchu: przyspieszenie użytkownika (bez grawitacji, w g), wektor grawitacji w układzie zegarka
/// oraz (opcjonalnie) orientacja. Orientacja pozwala wykrywać powolne, kontrolowane ruchy, których przyspieszenie jest małe.
struct MotionSample: Equatable {
    var t: TimeInterval
    var accel: Vec3
    var gravity: Vec3
    var attitude: Quat? = nil
}

struct NeutralPose: Codable, Equatable {
    var gravity: Vec3
    var attitude: Quat? = nil
}

enum CalibrationFailure: Error, Equatable {
    case tooFewSamples
    case moved
    var message: String {
        switch self {
        case .tooFewSamples: return "Za mało danych. Spróbuj jeszcze raz."
        case .moved: return "Ręka się poruszyła. Trzymaj ją nieruchomo."
        }
    }
}

/// Zbiera próbki w bezruchu i uśrednia grawitację jako pozycję neutralną.
struct NeutralCalibrator {
    var maxAccel = 0.10
    var maxTiltDeg = 6.0
    var minSamples = 30
    private var samples: [MotionSample] = []
    private var sawMotion = false
    private var lastAttitude: Quat?

    mutating func add(_ s: MotionSample) {
        if s.accel.length > maxAccel { sawMotion = true }
        if let a = s.attitude { lastAttitude = a }
        samples.append(s)
    }

    func finish() -> Result<NeutralPose, CalibrationFailure> {
        guard samples.count >= minSamples else { return .failure(.tooFewSamples) }
        if sawMotion { return .failure(.moved) }
        let sum = samples.reduce(Vec3.zero) { $0 + $1.gravity.normalized }
        let mean = sum.normalized
        for s in samples {
            let c = min(1, max(-1, s.gravity.normalized.dot(mean)))
            if acos(c) * 180 / .pi > maxTiltDeg { return .failure(.moved) }
        }
        return .success(NeutralPose(gravity: mean, attitude: lastAttitude))
    }
}
