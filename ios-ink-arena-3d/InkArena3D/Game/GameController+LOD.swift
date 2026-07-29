import Foundation
import RealityKit
import simd

/// Distance level-of-detail for fighters.
///
/// Six skinned characters, each with a 24-joint skeleton, are re-posed and
/// re-skinned by RealityKit on every single frame — regardless of whether they
/// fill the screen or are a thirty-pixel speck at the far end of the arena.
/// That is the heaviest recurring per-character cost in the match, and the one
/// with the weakest link to what the player can actually perceive.
///
/// This pass freezes the animation of distant fighters and hides their
/// smallest cosmetic attachments. It is strictly visual: positions, steering,
/// firing, damage and networking all keep running at full rate, so a bot that
/// is frozen mid-stride still walks across the map and still shoots back.
extension GameController {
    /// Runs the LOD re-evaluation at `characterLODInterval` (5 Hz). Crossing a
    /// threshold a fifth of a second late is invisible, and the pass itself
    /// then costs nothing on the other frames.
    func updateCharacterLODThrottled(dt: Float, camera: PerspectiveCamera) {
        characterLODAccum += dt
        guard characterLODAccum >= characterLODInterval else { return }
        characterLODAccum = 0
        updateCharacterLOD(camera: camera)
    }

    func updateCharacterLOD(camera: PerspectiveCamera) {
        let animationCull = qualitySettings.animationCullDistance
        let shadowCull = qualitySettings.blobShadowCullDistance
        // Ultra keeps every fighter fully animated at any distance — both
        // thresholds are infinite, so there is nothing to decide.
        guard animationCull < .greatestFiniteMagnitude
            || shadowCull < .greatestFiniteMagnitude else { return }

        let camPos = camera.position(relativeTo: nil)
        for bot in bots {
            let distance = simd_distance(camPos, bot.container.position(relativeTo: nil))
            // Skinning: the expensive one. A frozen pose at 35 m+ is
            // indistinguishable from a walk cycle at that pixel size.
            bot.animator.setLODPaused(distance > animationCull)
            if let shadow = bot.blobShadow {
                let visible = distance <= shadowCull
                if shadow.isEnabled != visible { shadow.isEnabled = visible }
            }
        }

        // The local player is always within a couple of metres of the camera in
        // third person, and hidden in first person — its animation is never
        // frozen. Only its shadow follows the preset, for consistency with the
        // bots when the camera pulls far back.
        if let shadow = playerBlobShadow {
            let visible = shadowCull >= .greatestFiniteMagnitude
                || simd_distance(camPos, shadow.position(relativeTo: nil)) <= shadowCull
            if shadow.isEnabled != visible { shadow.isEnabled = visible }
        }
    }

    /// Re-applies the parts of the active preset that can be switched at
    /// runtime, after the auto-downgrade steps the quality down mid-match.
    ///
    /// Most preset knobs are read live every frame (projectile cap, paint flush
    /// rate, bot think rate, VFX level, LOD distances) and so need nothing here.
    /// These four were previously baked in at setup only, which meant a
    /// downgrade triggered by a struggling device did nothing about the very
    /// geometry and lights that were causing the drop.
    func reapplyRuntimeQuality() {
        // Decorative layer: trees, holo panels, floating crystals, distant
        // mountains. Nothing collides with them and nothing reads them, so
        // switching the whole branch off is safe at any moment.
        if !qualitySettings.decorEnabled, decorRoot?.isEnabled == true {
            decorRoot?.isEnabled = false
        }
        // Dynamic lights: each one is a per-fragment evaluation over everything
        // on screen.
        sunLight?.light.intensity = 5200 * qualitySettings.sunIntensityScale
        if qualitySettings.fillLightScale > 0 {
            fillLight?.light.intensity = 2100 * qualitySettings.fillLightScale
        } else if fillLight?.isEnabled == true {
            fillLight?.isEnabled = false
        }
        // Cheaper splash silhouette for every splat merged from now on. The
        // chunk size can't follow — it defines the chunk grid the already-built
        // meshes are indexed by — so it stays fixed for the whole match.
        grid?.setSimplifiedSplash(qualitySettings.simplifiedSplash)
        // Distant fighters may need freezing right away rather than at the next
        // scheduled LOD tick.
        if let camera { updateCharacterLOD(camera: camera) }
    }
}
