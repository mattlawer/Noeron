//
//  GraphLayout.swift
//  Noeron
//
//  A small Fruchterman–Reingold force-directed layout. Pure value types so it can
//  run synchronously for modest graphs or be lifted off the main actor for big ones.
//

import CoreGraphics
import Foundation

struct ForceDirectedLayout {
    var size: CGSize = .init(width: 1600, height: 1200)
    var iterations: Int = 140
    /// Ideal edge length multiplier; higher spreads the graph out.
    var spread: CGFloat = 1.1
    /// Target distance (canvas points) between connected nodes. Kept small and
    /// independent of the canvas size so the graph stays compact and reads well
    /// once fitted to the viewport — deriving it from the (huge) canvas area made
    /// nodes ~750pt apart, so fit had to zoom out until everything was a speck.
    var idealEdgeLength: CGFloat = 160

    func layout(nodeIDs: [UUID],
                edges: [(UUID, UUID)],
                initial: [UUID: CGPoint] = [:],
                pinned: Set<UUID> = []) -> [UUID: CGPoint] {
        guard nodeIDs.count > 1 else {
            return Dictionary(uniqueKeysWithValues: nodeIDs.map { ($0, initial[$0] ?? .zero) })
        }

        let k = idealEdgeLength * spread
        var pos: [UUID: CGPoint] = [:]
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for (i, id) in nodeIDs.enumerated() {
            if let p = initial[id], p != .zero {
                pos[id] = p
            } else {
                // Deterministic ring seed avoids the all-at-origin singularity.
                let angle = CGFloat(i) / CGFloat(nodeIDs.count) * 2 * .pi
                pos[id] = CGPoint(x: center.x + cos(angle) * k, y: center.y + sin(angle) * k)
            }
        }

        var temperature = size.width / 10
        let cooling = temperature / CGFloat(iterations + 1)

        for _ in 0..<iterations {
            var disp = [UUID: CGVector](minimumCapacity: nodeIDs.count)
            for id in nodeIDs { disp[id] = .zero }

            // Repulsion (all pairs)
            for i in 0..<nodeIDs.count {
                let a = nodeIDs[i]
                for j in (i + 1)..<nodeIDs.count {
                    let b = nodeIDs[j]
                    var delta = CGVector(dx: pos[a]!.x - pos[b]!.x, dy: pos[a]!.y - pos[b]!.y)
                    var dist = max(delta.length, 0.01)
                    if dist > k * 6 { continue }            // ignore far pairs for speed
                    let force = (k * k) / dist
                    delta = delta.normalized
                    disp[a]! += delta * force
                    disp[b]! -= delta * force
                    _ = dist
                }
            }

            // Attraction (along edges)
            for (u, v) in edges {
                guard let pu = pos[u], let pv = pos[v] else { continue }
                var delta = CGVector(dx: pu.x - pv.x, dy: pu.y - pv.y)
                let dist = max(delta.length, 0.01)
                let force = (dist * dist) / k
                delta = delta.normalized
                disp[u]! -= delta * force
                disp[v]! += delta * force
            }

            // Integrate with temperature cap
            for id in nodeIDs where !pinned.contains(id) {
                let d = disp[id]!
                let len = max(d.length, 0.01)
                let limited = d.normalized * min(len, temperature)
                var p = pos[id]!
                p.x = min(max(p.x + limited.dx, 20), size.width - 20)
                p.y = min(max(p.y + limited.dy, 20), size.height - 20)
                pos[id] = p
            }
            temperature = max(temperature - cooling, 1)
        }
        return pos
    }
}

// MARK: - Vector math

extension CGVector {
    var length: CGFloat { sqrt(dx * dx + dy * dy) }
    var normalized: CGVector { let l = max(length, 0.0001); return CGVector(dx: dx / l, dy: dy / l) }
    static func + (a: CGVector, b: CGVector) -> CGVector { .init(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func - (a: CGVector, b: CGVector) -> CGVector { .init(dx: a.dx - b.dx, dy: a.dy - b.dy) }
    static func * (v: CGVector, s: CGFloat) -> CGVector { .init(dx: v.dx * s, dy: v.dy * s) }
    static func += (a: inout CGVector, b: CGVector) { a = a + b }
    static func -= (a: inout CGVector, b: CGVector) { a = a - b }
}
