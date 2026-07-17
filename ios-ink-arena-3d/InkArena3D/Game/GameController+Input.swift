import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Input: touch aim/camera helpers, jump/dive/gadget triggers, and the
/// desktop keyboard/mouse bridge. Verbatim from `GameController`.
extension GameController {
    /// Manual aim: deltas steer the damped target angles — the live camera
    /// eases toward them every frame, so the view never jumps raw.
    func addAimDelta(deltaX: CGFloat, deltaY: CGFloat) {
        lastManualAimTime = elapsed
        isAutoAligning = false
        let sensitivity = Float(ProfileStore.shared.cameraSensitivity)
        targetCameraYaw -= Float(deltaX) * 0.0085 * sensitivity
        targetCameraPitch = min(
            max(targetCameraPitch - Float(deltaY) * 0.0055 * sensitivity, GameConfig.cameraMinPitch),
            GameConfig.cameraMaxPitch
        )
    }

    /// Shortest signed angular difference, wrapped to (-π, π].
    func shortestAngle(_ angle: Float) -> Float {
        atan2(sin(angle), cos(angle))
    }

    /// Toggles squid dive mode (fast swim in your own ink).
    func toggleDive() {
        guard !isPlayerDown, !isMatchOver else { return }
        setDiving(!isDiving)
    }

    /// Hold-to-swim from the sponge joystick: pressing enters the dive,
    /// releasing pops back out — dragging the same finger steers the swim.
    func setDiveHeld(_ held: Bool) {
        guard !isPlayerDown, !isMatchOver, ziplineRide == nil, held != isDiving else { return }
        if !held { cancelDiveJumpCharge() }
        setDiving(held)
    }

    /// Starts charging the dive-jump surge. The player must already be diving;
    /// while the charge holds, the sponge form stays and the jump button is
    /// considered pressed. The simulation loop fires the actual jump once the
    /// charge reaches `diveJumpChargeDuration`.
    func beginDiveJumpCharge() {
        guard isDiving, !isPlayerDown, !isMatchOver else { return }
        guard !isDivingAndChargingJump else { return }
        isDivingAndChargingJump = true
        diveJumpCharge = 0
        diveJumpChargeRatio = 0
    }

    /// Cancels an in-progress charge without firing the jump — called when the
    /// finger slides back down or the dive is released early.
    func cancelDiveJumpCharge() {
        isDivingAndChargingJump = false
        diveJumpCharge = 0
        diveJumpChargeRatio = 0
    }

    /// Advances the squid-surge charge and fires the jump automatically when
    /// it reaches the threshold. Called from the per-frame simulation loop.
    func updateDiveJumpCharge(dt: Double) {
        guard isDivingAndChargingJump, isDiving else {
            if isDivingAndChargingJump || diveJumpChargeRatio != 0 {
                isDivingAndChargingJump = false
                diveJumpCharge = 0
                diveJumpChargeRatio = 0
            }
            return
        }
        diveJumpCharge += dt
        let quantized = (min(1, diveJumpCharge / diveJumpChargeDuration) * 20).rounded() / 20
        if quantized != diveJumpChargeRatio {
            diveJumpChargeRatio = quantized
        }
        if diveJumpCharge >= diveJumpChargeDuration {
            performDiveJump()
        }
    }

