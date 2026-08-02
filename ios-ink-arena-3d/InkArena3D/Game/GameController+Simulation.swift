import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// The per-frame simulation loop (`update(deltaTime:)`) that drives every
/// subsystem each image. Verbatim from `GameController` — no behaviour change.
extension GameController {
    func update(deltaTime rawDt: Float) {
        guard isSceneReady, let grid, let playerContainer, let camera else { return }

        // Sampled BEFORE the FPS governor: the overlay must show the real
        // display rate, not the paced simulation rate.
        updatePerfMonitor(rawDt: rawDt)

        // Real FPS governor: paces the whole simulation to the target rate
        // chosen in Settings (30/60/120). Skipped frames leave the scene
        // untouched, so CPU cost and motion updates genuinely follow the
        // setting instead of being cosmetic.
        var dt = rawDt
        // Real time elapsed since the last SIMULATED frame — with the governor
        // on, that is the accumulated carry, not just the last display frame.
        var realDt = rawDt
        let targetFPS = ProfileStore.shared.targetFPS
        if targetFPS < displayMaxFPS {
            frameCarry += rawDt
            let interval = 1 / Float(targetFPS)
            guard frameCarry >= interval - 0.001 else { return }
            dt = frameCarry
            realDt = frameCarry
            frameCarry = 0
        }
        // Clamp hitch spikes so one slow frame never teleports the physics or
        // makes the camera lurch to catch up. This deliberately trades real
        // time for stability: below the clamp the world genuinely runs in slow
        // motion, so the threshold sits low (15 FPS) — far under any framerate
        // we ship at, and only ever hit by a one-off hitch.
        dt = min(dt, 1 / 15)
        // Wall-clock time actually elapsed, unaffected by the hitch clamp. The
        // match countdown, the VFX expiry clock and the network authority all
        // run on THIS: a hitch used to stretch a 3-minute match past 3 minutes
        // and leave hit effects lingering, because everything shared the
        // clamped physics step.
        let clockDt = Double(realDt)
        let dtd = Double(dt)
        elapsed += clockDt
        // Recycle any expired hit/kill/burst VFX. Runs every frame (even while
        // the intro overlay idles) so lingering effects are torn down without
        // per-event async tasks. Freed budgeted entities restore the live count.
        let perf = PerfRecorder.shared
        perf.measure(.vfx) {
            liveTransientVFX = max(0, liveTransientVFX - vfxPool.tick(now: elapsed))
        }
        updateQualityAutoDowngrade(dt: dt, rawDt: rawDt)

        // Before the intro countdown ends the scene only idles: camera,
        // animations and weapon follow run so the arena looks alive behind
        // the loading overlay, but no clock, no bots, no combat.
        if !isMatchLive {
            heroAnimator?.cancelHorizontalRootMotion()
            updateWeaponEffects(dt: dt)
            updateCamera(dt: dt, target: playerContainer.position, camera: camera)
            updateNameTagsThrottled(dt: dt, camera: camera)
            updateCharacterLODThrottled(dt: dt, camera: camera)
            return
        }

        // The trace only covers live play: the intro idle would dilute every
        // average with frames where nothing is simulated.
        startPerfRecordingIfArmed()
        perf.noteFrame(rawDt: rawDt)

        // Training is a pure sandbox: no clock, no end-of-match.
        if !isMatchOver && !isTraining {
            timeLeftExact = max(0, timeLeftExact - clockDt)
            // Publish only when the displayed second changes — the HUD
            // timer no longer forces a SwiftUI re-render on every frame.
            let displaySeconds = timeLeftExact.rounded(.up)
            if displaySeconds != timeRemaining {
                timeRemaining = displaySeconds
            }
            if timeLeftExact <= 0 {
                endMatch()
            }
        }

        if grenadeCooldownExact > 0 {
            grenadeCooldownExact = max(0, grenadeCooldownExact - dtd)
            let quantized = (grenadeCooldownExact * 10).rounded() / 10
            if quantized != grenadeCooldown {
                grenadeCooldown = quantized
            }
        }
        // Ink gauge publishes in 2-unit steps for the same reason.
        let inkQuantized = (inkExact / 2).rounded() * 2
        if inkQuantized != inkLevel {
            inkLevel = inkQuantized
        }
        playerFlinchTimer = max(0, playerFlinchTimer - dtd)

        // Damped camera steering: the live angles ease toward their targets
        // with framerate-independent exponential smoothing — raw finger
        // deltas never hit the camera directly, so rotation stays calm and
        // consistent at 30 or 60 fps.
        let aimBlend = 1 - exp(-dt * GameConfig.cameraAimSmoothing)
        cameraYaw += shortestAngle(targetCameraYaw - cameraYaw) * aimBlend
        cameraPitch += (targetCameraPitch - cameraPitch) * aimBlend
        // Keep both angles bounded so long sessions never lose precision.
        if abs(targetCameraYaw) > .pi * 4 {
            let wrapped = shortestAngle(targetCameraYaw)
            cameraYaw += wrapped - targetCameraYaw
            cameraYaw = shortestAngle(cameraYaw)
            targetCameraYaw = wrapped
        }

        pollDesktopInput()
        perf.measure(.player) {
            updatePlayer(dt: dt, grid: grid, container: playerContainer)
            updateDiveJumpCharge(dt: dtd)
        }
        if isLocalDuel {
            perf.measure(.network) {
                networkTick(dt: dt)
                flushNetPaintOps(dt: dtd)
                duelBotNetTick(dt: dt)
                if !isMatchOver {
                    matchAuthority?.tick(
                        dt: clockDt,
                        remaining: timeLeftExact,
                        orange: grid.orangeCount,
                        purple: grid.purpleCount,
                        total: grid.totalCount,
                        modeScores: currentModeScores
                    )
                }
            }
        }
        heroAnimator?.cancelHorizontalRootMotion()
        perf.measure(.weapons) {
            updateWeaponEffects(dt: dt)
            updateGrenadeAim()
        }
        perf.measure(.bots) {
            if isTraining {
                updateTrainingTargets(dt: dt)
            } else {
                updateBots(dt: dt, grid: grid)
            }
        }
        perf.measure(.projectiles) {
            updateProjectiles(dt: dt, grid: grid)
            updatePlantedBombs(grid: grid)
        }
        perf.measure(.scoring) {
            updateCaptureZones(dt: dt)
            updateCoverage(dt: dtd, grid: grid)
        }
        perf.measure(.camera) {
            updateCamera(dt: dt, target: playerContainer.position, camera: camera)
        }
        perf.measure(.weapons) {
            updateSniperLaser()
            updateAimLock(container: playerContainer)
        }
        perf.measure(.nameTags) {
            updateNameTagsThrottled(dt: dt, camera: camera)
        }
        perf.measure(.lod) {
            updateCharacterLODThrottled(dt: dt, camera: camera)
        }

        // Merge tiles painted since the last flush into their chunk meshes,
        // throttled by the active quality preset's `paintRebuildInterval` so
        // a continuous jet doesn't force a mesh rebuild every single frame
        // (ownership + coverage already updated instantly when painted, only
        // this visual merge is paced).
        perf.measure(.paint) {
            if grid.usesTexturePaint {
                // Texture paint: no mesh is ever rebuilt. Only the rectangle of
                // the ink image touched since the last tick goes to the GPU — a
                // cost that stays flat from 0% to 100% coverage.
                grid.flushCanvas(dt: dt)
            } else {
                paintFlushAccum += dt
                if paintFlushAccum >= qualitySettings.paintRebuildInterval {
                    paintFlushAccum = 0
                    grid.flushPaintBatches(maxRebuilds: qualitySettings.maxChunkRebuildsPerFlush)
                }
            }
        }
        perf.noteCounts(
            projectiles: projectiles.count,
            bots: bots.count,
            vfx: liveTransientVFX,
            paintTiles: grid.paintedTileCount,
            uploads: grid.canvasUploadCount,
            stamps: grid.canvas.stampCount
        )
        refreshPaintPerfDebug(grid: grid)
    }

