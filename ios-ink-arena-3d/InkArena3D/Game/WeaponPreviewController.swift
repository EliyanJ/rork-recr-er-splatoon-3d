import RealityKit
import SwiftUI
import simd

/// Presentation viewer of the Armurerie: one weapon model on a lit stage,
/// auto-spinning slowly, manually rotatable by dragging. Rebuilt whenever
/// the browsed weapon (or its equipped skin) changes.
@MainActor
@Observable
final class WeaponPreviewController {
    private var root: Entity?
    private var weaponContainer: Entity?
    private var updateSubscription: EventSubscription?
    private var spin: Float = 0
    /// Extra user-driven yaw from the drag gesture.
    private var userSpin: Float = 0
    /// Seconds left before the auto-spin resumes after a manual drag.
    private var manualHold: Float = 0
    private var displayedWeapon: WeaponType?
    private var displayedSkinID: String?

    func setup(content: RealityViewCameraContent, weapon: WeaponType) async {
        guard root == nil else { return }
        let root = Entity()
        content.add(root)
        self.root = root

        let key = DirectionalLight()
        key.light.intensity = 2600
        key.orientation = simd_quatf(angle: -0.65, axis: [1, 0.35, 0])
        root.addChild(key)

        let stage = ModelEntity(
            mesh: .generateCylinder(height: 0.08, radius: 1.1),
            materials: [SimpleMaterial(color: UIColor(white: 0.13, alpha: 1), roughness: 0.3, isMetallic: true)]
        )
        stage.position = [0, -0.65, 0]
        root.addChild(stage)

        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.02, radius: 1.12),
            materials: [UnlitMaterial(color: Team.orange.uiColor)]
        )
        ring.position = [0, -0.6, 0]
        root.addChild(ring)

        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = 30
        cam.position = [0, 0.15, 2.6]
        cam.look(at: [0, 0, 0], from: cam.position, relativeTo: nil)
        root.addChild(cam)

        await show(weapon: weapon)

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(dt: Float(event.deltaTime))
        }
    }

    private func tick(dt: Float) {
        guard let container = weaponContainer else { return }
        if manualHold > 0 {
            manualHold -= dt
        } else {
            spin += dt * 0.55
        }
        container.orientation = simd_quatf(angle: spin + userSpin, axis: [0, 1, 0])
    }

    /// Manual rotation from the horizontal drag gesture.
    func addUserSpin(_ delta: Float) {
        userSpin += delta
        manualHold = 1.6
    }

    /// Swaps the displayed weapon model (with its equipped cosmetic tint).
    func show(weapon: WeaponType) async {
        guard let root else { return }
        let skinID = MetaStore.shared.equippedSkin(for: weapon)?.id
        guard displayedWeapon != weapon || displayedSkinID != skinID else { return }
        displayedWeapon = weapon
        displayedSkinID = skinID
        weaponContainer?.removeFromParent()

        let spec = Self.spec(for: weapon)
        let container = await makeGeneratedModelContainer(
            resourceName: spec.resourceName,
            targetSize: 1.35,
            anchor: .center,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: [1, 0, 0],
            worldPosition: [0, 0, 0],
            fallback: { Self.fallbackWeapon() }
        )
        if let hex = MetaStore.shared.equippedSkinColorHex(for: weapon) {
            Self.tint(container, hex: hex)
        }
        root.addChild(container)
        weaponContainer = container
        spin = 0
        userSpin = 0
    }

    private static func spec(for weapon: WeaponType) -> ModelCatalog.GeneratedModelSpec {
        switch weapon {
        case .blaster: ModelCatalog.blaster
        case .charger: ModelCatalog.sniper
        case .rapid: ModelCatalog.machineGun
        case .bucket: ModelCatalog.bucketLauncher
        case .dual: ModelCatalog.pistol
        }
    }

    private static func fallbackWeapon() -> ModelEntity {
        ModelEntity(
            mesh: .generateBox(size: [1.0, 0.28, 0.2], cornerRadius: 0.06),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.4, isMetallic: true)]
        )
    }

    private static func tint(_ entity: Entity, hex: String) {
        var value = UInt64()
        Scanner(string: hex).scanHexInt64(&value)
        let color = UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
        func visit(_ node: Entity) {
            if var model = node.components[ModelComponent.self] {
                model.materials = model.materials.map { material in
                    if var pbm = material as? PhysicallyBasedMaterial {
                        pbm.baseColor.tint = color
                        return pbm
                    }
                    return material
                }
                node.components.set(model)
            }
            for child in node.children { visit(child) }
        }
        visit(entity)
    }
}
