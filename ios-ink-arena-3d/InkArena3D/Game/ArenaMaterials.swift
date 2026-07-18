import RealityKit
import UIKit

/// Loads the AI-generated arena textures once at scene setup and hands out
/// ready-to-use materials. Every accessor degrades gracefully to a flat
/// color when a texture is missing, so the arena always builds.
@MainActor
final class ArenaMaterials {
    static let asphaltName = "asphalt_ground_texture"
    static let graffitiName = "graffiti_wall_texture"
    static let containerName = "seamless_tileable_texture"
    static let towerName = "industrial_tower_wall_texture"
    static let grateName = "metal_grate_turquoise"
    static let skyName = "cartoon_sunset_sky_panorama"
    static let skylineName = "paint_factory_skyline"
    static let billboardName = "ink_arena_billboard"

    // Temple Lost texture set.
    static let templeFloorName = "temple_stone_floor_texture"
    static let templeWallName = "mossy_temple_wall_texture"
    static let templeTechName = "ancient_temple_tech_wall"
    static let templePlanksName = "wooden_bridge_planks_texture"
    static let jungleSkyName = "jungle_temple_sky_panorama"
    static let jungleSkylineName = "jungle_ruins_skyline"

    // SplashCheese (cheese dairy) texture set.
    static let cheeseFloorName = "cheese_factory_floor"
    static let cheeseWallName = "cheese_barn_wall"
    static let cheeseMetalName = "cheese_silo_metal"
    static let cheesePlanksName = "cheese_wood_planks"
    static let cheeseRindName = "cheese_wax_block"
    static let cheeseSkyName = "cheese_factory_sky"
    static let cheeseSkylineName = "cheese_factory_skyline"

    // Vieux Bassin (Mediterranean fishing port) texture set.
    static let portFloorName = "port_quay_stone_texture"
    static let portWallName = "port_warehouse_wall_texture"
    static let portMetalName = "port_iron_plate_texture"
    static let portPlanksName = "port_boardwalk_planks_texture"
    static let portRopeName = "port_crate_rope_texture"
    static let portSkyName = "port_sunset_sky_panorama"
    static let portSkylineName = "port_town_skyline"

    private var textures: [String: TextureResource] = [:]

    /// Loads every bundled arena texture. Missing assets are simply skipped.
    static func load() async -> ArenaMaterials {
        let materials = ArenaMaterials()
        let names = [
            asphaltName, graffitiName, containerName, towerName,
            grateName, skyName, skylineName, billboardName,
            templeFloorName, templeWallName, templeTechName,
            templePlanksName, jungleSkyName, jungleSkylineName,
            cheeseFloorName, cheeseWallName, cheeseMetalName,
            cheesePlanksName, cheeseRindName, cheeseSkyName, cheeseSkylineName,
            portFloorName, portWallName, portMetalName, portPlanksName,
            portRopeName, portSkyName, portSkylineName,
        ]
        // Decode every texture in parallel. Each child task is @MainActor for
        // safe dictionary access, but `TextureResource(named:)` does its heavy
        // work off the main thread, so the decodes still overlap.
        await withTaskGroup(of: (String, TextureResource?).self) { group in
            for name in names {
                group.addTask { @MainActor in
                    (name, try? await TextureResource(named: name))
                }
            }
            for await (name, texture) in group {
                if let texture { materials.textures[name] = texture }
            }
        }
        return materials
    }

    /// Textured PBR material with tiling, or a flat fallback color.
    func pbr(
        _ name: String,
        tint: UIColor = .white,
        roughness: Float = 0.75,
        scale: SIMD2<Float> = [1, 1],
        fallback: UIColor
    ) -> any RealityKit.Material {
        guard let texture = textures[name] else {
            return SimpleMaterial(color: fallback, roughness: .init(floatLiteral: roughness), isMetallic: false)
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: tint, texture: .init(texture))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0)
        material.textureCoordinateTransform = .init(scale: scale)
        return material
    }

    /// Unlit textured material (skies, billboards, cutout backdrops).
    /// `cutout` enables alpha-threshold transparency for silhouette strips.
    func unlit(_ name: String, cutout: Bool = false) -> UnlitMaterial? {
        guard let texture = textures[name] else { return nil }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        if cutout {
            material.opacityThreshold = 0.35
        }
        return material
    }
}
