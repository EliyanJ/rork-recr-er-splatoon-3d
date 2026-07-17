import RealityKit
import simd

/// Local axis classification persisted with every generated 3D model.
enum GeneratedModelAxis: String {
    case positiveX, negativeX, positiveY, negativeY, positiveZ, negativeZ

    var vector: SIMD3<Float> {
        switch self {
        case .positiveX: [1, 0, 0]
        case .negativeX: [-1, 0, 0]
        case .positiveY: [0, 1, 0]
        case .negativeY: [0, -1, 0]
        case .positiveZ: [0, 0, 1]
        case .negativeZ: [0, 0, -1]
        }
    }
}

/// How a normalized visual is anchored inside its container.
enum GeneratedModelAnchor {
    case bottom
    case center
}

/// Quaternion for the orthonormal basis built from `front` and `up`.
func generatedModelBasisQuaternion(front: SIMD3<Float>, up: SIMD3<Float>) -> simd_quatf {
    let f = simd_normalize(front)
    let r = simd_normalize(simd_cross(up, f))
    let u = simd_normalize(simd_cross(f, r))
    return simd_quatf(simd_float3x3(r, u, f))
}

/// Full body-frame correction: rotates the model so its classified local front
/// axis points along `desiredWorldForward` while its local up axis stays world-up.
func generatedModelOrientationCorrection(
    localFrontAxis: GeneratedModelAxis,
    localUpAxis: GeneratedModelAxis,
    desiredWorldForward: SIMD3<Float>,
    worldUp: SIMD3<Float> = [0, 1, 0]
) -> simd_quatf {
    let localBasis = generatedModelBasisQuaternion(front: localFrontAxis.vector, up: localUpAxis.vector)
    let worldBasis = generatedModelBasisQuaternion(front: desiredWorldForward, up: worldUp)
    return worldBasis * localBasis.inverse
}

/// Normalizes a loaded visual into an existing container following the
/// container → runtime child → visual contract.
///
/// Scale, orientation correction and centering are applied to the RUNTIME
/// entity (the visual's parent), never to the visual itself. Generated
/// animation clips can contain root transform tracks that overwrite the
/// animated entity's transform during playback — keeping the correction on
/// the parent guarantees the character stays upright while animating.
@MainActor
func attachGeneratedModelVisual(
    _ visual: Entity,
    to container: Entity,
    targetSize: Float,
    scaleAxis: GeneratedModelAxis? = nil,
    anchor: GeneratedModelAnchor = .bottom,
    localFrontAxis: GeneratedModelAxis?,
    localUpAxis: GeneratedModelAxis = .positiveY,
    desiredWorldForward: SIMD3<Float>? = nil
) {
    let runtime = container.findEntity(named: "generated_model_runtime") ?? {
        let runtime = Entity()
        runtime.name = "generated_model_runtime"
        container.addChild(runtime)
        return runtime
    }()
    runtime.children.forEach { $0.removeFromParent() }
    runtime.transform = Transform.identity
    runtime.addChild(visual)

    // 1. Scale the runtime so the relevant dimension matches the planned size.
    let rawBounds = visual.visualBounds(relativeTo: runtime)
    let axisVector = (scaleAxis ?? .positiveY).vector
    let reference = abs(axisVector.x) * rawBounds.extents.x
        + abs(axisVector.y) * rawBounds.extents.y
        + abs(axisVector.z) * rawBounds.extents.z
    runtime.scale = SIMD3<Float>(repeating: targetSize / max(reference, 0.001))

    // 2. Orientation correction from the persisted axes — only with an intrinsic front.
    if let localFrontAxis, let desiredWorldForward {
        runtime.orientation = generatedModelOrientationCorrection(
            localFrontAxis: localFrontAxis,
            localUpAxis: localUpAxis,
            desiredWorldForward: desiredWorldForward
        )
    }

    // 3. Center X/Z and anchor Y from post-transform bounds in container space.
    let bounds = visual.visualBounds(relativeTo: container)
    switch anchor {
    case .bottom:
        runtime.position -= SIMD3<Float>(bounds.center.x, bounds.min.y, bounds.center.z)
    case .center:
        runtime.position -= bounds.center
    }
}

/// Builds container → runtime child → normalized visual for a bundled generated model.
@MainActor
func makeGeneratedModelContainer(
    resourceName: String?,
    targetSize: Float,
    scaleAxis: GeneratedModelAxis? = nil,
    anchor: GeneratedModelAnchor = .bottom,
    localFrontAxis: GeneratedModelAxis?,
    localUpAxis: GeneratedModelAxis = .positiveY,
    desiredWorldForward: SIMD3<Float>? = nil,
    worldPosition: SIMD3<Float> = .zero,
    fallback: () -> ModelEntity
) async -> Entity {
    let container = Entity()
    var loaded: Entity?
    if let resourceName {
        loaded = try? await Entity(named: resourceName)
    }
    attachGeneratedModelVisual(
        loaded ?? fallback(),
        to: container,
        targetSize: targetSize,
        scaleAxis: scaleAxis,
        anchor: anchor,
        localFrontAxis: localFrontAxis,
        localUpAxis: localUpAxis,
        desiredWorldForward: desiredWorldForward
    )
    container.position = worldPosition
    return container
}
