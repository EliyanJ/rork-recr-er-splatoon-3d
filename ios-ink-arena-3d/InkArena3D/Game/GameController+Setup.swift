import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Scene setup & lifecycle: builds the RealityKit world, wires the
/// per-frame loop, and starts the match. Verbatim from `GameController`.
extension GameController {
    func setup(content: RealityViewCameraContent) async {
        // Deduplicate: a second make-closure invocation awaits the first build
        // rather than returning early. The old `guard worldRoot == nil` bailed
        // out WITHOUT ever setting `isSceneReady`, which left "Préparation de
        // l'arène" spinning forever whenever the first build was still running
        // or had been abandoned.
        if let existing = setupTask {
            await existing.value
            return
        }
        // Deliberately unstructured: SwiftUI cancels the make closure's task
        // when it re-evaluates the view, and a cancelled build would leave the
        // arena half-assembled with the overlay never released. This task runs
        // to completion on its own.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performSetup(content: content)
        }
        setupTask = task
        await task.value
    }

    private func performSetup(content: RealityViewCameraContent) async {
        guard worldRoot == nil else { return }
        // Whatever happens below — a missing model, a failed texture decode, a
        // cancelled load — the overlay MUST be released, otherwise the match is
        // simply unreachable. A degraded arena beats an infinite loading screen.
        defer { isSceneReady = true }
        isLocalDuel = localMatch.phase == .inMatch
        if isLocalDuel {
            // Team by network role: host = orange / left base, guest =
            // purple / right base. Both devices share one world frame, so
            // streamed coordinates are applied as-is (no mirroring).
            localTeam = localMatch.isHost ? .orange : .purple
            localMatch.onGameMessage = { [weak self] envelope in
                self?.handleNetMessage(envelope)
            }
            pendingPaintOps.removeAll()
            hostCoverage = nil
            // Step-4 host authority: only the host broadcasts the shared
            // coverage counters and the match clock.
            matchAuthority = localMatch.isHost
                ? MatchAuthority { [weak self] message in self?.localMatch.send(message) }
                : nil
        }
        // Active preset for this match: the player's Settings choice (auto
        // detected or manual). A local duel steps it down one further notch
        // automatically — the host is simulating AI, the network stream AND
        // rendering all at once, so the same preset that's smooth in solo can
        // lag in a duel.
        var quality = ProfileStore.shared.effectiveGraphicsQuality
        if isLocalDuel { quality = quality.oneStepDown }
        activeQuality = quality
        qualitySettings = .settings(for: quality)
        projectileCap = qualitySettings.projectileCap
        let root = Entity()
        worldRoot = root
        content.add(root)

        projectileMaterials[.orange] = UnlitMaterial(color: Team.orange.uiColor)
        projectileMaterials[.purple] = UnlitMaterial(color: Team.purple.uiColor)
        // Defensive reset: if this controller instance is ever reused across
        // matches, a leftover count here would silently suppress every hit
        // VFX for the whole next match.
        liveTransientVFX = 0
        // Re-parent the VFX pool to the fresh world root and pre-create a
        // handful of idle entities so the first intense fight never allocates.
        vfxPool.reset(root: root)
        vfxPool.warm(count: 24)

        // Warm the drop pool up front so a burst of fire never allocates a
        // fresh entity mid-match. Each drop is parented once and left disabled
        // until `spawnPaintDrop` acquires it.
        dropPool.removeAll(keepingCapacity: true)
        dropPool.reserveCapacity(projectileCap)
        let warmMaterial = projectileMaterials[.orange] ?? UnlitMaterial(color: .white)
        for _ in 0..<projectileCap {
            let entity = ModelEntity(mesh: dropMesh, materials: [warmMaterial])
            entity.isEnabled = false
            root.addChild(entity)
            dropPool.append(entity)
        }

        // Only the active map's textures are decoded — the training range is
        // built entirely from flat colors, so it needs none at all.
        mats = await ArenaMaterials.load(
            names: isTraining ? [] : activeMapTextureNames,
            unlit: qualitySettings.unlitArena
        )
        buildLights(root)
        if isTraining {
            addTrainingSkyDome(root)
            buildTrainingArena(root)
        } else {
            addSkyDome(root)
            // Everything under `staticRoot` never moves for the whole match,
            // which is exactly what makes it mergeable below. Spawn rings and
            // capture zones stay outside: they pulse, recolour and resize.
            let staticRoot = Entity()
            staticRoot.name = "static_arena"
            root.addChild(staticRoot)
            staticArenaRoot = staticRoot
            buildArena(staticRoot)
            buildCityBackdrop(staticRoot)
            mergeStaticArena(staticRoot)
            buildSpawnZones(root)
            buildCaptureZones(root)
        }
        walkableObstacles = obstacles.filter(\.isWalkable)
        // Build the collision broadphase from the now-complete static geometry
        // (no-op in training, which keeps the legacy linear scan).
        rebuildSpatialIndex()
        // Bot navigation grid + patrol points — needs the full static
        // geometry (obstacles, water, ramps) already built above.
        if !isTraining {
            buildBotNavigation()
        }

        liveStats = [FighterStats(id: 0, name: ProfileStore.shared.playerName, team: localTeam)]

        if let name = ModelCatalog.grenade.resourceName {
            grenadeTemplate = try? await Entity(named: name)
        }

        lastSafeGround = playerHome
        let paintGrid = PaintGrid(
            heightAt: { [weak self] x, z in
                self?.paintSurfaceHeight(atX: x, z: z) ?? 0
            },
            surfaceAt: { [weak self] x, z in
                self?.paintSurface(atX: x, z: z)
            },
            isBlocked: { [weak self] x, z in
                guard let self else { return false }
                // Water pools AND ramp footprints are unpaintable, so they are
                // excluded from the coverage denominator (only flat floor /
                // crate tops count toward map coverage).
                return self.isInWater(x: x, z: z) || self.isOnRamp(atX: x, z: z)
            },
            chunkSize: qualitySettings.paintChunkSize,
            simplifiedSplash: qualitySettings.simplifiedSplash
        )
        grid = paintGrid
        root.addChild(paintGrid.root)
        registerPaintSurfaces(on: paintGrid)

        let cam = PerspectiveCamera()
        cam.camera.fieldOfViewInDegrees = GameConfig.cameraFieldOfView
        cam.position = playerHome + SIMD3<Float>(localTeam == .orange ? -4.5 : 4.5, 1.5, 0)
        content.add(cam)
        camera = cam
        // Aim the camera toward the arena centre from the assigned base.
        cameraYaw = -baseFacing(for: localTeam)
        targetCameraYaw = cameraYaw

        await buildPlayer(root)
        if isTraining {
            buildTrainingTargets(root)
        } else {
            await buildBots(root)
        }
        buildGrenadeAimVisuals(root)
        buildSniperLaser(root)
        configureDesktopInput()
        stats = liveStats

        // Starting turf around each base.
        paintGrid.paint(atX: playerHome.x, z: playerHome.z, radius: 2.6, team: localTeam)
        if isTraining {
            // Sandbox: no ally/enemy bases to seed.
        } else if isLocalDuel {
            paintGrid.paint(atX: remoteHome.x, z: remoteHome.z, radius: 2.6, team: enemyTeam)
            // Starting turf under each lobby-added AI bot, both devices alike.
            let perTeam = min(GameConfig.duelBotsPerTeam, min(allyHomes.count, enemyHomes.count))
            for home in allyHomes.prefix(perTeam) {
                paintGrid.paint(atX: home.x, z: home.z, radius: 2.0, team: .orange)
            }
            for home in enemyHomes.prefix(perTeam) {
                paintGrid.paint(atX: home.x, z: home.z, radius: 2.0, team: .purple)
            }
        } else {
            for home in allyHomes {
                paintGrid.paint(atX: home.x, z: home.z, radius: 2.0, team: .orange)
            }
            for home in enemyHomes {
                paintGrid.paint(atX: home.x, z: home.z, radius: 2.0, team: .purple)
            }
        }

        configurePerfBisection()

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            MainActor.assumeIsolated {
                self?.update(deltaTime: Float(event.deltaTime))
            }
        }
    }

    /// Collapses the finished arena into a handful of merged meshes.
    ///
    /// The arena is ~250 entities that never move, each costing a draw call
    /// every frame for the entire match — and the traces say the frame is
    /// dominated by exactly that kind of render-submission work (83 % of the
    /// frame is spent outside our own measured code). Merging by material
    /// leaves the picture identical while collapsing those hundreds of
    /// submissions into a handful.
    ///
    /// The decorative layer is merged FIRST and on its own, so its batches
    /// stay parented to it and the "hide all decor" quality switch keeps
    /// working as a single assignment.
    private func mergeStaticArena(_ staticRoot: Entity) {
        guard qualitySettings.mergeStaticGeometry else { return }
        var stats = StaticBatcher.Stats()
        var protected: Set<ObjectIdentifier> = []
        if let decorRoot, decorRoot.parent === staticRoot {
            stats = stats + StaticBatcher.run(roots: [decorRoot])
            protected.insert(ObjectIdentifier(decorRoot))
        }
        stats = stats + StaticBatcher.run(roots: [staticRoot], protecting: protected)
        PerfRecorder.shared.noteBatching(
            absorbed: stats.absorbed,
            produced: stats.produced,
            keptAsIs: stats.keptAsIs
        )
    }

    /// Declares the visual layers the GPU subtraction sweep can switch off.
    ///
    /// Ordered cheapest-to-suspect first so a report reads like an argument:
    /// characters and decor are small, the arena and the ink surface cover the
    /// whole screen, and the sky fills every remaining pixel. The closures are
    /// evaluated at each phase start because bots die and respawn mid-match.
    private func configurePerfBisection() {
        PerfBisector.shared.configure(layers: [
            PerfBisector.Layer(label: "décor") { [weak self] in
                [self?.decorRoot].compactMap { $0 }
            },
            PerfBisector.Layer(label: "personnages") { [weak self] in
                guard let self else { return [] }
                return ([playerContainer] + bots.map(\.container)).compactMap { $0 }
            },
            PerfBisector.Layer(label: "peinture") { [weak self] in
                [self?.grid?.root].compactMap { $0 }
            },
            PerfBisector.Layer(label: "arène") { [weak self] in
                [self?.staticArenaRoot].compactMap { $0 }
            },
            PerfBisector.Layer(label: "ciel") { [weak self] in
                [self?.skyDome].compactMap { $0 }
            },
        ])
    }

    /// Hands the paint system an exact registry of the arena's ground.
    ///
    /// Everything is derived from the SAME rectangles the collision system
    /// already uses, so what can be painted matches what can be walked on:
    /// - decks: every walkable top above floor level, sorted low → high so the
    ///   highest wins wherever two overlap (a crate on a platform);
    /// - blockers: water pools — and ONLY water. Walls were briefly carved out
    ///   too, which read in play as ink refusing to stick for no reason around
    ///   every structure (collision boxes are wider than the visible wall).
    ///   Ink sliding under a wall is invisible anyway, so the old, predictable
    ///   rule is back: everything is paintable except water and ramps;
    /// - rampBlockers: ramp decks, which have never been paintable.
    ///
    /// Skipped in training: its targets slide every frame, so a baked registry
    /// would be stale — the flat sandbox floor stays fully paintable.
    private func registerPaintSurfaces(on paintGrid: PaintGrid) {
        guard !isTraining else { return }

        let decks = walkableObstacles
            .filter { $0.topY > 0.05 }
            .sorted { $0.topY < $1.topY }
            .map {
                PaintCanvasSurface.Deck(
                    centerX: $0.center.x,
                    centerZ: $0.center.z,
                    halfX: $0.halfX,
                    halfZ: $0.halfZ,
                    topY: $0.topY
                )
            }

        let blockers = waterZones.map {
            PaintSurfaceMap.Box(
                centerX: $0.center.x,
                centerZ: $0.center.y,
                halfX: $0.halfX,
                halfZ: $0.halfZ
            )
        }
        let rampBlockers = ramps.map {
            PaintSurfaceMap.OrientedBox(
                centerX: $0.center.x,
                centerZ: $0.center.y,
                axisX: $0.axis.x,
                axisZ: $0.axis.y,
                halfLength: $0.halfLength,
                halfWidth: $0.halfWidth
            )
        }

        paintGrid.configureSurfaces(
            decks: decks,
            blockers: blockers,
            rampBlockers: rampBlockers
        )
    }

    /// Called when the intro countdown ends — the match actually starts.
    func beginMatch() {
        guard !isMatchLive else { return }
        isMatchLive = true
        refreshEnemyStatuses()
    }

    func buildLights(_ root: Entity) {
        // Key light matched to each map's sky: warm sunset over the docks,
        // golden light filtering through the jungle canopy at the temple.
        let sun = DirectionalLight()
        sun.light.intensity = 5200 * qualitySettings.sunIntensityScale
        sun.light.color = sunLightColor
        sun.look(at: .zero, from: [10, 18, 10], relativeTo: nil)
        root.addChild(sun)
        sunLight = sun

        // Colored bounce so shadows stay vibrant instead of gray. Its intensity
        // scales with the active quality preset: a full bounce on Ultra/
        // Standard, dropped entirely on Performance/Lite — fewer dynamic-light
        // evaluations, no gameplay impact.
        let fillScale = qualitySettings.fillLightScale
        if fillScale > 0 {
            let fill = DirectionalLight()
            fill.light.intensity = 2100 * fillScale
            fill.light.color = fillLightColor
            fill.look(at: .zero, from: [-10, 13, -6], relativeTo: nil)
            root.addChild(fill)
            fillLight = fill
        }
    }

    /// Giant inside-out sphere carrying the sunset panorama — kills the
    /// black void behind the map. Falls back to a warm unlit dome color.
    func addSkyDome(_ root: Entity) {
        let fallbackSky = fallbackSkyColor
        // The lightest preset skips the panoramic texture lookup entirely
        // (flat unlit color) — one less texture bound for the whole match.
        let material: UnlitMaterial = qualitySettings.simplifiedSkybox
            ? UnlitMaterial(color: fallbackSky)
            : (mats?.unlit(skyTextureName) ?? UnlitMaterial(color: fallbackSky))
        let dome = ModelEntity(mesh: .generateSphere(radius: 150), materials: [material])
        // Negative X scale flips the winding so the texture renders inside.
        dome.scale = [-1, 1, 1]
        dome.position = [0, 0, 0]
        dome.name = "sky_dome"
        root.addChild(dome)
        skyDome = dome
    }

}