    /// Opens a performance trace on the first live frame when the player armed
    /// the recorder in Settings. Snapshotting the context here (rather than at
    /// setup) guarantees the preset recorded is the one actually in force,
    /// including any auto-downgrade already applied.
    private func startPerfRecordingIfArmed() {
        let recorder = PerfRecorder.shared
        guard !recorder.isRecording, ProfileStore.shared.perfRecorderEnabled else { return }
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        recorder.start(context: PerfRunContext(
            device: PerfSampler.deviceModelIdentifier(),
            systemVersion: UIDevice.current.systemVersion,
            appVersion: "\(version) (\(build))",
            quality: activeQuality.rawValue,
            autoQuality: ProfileStore.shared.autoGraphicsQuality,
            targetFPS: ProfileStore.shared.targetFPS,
            displayMaxFPS: displayMaxFPS,
            map: ProfileStore.shared.selectedMap.displayName,
            mode: matchMode.displayName,
            weapon: weapon.displayName,
            texturePaint: grid?.usesTexturePaint ?? false,
            botCount: bots.count,
            isLocalDuel: isLocalDuel,
            isTraining: isTraining
        ))
    }

    /// Tracks sustained frame time; if the game runs under 45 FPS for more
    /// than 2 seconds, steps the active quality preset down ONE notch (never
    /// back up mid-match) and shows a brief on-screen notice. It can fire
    /// again — all the way down to Lite — but only after an 8-second
    /// cooldown per step, so a genuinely struggling device (iPhone 12/13)
    /// always ends up on a preset it can actually hold instead of staying
    /// stuck one notch too high.
    private func updateQualityAutoDowngrade(dt: Float, rawDt: Float) {
        if qualityNoticeTimer > 0 {
            qualityNoticeTimer -= rawDt
            if qualityNoticeTimer <= 0 { qualityDowngradeNotice = nil }
        }
        if autoDowngradeCooldown > 0 {
            autoDowngradeCooldown -= rawDt
            sustainedSlowTime = 0
            return
        }
        guard activeQuality != .lite, isMatchLive else { return }
        // Use the raw (unpaced) frame time so a deliberate 30 FPS target
        // isn't mistaken for a struggling device.
        if rawDt > (1.0 / 45.0) {
            sustainedSlowTime += rawDt
        } else {
            sustainedSlowTime = max(0, sustainedSlowTime - rawDt * 2)
        }
        guard sustainedSlowTime > 2 else { return }
        sustainedSlowTime = 0
        autoDowngradeCooldown = 8
        activeQuality = activeQuality.oneStepDown
        qualitySettings = .settings(for: activeQuality)
        projectileCap = qualitySettings.projectileCap
        // Everything the new preset can still change on an already-built scene:
        // decor, lights, splash detail, character LOD. Without this the
        // downgrade only affected the knobs read live each frame, leaving the
        // heaviest offenders (dynamic lights, decorative geometry) in place on
        // the very device that just told us it can't cope.
        reapplyRuntimeQuality()
        qualityDowngradeNotice = "Qualité ajustée pour préserver la fluidité"
        qualityNoticeTimer = 3
    }

