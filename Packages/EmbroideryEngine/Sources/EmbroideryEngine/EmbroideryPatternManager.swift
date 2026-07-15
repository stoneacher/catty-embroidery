/// Identifies the object ("sprite" in Catroid, "actor" here) a stitch
/// command originates from. The workspace dedup and the actor-change tie-off
/// in `DSTStitchCommand.act` are keyed on it (US-110).
public struct ActorID: Hashable, Sendable {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// Port of Catroid `DSTPatternManager` plus `DSTStitchCommand.act`
/// (US-110, ADR-012): collects stitch commands per z-layer, applies the
/// workspace dedup, actor-change, and layer-switch rules at command time,
/// and assembles the layers in ascending order into one stream.
///
/// Where Catroid keeps a live `DSTStream` per layer and concatenates their
/// point lists, this port records per-layer *stage-space ops* — a point, its
/// color, and at most one armed flag — and replays them into a fresh
/// `EmbroideryStream` at `assembled()` time, so interpolation and unit
/// conversion run exactly once with the US-105 semantics. The replay goes
/// through the stream's dedup-free `append(stitchAt:color:)` seam because
/// several clauses emit byte-pinned consecutive duplicates.
///
/// Thread color handling is the ADR-012 deliberate divergence pinned in
/// ADR-015: Android's Set Thread Color brick only mutates the sprite's color
/// and never emits machine-level changes; here a differing set arms a DST
/// color change that the actor's next surviving stitch carries — silently
/// choosing the starting color while nothing has been emitted yet.
public struct EmbroideryPatternManager: Sendable {
    // MARK: - Internal state

    /// One recorded emission: a stage-space point, its color, and at most
    /// one armed flag consumed at replay (never both — Catroid arms either
    /// `addColorChange()` or `addJump()` before a given `addStitchPoint`).
    private struct EmittedPoint: Sendable {
        var stage: StagePoint
        var color: ThreadColor
        var armColorChange = false
        var armJump = false
    }

    /// Per-layer analogue of Catroid `DSTWorkSpace`: the last position and
    /// actor that stitched on the layer. The workspace color is never
    /// assigned in the reference, so clause B's emissions stay black.
    private struct LayerWorkspace: Sendable {
        var currentStage: StagePoint?
        var lastActor: ActorID?
    }

    /// Per-actor analogue of Catroid's `lastCommandOfSpriteMap` entry —
    /// global across layers, updated even for deduped commands.
    private struct LastCommand: Sendable {
        var stage: StagePoint
        var layer: Int
        var color: ThreadColor
    }

    /// Per-actor thread color plus the armed-change bit (ADR-015).
    private struct ColorState: Sendable {
        var current: ThreadColor = .black
        var pendingChange = false
    }

    /// TreeMap analogue: keys are z-layers, sorted ascending at assembly.
    private var layerOps: [Int: [EmittedPoint]] = [:]
    private var workspaces: [Int: LayerWorkspace] = [:]
    private var lastCommandByActor: [ActorID: LastCommand] = [:]
    private var colorByActor: [ActorID: ColorState] = [:]

    public init() {}

    // MARK: - Queries

    /// Catroid `validPatternExists`: more than one recorded point overall.
    public var hasValidPattern: Bool {
        layerOps.values.reduce(0) { $0 + $1.count } > 1
    }

    private var hasEmittedOps: Bool {
        layerOps.values.contains { !$0.isEmpty }
    }

    // MARK: - Thread color (ADR-012 divergence, edges pinned by ADR-015)

    /// Sets the actor's thread color. Setting the current color is a no-op;
    /// a differing color arms a DST color change for the actor's next
    /// surviving stitch — unless nothing has been emitted manager-wide yet,
    /// in which case the set silently chooses the starting color (Catroid
    /// only ever inserts color changes into non-empty streams).
    public mutating func setThreadColor(_ color: ThreadColor, for actor: ActorID) {
        var state = colorByActor[actor] ?? ColorState()
        guard color != state.current else { return }
        state.current = color
        if hasEmittedOps {
            state.pendingChange = true
        }
        colorByActor[actor] = state
    }

    /// Hex-string variant used by the Set Thread Color brick. Malformed
    /// input is a full no-op — the actor keeps its current color, matching
    /// Android's swallowed parse exception (ADR-015).
    public mutating func setThreadColor(hexString: String, for actor: ActorID) {
        guard let color = ThreadColor(hexString: hexString) else { return }
        setThreadColor(color, for: actor)
    }

    // MARK: - Stitch commands (port of DSTStitchCommand.act)

