import RealityKit
import SwiftUI
import simd

/// Minimal RealityKit scene for the locker room: a slowly spinning player
/// character on a stage disc, rebuilt whenever the chosen skin changes.
@MainActor
@Observable
final class LockerRoomController {
    private var root: Entity?
    private var characterContainer: Entity?
    private var animator: GeneratedModelAnimationPlayer?
    private var updateSubscription: EventSubscription?
    private var spin: Float = 0

    func setup(content: RealityViewCameraContent) async {
        guard root == nil else { return }
        let root = Entity()
        content.add(root)
        self.root = root

        let key = DirectionalLight()
        key.light.intensity = 2400
        key.orientation = simd_quatf(angle: -0.7, axis: [1, 0.3, 0])
        root.addChild(key)

        let stage = ModelEntity(
            mesh: .generateCylinder(height: 0.12, radius: 1.6),
            materials: [SimpleMaterial(color: UIColor(white: 0.14, alpha: 1), roughness: 0.3, isMetallic: true)]
        )
        stage.position = [0, -0.06, 0]
        root.addChild(stage)

        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 1.62),
            materials: [UnlitMaterial(color: Team.orange.uiColor)]
        )
        ring.position = [0, 0.005, 0]
        root.addChild(ring)

        // Explicit camera pulled back and framed on the character's mid-height so
        // the whole body is visible instead of relying on RealityKit's default
        // camera, which sits far too close for a full-body portrait.
        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 32
        let eyeHeight = GameConfig.characterHeight * 0.82 * 0.55
        cam.position = [0, eyeHeight, 3.4]
        cam.look(at: [0, eyeHeight, 0], from: cam.position, relativeTo: nil)
        root.addChild(cam)

        await rebuildCharacter()

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(dt: Float(event.deltaTime))
        }
    }

    private func tick(dt: Float) {
        guard let container = characterContainer else { return }
        spin += dt * 0.5
        container.orientation = simd_quatf(angle: spin, axis: [0, 1, 0])
    }

    /// Tears down and rebuilds the displayed character for a new skin choice.
    func rebuildCharacter() async {
        guard let root else { return }
        characterContainer?.removeFromParent()

        let skin = ProfileStore.shared.selectedSkin
        let spec = skin.spec
        // Rigged idle clip as the body so the idle animation actually plays
        // (the static skin mesh has no skeleton).
        let container = await makeGeneratedModelContainer(
            resourceName: skin.bodyResource ?? spec.resourceName,
            targetSize: GameConfig.characterHeight * 0.82,
            anchor: .bottom,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: [0, 0, 1],
            worldPosition: [0, 0, 0],
            fallback: { Self.fallbackCharacter() }
        )
        root.addChild(container)
        characterContainer = container

        if let accessoryEntity = Self.accessoryEntity() {
            container.addChild(accessoryEntity)
        }

        let animator = GeneratedModelAnimationPlayer(container: container)
        await animator.preload([ModelCatalog.heroIdle, skin.idleAnim].compactMap { $0 })
        self.animator = animator
        animator.setLoop(skin.idleAnim ?? ModelCatalog.heroIdle)
    }

    private static func accessoryEntity() -> Entity? {
        let accessory = ProfileStore.shared.selectedAccessory
        guard accessory != .none else { return nil }
        let accentColor = UIColor(ProfileStore.shared.accentColor)
        let material = SimpleMaterial(color: accentColor, roughness: 0.35, isMetallic: true)
        let mesh: MeshResource
        let localPosition: SIMD3<Float>
        switch accessory {
        case .none:
            return nil
        case .band:
            mesh = .generateBox(size: [0.5, 0.07, 0.5], cornerRadius: 0.03)
            localPosition = [0, GameConfig.characterHeight * 0.82 * 0.92, 0]
        case .cape:
            mesh = .generateBox(size: [0.4, 0.5, 0.05], cornerRadius: 0.025)
            localPosition = [0, GameConfig.characterHeight * 0.82 * 0.72, -0.15]
        case .visor:
            mesh = .generateBox(size: [0.4, 0.1, 0.11], cornerRadius: 0.025)
            localPosition = [0, GameConfig.characterHeight * 0.82 * 0.9, 0.18]
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.position = localPosition
        return entity
    }

    private static func fallbackCharacter() -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: [0.6, 1.8, 0.4], cornerRadius: 0.2),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.5, isMetallic: false)]
        )
    }
}