    /// Publishes the FPS / CPU / RAM overlay at 2 Hz while enabled in
    /// Settings. The between-publish cost is two counter increments; the Mach
    /// samplers only run when a snapshot is actually published.
    private func updatePerfMonitor(rawDt: Float) {
        guard ProfileStore.shared.perfOverlayEnabled else {
            if perfStats != nil { perfStats = nil }
            return
        }
        perfFrameCount += 1
        perfTimeAccum += rawDt
        guard perfTimeAccum >= 0.5, perfFrameCount > 0 else { return }
        let avgFrame = perfTimeAccum / Float(perfFrameCount)
        let stats = PerfStats(
            fps: Int((1 / max(avgFrame, 0.0001)).rounded()),
            frameMs: (Double(avgFrame) * 10_000).rounded() / 10,
            cpuPercent: (PerfSampler.cpuUsagePercent() * 10).rounded() / 10,
            memoryMB: PerfSampler.memoryFootprintMB()
        )
        perfFrameCount = 0
        perfTimeAccum = 0
        if stats != perfStats { perfStats = stats }
    }

    /// Publishes and logs the live paint draw-call counts when the debug flag
    /// is enabled — lets us compare batched vs legacy cost without Instruments.
    func refreshPaintPerfDebug(grid: PaintGrid) {
        guard GameConfig.paintPerfDebug else {
            if paintPerfStats != nil { paintPerfStats = nil }
            return
        }
        let stats = PaintPerfStats(
            activeEntities: grid.activePaintEntities,
            legacyDrawCalls: grid.paintedTileCount,
            usesTexture: grid.usesTexturePaint,
            canvasStamps: grid.canvas.stampCount,
            canvasPixels: grid.canvas.writtenPixelCount,
            canvasUploads: grid.canvasUploadCount,
            lastStampX: grid.canvas.lastStampX,
            lastStampY: grid.canvas.lastStampY
        )
        if stats != paintPerfStats { paintPerfStats = stats }
        if elapsed - lastPaintPerfLog > 0.5 {
            lastPaintPerfLog = elapsed
            NSLog("[PaintPerf] texture=\(stats.usesTexture) stamps=\(stats.canvasStamps) px=\(stats.canvasPixels) uploads=\(stats.canvasUploads) last=(\(stats.lastStampX),\(stats.lastStampY)) tiles=\(stats.legacyDrawCalls)")
        }
    }

