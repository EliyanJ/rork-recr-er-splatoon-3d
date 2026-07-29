import Foundation
import RealityKit
import UIKit
import simd

/// Floating name tags above characters (billboarded toward the camera).
/// Extracted verbatim from `GameController` — no behaviour change.
extension GameController {
    /// Floating billboarded name label above a character's head.
    func makeNameTag(text: String, color: UIColor) -> Entity {
        let tag = Entity()
        tag.name = "name_tag"
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.005,
            font: .systemFont(ofSize: 0.3, weight: .heavy),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        // The tag is billboarded, so the extrusion's back face and side walls
        // are never visible — back-face culling drops roughly half of the text
        // geometry's rasterization for free.
        var textMaterial = UnlitMaterial(color: color)
        textMaterial.faceCulling = .back
        let label = ModelEntity(mesh: mesh, materials: [textMaterial])
        let bounds = mesh.bounds
        label.position = [-bounds.center.x, -bounds.center.y, 0.014]

        var backingMaterial = UnlitMaterial(color: .black)
        backingMaterial.blending = .transparent(opacity: 0.42)
        backingMaterial.faceCulling = .back
        let backing = ModelEntity(
            mesh: .generatePlane(
                width: bounds.extents.x + 0.28,
                height: bounds.extents.y + 0.2,
                cornerRadius: 0.1
            ),
            materials: [backingMaterial]
        )
        tag.addChild(backing)
        tag.addChild(label)
        tag.position = [0, GameConfig.nameTagHeight, 0]
        return tag
    }

    /// Turns every name tag toward the camera (yaw-only billboard) so the
    /// pseudo stays readable whichever way the character faces.
    /// Runs the (relatively cheap but per-entity) name-tag billboard pass at a
    /// reduced cadence — the tags barely move between frames, so ~14 Hz looks
    /// identical while saving per-frame work.
    func updateNameTagsThrottled(dt: Float, camera: PerspectiveCamera) {
        nameTagAccum += dt
        guard nameTagAccum >= nameTagInterval else { return }
        nameTagAccum = 0
        updateNameTags(camera: camera)
    }

    func updateNameTags(camera: PerspectiveCamera) {
        // Lite preset drops name tags entirely — one less billboarded entity
        // update per character every refresh.
        guard qualitySettings.nameTagsEnabled else {
            if playerNameTag?.isEnabled == true { playerNameTag?.isEnabled = false }
            for bot in bots where bot.nameTag?.isEnabled == true { bot.nameTag?.isEnabled = false }
            return
        }
        let camPos = camera.position(relativeTo: nil)
        // Beyond this distance the pseudo is a couple of unreadable pixels, so
        // the preset hides it: one less billboard update and two fewer draw
        // calls (one of them blended) per distant fighter.
        let cullDistance = qualitySettings.nameTagCullDistance
        if let tag = playerNameTag {
            let visible = cameraMode == .thirdPerson && !isPlayerDown
            if tag.isEnabled != visible {
                tag.isEnabled = visible
            }
            if visible {
                billboard(tag, toward: camPos)
            }
        }
        for bot in bots where !bot.isDown {
            guard let tag = bot.nameTag else { continue }
            let visible = simd_distance(camPos, tag.position(relativeTo: nil)) <= cullDistance
            if tag.isEnabled != visible {
                tag.isEnabled = visible
            }
            if visible {
                billboard(tag, toward: camPos)
            }
        }
    }

    func billboard(_ tag: Entity, toward camPos: SIMD3<Float>) {
        let tagPos = tag.position(relativeTo: nil)
        let yaw = atan2(camPos.x - tagPos.x, camPos.z - tagPos.z)
        tag.setOrientation(simd_quatf(angle: yaw, axis: [0, 1, 0]), relativeTo: nil)
    }
}