    /// Fires the charged dive-jump: the player exits the dive and launches
    /// upward with a stronger jump. The charge is consumed immediately.
    private func performDiveJump() {
        cancelDiveJumpCharge()
        // Exit dive form then jump. `jump()` already exits diving and enforces
        // grounded-state, so we just give it a bigger velocity here.
        verticalVelocity = GameConfig.jumpVelocity * 1.25
        isAirborne = true
        setDiving(false)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Launches the player upward — high enough to reach the raised decks.
    /// Near a zipline endpoint the jump boards the cable instead; while
    /// riding, jumping again drops off mid-flight.
    func jump() {
        guard !isPlayerDown, !isMatchOver else { return }
        if ziplineRide != nil {
            ziplineRide = nil
            isAirborne = true
            verticalVelocity = GameConfig.jumpVelocity * 0.4
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard !isAirborne else { return }
        if isDiving { setDiving(false) }
        if let pos = playerContainer?.position, let boarding = ziplineBoarding(from: pos) {
            ziplineRide = boarding
            verticalVelocity = 0
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            heroAnimator?.playOnce(ModelCatalog.heroJump, restoreAfter: .milliseconds(500))
            return
        }
        verticalVelocity = GameConfig.jumpVelocity
        isAirborne = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        heroAnimator?.playOnce(ModelCatalog.heroJump, restoreAfter: .milliseconds(750))
    }

    /// Zipline ride starting at whichever endpoint the player stands on,
    /// or nil when no cable is within reach.
    func ziplineBoarding(from pos: SIMD3<Float>) -> (index: Int, t: Float, forward: Bool)? {
        for (index, line) in ziplines.enumerated() {
            let candidates: [(SIMD3<Float>, Bool)] = [(line.start, true), (line.end, false)]
            for (endpoint, forward) in candidates {
                let horizontal = simd_length(SIMD2<Float>(pos.x - endpoint.x, pos.z - endpoint.z))
                let feetY = endpoint.y - GameConfig.ziplineHangHeight
                if horizontal < GameConfig.ziplineAttachRadius, abs(pos.y - feetY) < 1.4 {
                    return (index, forward ? 0.02 : 0.98, forward)
                }
            }
        }
        return nil
    }

    func setDiving(_ diving: Bool) {
        guard isDiving != diving else { return }
        if !diving {
            cancelDiveJumpCharge()
            diveFormEntity?.scale = SIMD3<Float>(repeating: 1)
        }
        isDiving = diving
        applyBodyVisibility()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if diving {
            heroSetLoop(nil)
            AudioService.shared.playSplat(volume: 0.35)
        } else {
            heroSetLoop(heroStandLoop)
        }
    }

    /// Builds one grenade visual — the generated 3D model when available,
    /// otherwise a plain sphere.
    func makeGrenadeEntity() -> Entity {
        let container = Entity()
        let visual: Entity
        if let template = grenadeTemplate {
            visual = template.clone(recursive: true)
        } else {
            visual = ModelEntity(
                mesh: grenadeMesh,
                materials: [projectileMaterials[localTeam] ?? UnlitMaterial(color: localTeam.uiColor)]
            )
        }
        let spec = ModelCatalog.grenade
        attachGeneratedModelVisual(
            visual,
            to: container,
            targetSize: GameConfig.grenadeVisualSize,
            scaleAxis: .positiveY,
            anchor: .center,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: spec.localFrontAxis == nil ? nil : [0, 0, 1]
        )
        return container
    }

    /// Enters grenade aim mode: the grenade appears in the hand and the
    /// predicted trajectory + landing zone are drawn live. While held, drag
    /// (or move the camera) to redirect the throw without releasing.
    func beginGrenadeAim() {
        guard !isPlayerDown, !isMatchOver, !isAimingGrenade,
              grenadeCooldown <= 0, inkExact >= gadget.inkCost else { return }
        if gadget != .paintBomb {
            // Ink wall fires instantly on press — paint bomb uses the held
            // aim-and-throw flow.
            performInstantGadget()
            return
        }
        if isDiving { setDiving(false) }
        isAimingGrenade = true
        isFiring = false
        attachHandGrenade()
        grenadeAimRoot?.isEnabled = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Releases the held grenade: throws it along the previewed arc, or
    /// plants it as a trap when the landing zone is at the player's feet.
    func releaseGrenadeAim() {
        guard isAimingGrenade else { return }
        isAimingGrenade = false
        grenadeAimRoot?.isEnabled = false
        guard !isPlayerDown, !isMatchOver, grenadeCooldown <= 0,
              inkExact >= GameConfig.grenadeInkCost,
              let container = playerContainer else {
            removeHandGrenade()
            return
        }
        let landing = simulatedGrenadePath().last ?? container.position
        let distance = simd_length(SIMD2<Float>(
            landing.x - container.position.x,
            landing.z - container.position.z
        ))
        if distance < GameConfig.grenadePlantDistance {
            removeHandGrenade()
            plantGrenade()
        } else {
            throwGrenadeAimed()
        }
    }

    /// Cancels the aim without spending the grenade (splat, match end).
    func cancelGrenadeAim() {
        guard isAimingGrenade || handGrenade != nil else { return }
        isAimingGrenade = false
        grenadeAimRoot?.isEnabled = false
        removeHandGrenade()
    }


    /// Wires the hardware keyboard/mouse (desktop testing) into the same
    /// actions as the touch controls.
    func configureDesktopInput() {
        desktopInput.onFireChanged = { [weak self] down in
            guard let self else { return }
            if down {
                guard !self.isAimingGrenade else { return }
                self.isFiring = true
            } else {
                self.isFiring = false
            }
        }
        desktopInput.onGrenadeChanged = { [weak self] down in
            if down {
                self?.beginGrenadeAim()
            } else {
                self?.releaseGrenadeAim()
            }
        }
        desktopInput.onJump = { [weak self] in self?.jump() }
        desktopInput.onDiveToggle = { [weak self] in self?.toggleDive() }
        desktopInput.onAimDelta = { [weak self] deltaX, deltaY in
            self?.addAimDelta(deltaX: deltaX, deltaY: deltaY)
        }
    }

    func pollDesktopInput() {
        desktopInput.poll()
        if isKeyboardConnected != desktopInput.isKeyboardConnected {
            isKeyboardConnected = desktopInput.isKeyboardConnected
        }
    }
}
