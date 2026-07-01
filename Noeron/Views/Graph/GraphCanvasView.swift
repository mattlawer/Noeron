//
//  GraphCanvasView.swift
//  Noeron
//
//  Interactive node-link canvas. Edges are drawn with SwiftUI Canvas; nodes are
//  draggable views. Pan, zoom, select, and auto-expand straight from the graph.
//

import SwiftUI
import SwiftData

struct GraphCanvasView: View {
    @Bindable var investigation: Investigation
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: DiscoveryEngine

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var scale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var dragPanStart: CGSize = .zero
    @State private var selectedID: UUID?
    @State private var didLayout = false
    @State private var viewportSize: CGSize = .zero

    private let canvasSize = CGSize(width: 1800, height: 1300)
    private let minScale: CGFloat = 0.15
    private let maxScale: CGFloat = 4

    private var entities: [Entity] { investigation.entitiesArray }
    private var links: [EntityLink] { investigation.linksArray }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvasBackground.ignoresSafeArea()

                graphLayer
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(scale)
                    .offset(pan)
                    .coordinateSpace(name: "graph")

                if entities.isEmpty { emptyState }
                if let id = selectedID, let entity = entities.first(where: { $0.id == id }) {
                    selectionInspector(entity).transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if engine.isRunning { runningBanner }
            }
            // Fill the GeometryReader and centre children. Without this the ZStack
            // shrinks to the 1800×1300 canvas and anchors top-left, pushing the
            // (centre-anchored) fit transform entirely off-screen → blank graph.
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear {
                viewportSize = geo.size
                ensureLayout()
            }
            .onChange(of: geo.size) { _, s in
                viewportSize = s
                if !didLayout { ensureLayout() }
            }
            .onChange(of: entities.count) { _, _ in ensureLayout(force: true) }
        }
        .navigationTitle("Graph")
        .toolbar { graphToolbar }
    }

    // MARK: Layers

    private var graphLayer: some View {
        ZStack {
            Canvas { ctx, _ in
                // Edges live in the zoomed canvas, so divide widths by the zoom to
                // keep a constant, visible on-screen thickness (like the nodes).
                let base = 2.4 / scale
                for link in links {
                    guard let s = link.source?.id, let t = link.target?.id,
                          let a = positions[s], let b = positions[t] else { continue }
                    var path = Path(); path.move(to: a); path.addLine(to: b)
                    let highlighted = selectedID == s || selectedID == t
                    ctx.stroke(path, with: .color(.white.opacity(highlighted ? 0.85 : 0.40)),
                               lineWidth: highlighted ? base * 1.8 : base)
                    // Midpoint label for highlighted edges
                    if highlighted {
                        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        ctx.draw(Text(link.label).font(.system(size: 11 / scale, weight: .medium))
                            .foregroundColor(.white), at: mid)
                    }
                }
            }
            ForEach(entities) { entity in
                NodeView(entity: entity, selected: selectedID == entity.id)
                    // Counter-scale so nodes & labels keep a constant, readable
                    // on-screen size at any zoom (the parent scaleEffect would
                    // otherwise shrink them into illegibility when fitted).
                    .scaleEffect(1.0 / scale)
                    .position(positions[entity.id] ?? randomStart())
                    .highPriorityGesture(nodeDrag(entity))
                    .onTapGesture { withAnimation(.spring(duration: 0.25)) { selectedID = entity.id } }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Empty graph", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("Add a seed entity and run discovery — nodes appear automatically.")
        }
        .foregroundStyle(.white.opacity(0.8))
    }

    private func selectionInspector(_ entity: Entity) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                KindBadge(kind: entity.kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.label).font(.headline).lineLimit(1)
                    Text("\(entity.kind.displayName) · \(entity.degree) links").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await engine.expand(seed: entity, in: investigation, modelContext: modelContext) }
                } label: { Label("Expand", systemImage: "point.3.connected.trianglepath.dotted") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(engine.isRunning)
                NavigationLink(value: entity) { Label("Open", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(role: .destructive) { discard(entity) } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help("Discard as false positive")
                Button { withAnimation { selectedID = nil } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(16)
        }
    }

    private var runningBanner: some View {
        VStack {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(engine.statusText).font(.caption).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 10)
            Spacer()
        }
    }

    @ToolbarContentBuilder
    private var graphToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { relayout() } label: { Label("Re-layout", systemImage: "wand.and.rays") }
            Button { fitToContent() } label: { Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
        }
    }

    // MARK: Gestures

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in pan = CGSize(width: dragPanStart.width + value.translation.width,
                                               height: dragPanStart.height + value.translation.height) }
            .onEnded { _ in dragPanStart = pan }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in scale = min(max(value * lastScale, minScale), maxScale) }
            .onEnded { _ in lastScale = scale }
    }
    @State private var lastScale: CGFloat = 1

    /// Drag a node. Uses the gesture *translation* divided by the current zoom so
    /// the node tracks the finger exactly regardless of scale/pan, instead of
    /// snapping to a mis-mapped point in the transformed coordinate space.
    private func nodeDrag(_ entity: Entity) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let base = dragStart[entity.id] ?? positions[entity.id] ?? randomStart()
                if dragStart[entity.id] == nil { dragStart[entity.id] = base }
                positions[entity.id] = CGPoint(x: base.x + value.translation.width / scale,
                                               y: base.y + value.translation.height / scale)
            }
            .onEnded { value in
                let base = dragStart[entity.id] ?? positions[entity.id] ?? randomStart()
                let p = CGPoint(x: base.x + value.translation.width / scale,
                                y: base.y + value.translation.height / scale)
                positions[entity.id] = p
                entity.canvasX = p.x; entity.canvasY = p.y
                dragStart[entity.id] = nil
                try? modelContext.save()
            }
    }
    @State private var dragStart: [UUID: CGPoint] = [:]

    // MARK: Layout

    private func ensureLayout(force: Bool = false) {
        if !force && didLayout && positions.count == entities.count { return }
        // Use persisted positions where available.
        var seed: [UUID: CGPoint] = [:]
        for e in entities where e.canvasX != 0 || e.canvasY != 0 {
            seed[e.id] = CGPoint(x: e.canvasX, y: e.canvasY)
        }
        // Always run a layout pass on first appear, seeding from any persisted
        // positions. This recompacts graphs saved with the old wide spacing (which
        // otherwise stay spread out and tiny) while keeping the topology stable.
        relayout(initial: seed)
        didLayout = true
    }

    private func relayout(initial: [UUID: CGPoint] = [:]) {
        let ids = entities.map(\.id)
        let edges = links.compactMap { link -> (UUID, UUID)? in
            guard let s = link.source?.id, let t = link.target?.id else { return nil }
            return (s, t)
        }
        let layout = ForceDirectedLayout(size: canvasSize)
        let result = layout.layout(nodeIDs: ids, edges: edges, initial: initial)
        withAnimation(.easeInOut(duration: 0.4)) { positions = result }
        // Persist
        for e in entities { if let p = result[e.id] { e.canvasX = p.x; e.canvasY = p.y } }
        try? modelContext.save()
        fitToContent()
    }

    /// Zoom and pan so every node fits the viewport, centred — the key to a
    /// readable graph on a phone (the canvas is far larger than the screen).
    private func fitToContent() {
        let pts = Array(positions.values)
        guard pts.count > 0, viewportSize.width > 1, viewportSize.height > 1 else { return }
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
        let contentW = max(maxX - minX, 1), contentH = max(maxY - minY, 1)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        // Padding (canvas units) leaves room for node circles + labels at the edges.
        let pad: CGFloat = 240
        let fit = min(viewportSize.width / (contentW + pad), viewportSize.height / (contentH + pad))
        // Don't blow tiny graphs up past ~1.4×; clamp to global bounds otherwise.
        let target = min(max(fit, minScale), 1.4)
        withAnimation(.easeInOut(duration: 0.35)) {
            scale = target
            lastScale = target
            pan = CGSize(width: (canvasCenter.x - center.x) * target,
                         height: (canvasCenter.y - center.y) * target)
            dragPanStart = pan
        }
    }

    /// Discard a node as a false positive: flag it (hidden + skipped by discovery),
    /// don't delete, so it stays reversible and isn't rediscovered.
    private func discard(_ entity: Entity) {
        withAnimation { selectedID = nil }
        positions[entity.id] = nil
        dragStart[entity.id] = nil
        entity.discarded = true
        entity.updatedAt = Date()
        try? modelContext.save()
    }

    private func randomStart() -> CGPoint {
        CGPoint(x: canvasSize.width / 2 + .random(in: -60...60),
                y: canvasSize.height / 2 + .random(in: -60...60))
    }
}

// MARK: - Node

private struct NodeView: View {
    let entity: Entity
    let selected: Bool
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(entity.kind.color.gradient)
                    .frame(width: nodeSize, height: nodeSize)
                    .shadow(color: entity.kind.color.opacity(0.6), radius: selected ? 8 : 2)
                Image(systemName: entity.kind.symbolName)
                    .font(.system(size: nodeSize * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2.5 : (entity.isSeed ? 1.5 : 0)))
            Text(entity.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.6)))
        }
    }
    private var nodeSize: CGFloat { entity.isSeed ? 48 : (34 + CGFloat(min(entity.degree, 8)) * 2) }
}
