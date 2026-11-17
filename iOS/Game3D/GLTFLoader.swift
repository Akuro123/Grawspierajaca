import SceneKit
import UIKit
import simd

/// Minimalny loader glTF 2.0 (.glb) dla SceneKit: hierarchia węzłów, siatki z materiałami i teksturami,
/// szkielety (skinning) oraz klipy animacji węzłów. SceneKit nie czyta glTF natywnie, a Model I/O też nie.
/// Obsługuje tylko to, czego potrzebują użyte zasoby (Kenney CC0, RobotExpressive CC0).
final class GLTFAsset {
    struct TRS {
        var t: SIMD3<Float>, r: simd_quatf, s: SIMD3<Float>
    }
    final class NodeTracks {
        var t: (times: [Float], values: [SIMD3<Float>])?
        var r: (times: [Float], values: [simd_quatf])?
        var s: (times: [Float], values: [SIMD3<Float>])?
    }
    final class Clip {
        let name: String
        var duration: Float = 0
        var tracks: [Int: NodeTracks] = [:]
        init(name: String) { self.name = name }
    }

    let root = SCNNode()
    private(set) var nodes: [SCNNode] = []
    private(set) var defaults: [TRS] = []
    private(set) var clips: [String: Clip] = [:]
    var nodeByName: [String: SCNNode] = [:]

    // MARK: Wczytywanie

    enum LoadError: Error { case badFile, unsupported(String) }

    /// - Parameter textureResolver: zamienia URI obrazu z pliku (np. "Textures/colormap.png") na obraz z pakietu.
    init(url: URL, textureResolver: (String) -> UIImage?) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 20, data.prefix(4) == Data("glTF".utf8) else { throw LoadError.badFile }
        var json: [String: Any] = [:]
        var bin = Data()
        var off = 12
        while off + 8 <= data.count {
            let len = Int(data.loadLE(UInt32.self, at: off)), type = data.loadLE(UInt32.self, at: off + 4)
            let body = data.subdata(in: off + 8..<min(data.count, off + 8 + len))
            if type == 0x4E4F534A { json = (try JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:] }
            else if type == 0x004E4942 { bin = body }
            off += 8 + len
        }
        let reader = Reader(json: json, bin: bin)
        let materials = Self.makeMaterials(json, resolver: textureResolver)

        let nodeDefs = json["nodes"] as? [[String: Any]] ?? []
        nodes = nodeDefs.map { _ in SCNNode() }
        defaults = nodeDefs.map { Self.trs(of: $0) }
        for (i, d) in nodeDefs.enumerated() {
            let n = nodes[i]
            n.name = d["name"] as? String
            if let name = n.name { nodeByName[name] = n }
            let tr = defaults[i]
            n.simdPosition = tr.t; n.simdOrientation = tr.r; n.simdScale = tr.s
            if let kids = d["children"] as? [Int] { kids.forEach { n.addChildNode(nodes[$0]) } }
        }
        // Siatki (po zbudowaniu hierarchii, bo skórki odwołują się do kości).
        let meshes = json["meshes"] as? [[String: Any]] ?? []
        let skins = json["skins"] as? [[String: Any]] ?? []
        var isChild = Set<Int>()
        nodeDefs.forEach { ($0["children"] as? [Int])?.forEach { isChild.insert($0) } }
        for (i, d) in nodeDefs.enumerated() {
            guard let mi = d["mesh"] as? Int, mi < meshes.count else { continue }
            let skin = (d["skin"] as? Int).flatMap { $0 < skins.count ? skins[$0] : nil }
            for prim in meshes[mi]["primitives"] as? [[String: Any]] ?? [] {
                guard let geo = try Self.geometry(prim, reader: reader, materials: materials) else { continue }
                let holder = SCNNode(geometry: geo.geometry)
                if let skin, let w = geo.weights, let jn = geo.joints {
                    // Siatka ze skórką: przypinamy ją sztywno do dominującej kości (zamiast SCNSkinner, który źle znosi
                    // szkielet pod węzłem o skali 100). Dla dłoni robota daje to poprawny wynik.
                    let jointIdx = skin["joints"] as? [Int] ?? []
                    var sum = [Float](repeating: 0, count: jointIdx.count)
                    for v in 0..<jn.count / 4 { for k in 0..<4 where Int(jn[v * 4 + k]) < sum.count { sum[Int(jn[v * 4 + k])] += w[v * 4 + k] } }
                    let best = sum.indices.max { sum[$0] < sum[$1] } ?? 0
                    let f = skin["inverseBindMatrices"].flatMap { $0 as? Int }.map { reader.floats($0).data } ?? []
                    if best < jointIdx.count, f.count >= (best + 1) * 16 {
                        let o = best * 16
                        let m = simd_float4x4(columns: (SIMD4(f[o], f[o+1], f[o+2], f[o+3]), SIMD4(f[o+4], f[o+5], f[o+6], f[o+7]),
                                                       SIMD4(f[o+8], f[o+9], f[o+10], f[o+11]), SIMD4(f[o+12], f[o+13], f[o+14], f[o+15])))
                        holder.simdTransform = m
                        nodes[jointIdx[best]].addChildNode(holder)
                    } else { nodes[i].addChildNode(holder) }
                } else {
                    nodes[i].addChildNode(holder)
                }
            }
        }
        // Korzeń: węzły sceny.
        let scenes = json["scenes"] as? [[String: Any]] ?? []
        let rootIdx = (scenes.first?["nodes"] as? [Int]) ?? nodeDefs.indices.filter { !isChild.contains($0) }
        rootIdx.forEach { root.addChildNode(nodes[$0]) }