    /// Records a stitch command on a layer. Clauses in Catroid's order:
    ///
    /// A. Workspace dedup: same position *and* same actor as the layer's
    ///    workspace emits nothing — but still updates the actor's last
    ///    command, like `DSTPatternManager.addStitchCommand`.
    /// B. Actor change on the layer: color change armed on the workspace
    ///    position, which is emitted twice (with a jump armed between the
    ///    two when the target is farther than ±121 units). Both emissions
    ///    carry the never-assigned workspace color — black.
    /// C. Otherwise, layer switch into a non-empty layer: far targets get
    ///    the color change armed on the target itself (clause E emits it
    ///    again, deliberately un-deduped); near targets tie off with the
    ///    previous command's point emitted twice (change, then jump).
    /// D. Independently, a layer switch with a *strictly* near target also
    ///    re-emits the previous command's point as the layer's entry stitch.
    /// E. Always: the target itself, carrying the actor's pending color
    ///    change if one is armed.
    ///
    /// Catroid arms flags via `stream.addColorChange()`/`addJump()` *before*
    /// `addStitchPoint`, so each armed flag rides the next emitted point.
    public mutating func addStitch(at point: StagePoint, layer: Int, actor: ActorID) {
        let workspace = workspaces[layer] ?? LayerWorkspace()
        let previous = lastCommandByActor[actor]
        var colorState = colorByActor[actor] ?? ColorState()
        let color = colorState.current

        // Clause A — dedup returns before any flag is consumed, so a
        // pending color change survives onto the next surviving stitch.
        if workspace.currentStage == point, workspace.lastActor == actor {
            lastCommandByActor[actor] = LastCommand(stage: point, layer: layer, color: color)
            return
        }

        if let lastActor = workspace.lastActor, lastActor != actor {
            // Clause B — the workspace has stitched, so currentStage is set.
            let workspacePoint = workspace.currentStage!
            let isFar = distanceInUnits(from: workspacePoint, to: point) > DSTStitchRecord.maxDelta
            layerOps[layer, default: []].append(
                EmittedPoint(stage: workspacePoint, color: .black, armColorChange: true)
            )
            layerOps[layer, default: []].append(
                EmittedPoint(stage: workspacePoint, color: .black, armJump: isFar)
            )
        } else if !(layerOps[layer] ?? []).isEmpty, let previous, previous.layer != layer {
            // Clause C — strict > mirrors the reference; exactly 121 ties off.
            if distanceInUnits(from: previous.stage, to: point) > DSTStitchRecord.maxDelta {
                layerOps[layer, default: []].append(
                    EmittedPoint(stage: point, color: color, armColorChange: true)
                )
            } else {
                layerOps[layer, default: []].append(
                    EmittedPoint(stage: previous.stage, color: previous.color, armColorChange: true)
                )
                layerOps[layer, default: []].append(
                    EmittedPoint(stage: previous.stage, color: previous.color, armJump: true)
                )
            }
        }

        // Clause D — not chained to B/C in the reference; strict <, so a
        // 121-unit gap emits nothing here.
        let connectsNearbyLayerSwitch = previous.map {
            $0.layer != layer && distanceInUnits(from: $0.stage, to: point) < DSTStitchRecord.maxDelta
        } ?? false
        if let previous, connectsNearbyLayerSwitch {
            layerOps[layer, default: []].append(
                EmittedPoint(stage: previous.stage, color: previous.color)
            )
        }

        // Clause E — the target, consuming the actor's pending color change.
        layerOps[layer, default: []].append(
            EmittedPoint(stage: point, color: color, armColorChange: colorState.pendingChange)
        )
        colorState.pendingChange = false
        colorByActor[actor] = colorState
        workspaces[layer] = LayerWorkspace(currentStage: point, lastActor: actor)
        lastCommandByActor[actor] = LastCommand(stage: point, layer: layer, color: color)
    }

    // MARK: - Assembly (port of DSTPatternManager.getEmbroideryStream)

    /// Replays every layer's ops in ascending z-order into one fresh stream.
    /// Between layers Catroid signals a color change and re-emits the
    /// previous layer's last point (the boundary re-emit); the replay side
    /// of the concatenation contributes the join duplicate as a jump, so a
    /// layer never starts with an un-anchored move. All emission bypasses
    /// `addStitch`: the clause traces are byte-pinned including their
    /// consecutive duplicates, and interpolation runs here exactly once.
    public func assembled() -> EmbroideryStream {
        var stream = EmbroideryStream()
        var lastStage: StagePoint?
        var lastColor = ThreadColor.black
        let sortedLayers = layerOps.keys.sorted()

        for (index, layer) in sortedLayers.enumerated() {
            guard let ops = layerOps[layer], !ops.isEmpty else { continue }
            if !stream.stitches.isEmpty {
                stream.addJump()
                stream.append(stitchAt: lastStage!, color: lastColor)
            }
            for emission in ops {
                if emission.armColorChange {
                    stream.addColorChange()
                } else if emission.armJump {
                    stream.addJump()
                }
                stream.append(stitchAt: emission.stage, color: emission.color)
                lastStage = emission.stage
                lastColor = emission.color
            }
            let hasLaterOps = sortedLayers[(index + 1)...]
                .contains { !(layerOps[$0] ?? []).isEmpty }
            if hasLaterOps {
                stream.addColorChange()
                stream.append(stitchAt: lastStage!, color: lastColor)
            }
        }
        return stream
    }

    // MARK: - Distance

    /// Catroid `DSTFileConstants.getMaxDistanceBetweenPoints`: Chebyshev
    /// distance with each stage-space axis difference converted to
    /// embroidery units first (the ADR-012 decision-only difference
    /// conversion), compared against `MAX_DISTANCE` = ±121.
    private func distanceInUnits(from start: StagePoint, to end: StagePoint) -> Int {
        max(
            abs(EmbroideryPoint.embroideryUnits(fromStageValue: end.x - start.x)),
            abs(EmbroideryPoint.embroideryUnits(fromStageValue: end.y - start.y))
        )
    }
}
