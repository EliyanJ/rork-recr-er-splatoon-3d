import Foundation
import RealityKit

/// Recycles the short-lived VFX entities (hit splash / puff / flash, kill
/// ring / plume / flash, grenade burst) instead of allocating and destroying
/// a fresh `ModelEntity` per event.
///
/// Before pooling, every hit and kill created 1-3 `ModelEntity` objects, added
/// them to the scene graph, then removed them via `Task.sleep`. A sustained jet
/// lands several hits per second, so this was a steady stream of allocations,
/// scene-graph mutations and concurrent async tasks on the combat hot path.
///
/// The pool keeps a stack of idle entities parented ONCE to `worldRoot` and
/// toggled with `isEnabled`. Lifetimes are driven by `tick(now:)` from the sim
/// loop — no `Task.sleep` and no per-event async task. All access is on the
/// main actor because every operation touches `Entity`.
@MainActor
final class VFXPool {
    /// A scheduled recycle: when `now >= expiresAt`, the entity is disabled and
    /// returned to the idle stack. `budgeted` entries decrement the caller's
    /// live-VFX counter so the transient-VFX budget stays accurate.
    private struct Active {
        let entity: ModelEntity
        let expiresAt: Double
        let budgeted: Bool
    }

    private weak var root: Entity?
    private var idle: [ModelEntity] = []
    private var active: [Active] = []

    /// Re-parents the pool to a freshly built world root at match setup and
    /// drops any entities that belonged to the previous (now discarded) root.
    func reset(root: Entity) {
        self.root = root
        idle.removeAll(keepingCapacity: true)
        active.removeAll(keepingCapacity: true)
    }

    /// Pre-creates `count` idle entities so the first intense fight of a match
    /// never allocates mid-combat.
    func warm(count: Int) {
        guard let root else { return }
        for _ in 0..<count {
            let entity = ModelEntity()
            entity.isEnabled = false
            root.addChild(entity)
            idle.append(entity)
        }
    }

    /// Fetches a recycled entity (or creates one), applies the mesh/material,
    /// positions and scales it, enables it and schedules its recycle. Returns
    /// the entity so the caller can drive its `.move(to:)` animation.
    @discardableResult
    func spawn(
        mesh: MeshResource,
        materials: [Material],
        position: SIMD3<Float>,
        scale: SIMD3<Float>,
        lifetime: Double,
        now: Double,
        budgeted: Bool
    ) -> ModelEntity? {
        guard let root else { return nil }
        let entity: ModelEntity
        if let reused = idle.popLast() {
            entity = reused
        } else {
            entity = ModelEntity()
            root.addChild(entity)
        }
        entity.model = ModelComponent(mesh: mesh, materials: materials)
        entity.transform = Transform(scale: scale, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), translation: position)
        entity.isEnabled = true
        active.append(Active(entity: entity, expiresAt: now + lifetime, budgeted: budgeted))
        return entity
    }

    /// Recycles every VFX whose lifetime has elapsed. Returns the number of
    /// budgeted entities freed this tick so the caller can decrement its live
    /// count in one shot.
    func tick(now: Double) -> Int {
        var freedBudgeted = 0
        var i = 0
        while i < active.count {
            if now >= active[i].expiresAt {
                let item = active[i]
                item.entity.stopAllAnimations()
                item.entity.isEnabled = false
                idle.append(item.entity)
                if item.budgeted { freedBudgeted += 1 }
                active.remove(at: i)
            } else {
                i += 1
            }
        }
        return freedBudgeted
    }
}