        // Animacje.
        for a in json["animations"] as? [[String: Any]] ?? [] {
            let clip = Clip(name: a["name"] as? String ?? "clip\(clips.count)")
            let samplers = a["samplers"] as? [[String: Any]] ?? []
            for ch in a["channels"] as? [[String: Any]] ?? [] {
                guard let si = ch["sampler"] as? Int, let tgt = ch["target"] as? [String: Any],
                      let node = tgt["node"] as? Int, let path = tgt["path"] as? String, si < samplers.count,
                      let inp = samplers[si]["input"] as? Int, let out = samplers[si]["output"] as? Int else { continue }
                let times = reader.floats(inp).data
                var vals = reader.floats(out).data
                let interp = samplers[si]["interpolation"] as? String ?? "LINEAR"
                let comps = path == "rotation" ? 4 : 3
                if interp == "CUBICSPLINE" {   // bierzemy wartości punktów (środkowa z trójki) jako przybliżenie
                    vals = stride(from: 0, to: times.count, by: 1).flatMap { k in Array(vals[(k * 3 + 1) * comps..<(k * 3 + 2) * comps]) }
                }
                guard vals.count >= times.count * comps, !times.isEmpty else { continue }
                clip.duration = max(clip.duration, times.last ?? 0)
                let tracks = clip.tracks[node] ?? NodeTracks()
                clip.tracks[node] = tracks
                switch path {
                case "translation": tracks.t = (times, (0..<times.count).map { SIMD3(vals[$0*3], vals[$0*3+1], vals[$0*3+2]) })
                case "scale": tracks.s = (times, (0..<times.count).map { SIMD3(vals[$0*3], vals[$0*3+1], vals[$0*3+2]) })
                case "rotation": tracks.r = (times, (0..<times.count).map { simd_quatf(ix: vals[$0*4], iy: vals[$0*4+1], iz: vals[$0*4+2], r: vals[$0*4+3]).normalized })
                default: break
                }
            }
            clips[clip.name.lowercased()] = clip
        }
    }

    // MARK: Odtwarzanie klipów (własne, by w pełni sterować czasem i mieszaniem)

    func sample(_ clip: Clip, node i: Int, time: Float) -> TRS {
        var tr = defaults[i]
        guard let tracks = clip.tracks[i] else { return tr }
        if let t = tracks.t { tr.t = Self.lerp(t.times, t.values, time, mix: { $0 + ($1 - $0) * $2 }) }
        if let s = tracks.s { tr.s = Self.lerp(s.times, s.values, time, mix: { $0 + ($1 - $0) * $2 }) }
        if let r = tracks.r { tr.r = Self.lerp(r.times, r.values, time, mix: { simd_slerp($0, $1, $2) }) }
        return tr
    }

    /// Ustawia pozę: klip A w czasie `ta`, opcjonalnie zmieszany z klipem B (`blend` 0…1).
    func pose(_ a: Clip, at ta: Float, _ b: Clip? = nil, at tb: Float = 0, blend: Float = 0) {
        var animated = Set(a.tracks.keys)
        if let b { animated.formUnion(b.tracks.keys) }
        for i in animated {
            var tr = sample(a, node: i, time: ta)
            if let b, blend > 0 {
                let o = sample(b, node: i, time: tb)
                tr = TRS(t: tr.t + (o.t - tr.t) * blend, r: simd_slerp(tr.r, o.r, blend), s: tr.s + (o.s - tr.s) * blend)
            }
            let n = nodes[i]
            n.simdPosition = tr.t; n.simdOrientation = tr.r; n.simdScale = tr.s
        }
    }

    private static func lerp<T>(_ times: [Float], _ values: [T], _ time: Float, mix: (T, T, Float) -> T) -> T {
        if time <= times[0] || times.count == 1 { return values[0] }
        if time >= times[times.count - 1] { return values[times.count - 1] }
        var lo = 0, hi = times.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if times[m] <= time { lo = m } else { hi = m } }
        let f = (time - times[lo]) / max(1e-6, times[hi] - times[lo])
        return mix(values[lo], values[hi], f)
    }

    // MARK: Pomocnicze

    private static func trs(of d: [String: Any]) -> TRS {
        if let m = d["matrix"] as? [Double], m.count == 16 {
            let f = m.map(Float.init)
            let mat = simd_float4x4(columns: (SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]), SIMD4(f[8], f[9], f[10], f[11]), SIMD4(f[12], f[13], f[14], f[15])))
            let s = SIMD3<Float>(simd_length(SIMD3(f[0], f[1], f[2])), simd_length(SIMD3(f[4], f[5], f[6])), simd_length(SIMD3(f[8], f[9], f[10])))
            let rot = simd_float3x3(SIMD3(mat.columns.0.x, mat.columns.0.y, mat.columns.0.z) / s.x, SIMD3(mat.columns.1.x, mat.columns.1.y, mat.columns.1.z) / s.y, SIMD3(mat.columns.2.x, mat.columns.2.y, mat.columns.2.z) / s.z)
            return TRS(t: SIMD3(f[12], f[13], f[14]), r: simd_quatf(rot), s: s)
        }
        let t = (d["translation"] as? [Double]).map { SIMD3(Float($0[0]), Float($0[1]), Float($0[2])) } ?? .zero
        let r = (d["rotation"] as? [Double]).map { simd_quatf(ix: Float($0[0]), iy: Float($0[1]), iz: Float($0[2]), r: Float($0[3])) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let s = (d["scale"] as? [Double]).map { SIMD3(Float($0[0]), Float($0[1]), Float($0[2])) } ?? SIMD3(1, 1, 1)
        return TRS(t: t, r: r, s: s)
    }

    private static func makeMaterials(_ json: [String: Any], resolver: (String) -> UIImage?) -> [SCNMaterial] {
        let images = (json["images"] as? [[String: Any]] ?? []).map { ($0["uri"] as? String).flatMap(resolver) }
        let textures = (json["textures"] as? [[String: Any]] ?? []).map { $0["source"] as? Int }
        return (json["materials"] as? [[String: Any]] ?? []).map { m in
            let mat = SCNMaterial()
            mat.lightingModel = .blinn
            mat.isDoubleSided = (m["doubleSided"] as? Bool) ?? false
            mat.specular.contents = UIColor(white: 0.25, alpha: 1)
            mat.shininess = 0.15
            let pbr = m["pbrMetallicRoughness"] as? [String: Any] ?? [:]
            if let ti = (pbr["baseColorTexture"] as? [String: Any])?["index"] as? Int, ti < textures.count,
               let si = textures[ti], si < images.count, let img = images[si] {
                mat.diffuse.contents = img
                mat.diffuse.magnificationFilter = .nearest   // paleta kolorów: bez rozmycia
                mat.diffuse.minificationFilter = .linear
                mat.diffuse.mipFilter = .none
                mat.specular.contents = UIColor(white: 0.1, alpha: 1)
            } else if let c = pbr["baseColorFactor"] as? [Double], c.count == 4 {
                mat.diffuse.contents = UIColor(red: CGFloat(c[0]).srgb, green: CGFloat(c[1]).srgb, blue: CGFloat(c[2]).srgb, alpha: CGFloat(c[3]))
            } else { mat.diffuse.contents = UIColor(white: 0.8, alpha: 1) }
            return mat
        }
    }

    private struct Geo { var geometry: SCNGeometry; var weights: [Float]?; var joints: [UInt32]? }

    private static func geometry(_ prim: [String: Any], reader: Reader, materials: [SCNMaterial]) throws -> Geo? {
        guard (prim["mode"] as? Int ?? 4) == 4, let attrs = prim["attributes"] as? [String: Int], let pos = attrs["POSITION"] else { return nil }
        let p = reader.floats(pos).data
        var sources = [SCNGeometrySource(vertices: (0..<p.count / 3).map { SCNVector3(p[$0*3], p[$0*3+1], p[$0*3+2]) })]
        if let n = attrs["NORMAL"] {
            let f = reader.floats(n).data
            sources.append(SCNGeometrySource(normals: (0..<f.count / 3).map { SCNVector3(f[$0*3], f[$0*3+1], f[$0*3+2]) }))
        }
        if let t = attrs["TEXCOORD_0"] {
            let f = reader.floats(t).data
            sources.append(SCNGeometrySource(textureCoordinates: (0..<f.count / 2).map { CGPoint(x: CGFloat(f[$0*2]), y: CGFloat(f[$0*2+1])) }))
        }
        let vertexCount = p.count / 3
        let indices: [UInt32] = (prim["indices"] as? Int).map { reader.ints($0) } ?? (0..<UInt32(vertexCount)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geo = SCNGeometry(sources: sources, elements: [element])
        if let mi = prim["material"] as? Int, mi < materials.count { geo.materials = [materials[mi]] }
        var weights: [Float]?, joints: [UInt32]?
        if let j = attrs["JOINTS_0"], let w = attrs["WEIGHTS_0"] { joints = reader.ints(j); weights = reader.floats(w).data }
        return Geo(geometry: geo, weights: weights, joints: joints)
    }

    // MARK: Odczyt akcesorów

    private struct Reader {
        let json: [String: Any], bin: Data
        func accessor(_ i: Int) -> (comp: Int, count: Int, n: Int, stride: Int, offset: Int, normalized: Bool) {
            let a = (json["accessors"] as! [[String: Any]])[i]
            let bv = (json["bufferViews"] as! [[String: Any]])[a["bufferView"] as? Int ?? 0]
            let type = a["type"] as! String
            let n = ["SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16][type] ?? 1
            let comp = a["componentType"] as! Int
            let size = [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4][comp] ?? 4
            let stride = (bv["byteStride"] as? Int) ?? n * size
            return (comp, a["count"] as! Int, n, stride, (bv["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0), a["normalized"] as? Bool ?? false)
        }
        func floats(_ i: Int) -> (data: [Float], comps: Int) {
            let a = accessor(i)
            var out = [Float](); out.reserveCapacity(a.count * a.n)
            for e in 0..<a.count {
                for c in 0..<a.n {
                    let o = a.offset + e * a.stride + c * Self.size(a.comp)
                    out.append(value(at: o, comp: a.comp, normalized: a.normalized))
                }
            }
            return (out, a.n)
        }
        func ints(_ i: Int) -> [UInt32] {
            let a = accessor(i)
            var out = [UInt32](); out.reserveCapacity(a.count * a.n)
            for e in 0..<a.count {
                for c in 0..<a.n {
                    let o = a.offset + e * a.stride + c * Self.size(a.comp)
                    switch a.comp {
                    case 5121, 5120: out.append(UInt32(bin[o]))
                    case 5123, 5122: out.append(UInt32(bin.loadLE(UInt16.self, at: o)))
                    default: out.append(bin.loadLE(UInt32.self, at: o))
                    }
                }
            }
            return out
        }
        static func size(_ comp: Int) -> Int { [5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4][comp] ?? 4 }
        func value(at o: Int, comp: Int, normalized: Bool) -> Float {
            switch comp {
            case 5126: return Float(bitPattern: bin.loadLE(UInt32.self, at: o))
            case 5121: let v = Float(bin[o]); return normalized ? v / 255 : v
            case 5123: let v = Float(bin.loadLE(UInt16.self, at: o)); return normalized ? v / 65535 : v
            case 5120: let v = Float(Int8(bitPattern: bin[o])); return normalized ? max(v / 127, -1) : v
            case 5122: let v = Float(Int16(bitPattern: bin.loadLE(UInt16.self, at: o))); return normalized ? max(v / 32767, -1) : v
            default: return Float(bin.loadLE(UInt32.self, at: o))
            }
        }
    }
}

private extension Data {
    func loadLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var v: T = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) { copyBytes(to: $0, from: (startIndex + offset)..<(startIndex + offset + MemoryLayout<T>.size)) }
        return T(littleEndian: v)
    }
}

private extension CGFloat {
    /// Kolory glTF są liniowe; konwersja do sRGB dla UIColor.
    var srgb: CGFloat { self <= 0.0031308 ? self * 12.92 : 1.055 * pow(self, 1 / 2.4) - 0.055 }
}