    /// Red targeting laser of the Sniper — a thin beam from the muzzle to
    /// the exact aim point, visible to everyone while the charge is held,
    /// so victims can spot the sniper before the one-shot lands.
    func buildSniperLaser(_ root: Entity) {
        var beamMaterial = UnlitMaterial(color: UIColor(red: 1, green: 0.12, blue: 0.12, alpha: 1))
        beamMaterial.blending = .transparent(opacity: 0.72)
        let beam = ModelEntity(
            mesh: .generateBox(size: [GameConfig.laserThickness, GameConfig.laserThickness, 1]),
            materials: [beamMaterial]
        )
        beam.isEnabled = false
        root.addChild(beam)
        laserBeam = beam

        let dot = ModelEntity(
            mesh: .generateSphere(radius: 0.07),
            materials: [UnlitMaterial(color: UIColor(red: 1, green: 0.15, blue: 0.15, alpha: 1))]
        )
        dot.isEnabled = false
        root.addChild(dot)
        laserDot = dot
    }

    func updateSniperLaser() {
        guard let beam = laserBeam, let dot = laserDot else { return }
        let active = weapon == .charger && isFiring && !isDiving && !isPlayerDown
            && !isMatchOver && !isAimingGrenade && isMatchLive
        guard active, let muzzle = muzzleEntity else {
            if beam.isEnabled {
                beam.isEnabled = false
                dot.isEnabled = false
            }
            return
        }
        let origin = muzzle.position(relativeTo: nil)
        let target = aimTargetPoint()
        let delta = target - origin
        let length = simd_length(delta)
        guard length > 0.4 else {
            if beam.isEnabled {
                beam.isEnabled = false
                dot.isEnabled = false
            }
            return
        }
        let dir = delta / length
        beam.isEnabled = true
        dot.isEnabled = true
        beam.position = origin + dir * (length / 2)
        beam.orientation = simd_quatf(from: [0, 0, 1], to: dir)
        beam.scale = [1, 1, length]
        dot.position = target
        dot.scale = SIMD3<Float>(repeating: 1 + 0.3 * abs(sinf(Float(elapsed) * 9)))
    }

}
