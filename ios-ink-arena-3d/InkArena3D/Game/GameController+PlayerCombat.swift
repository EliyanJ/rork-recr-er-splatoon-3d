import Foundation
import RealityKit
import UIKit
import simd

/// Local player per-frame simulation: movement, aim, weapon firing,
/// weapon follow, and the sponge (dive) form. Verbatim from `GameController`.
extension GameController {
    func forwardVector() -> SIMD3<Float> {
        [-sin(cameraYaw), 0, -cos(cameraYaw)]
    }

    /// Full 3D aim direction including the camera's up/down tilt.
    func aimVector() -> SIMD3<Float> {
        let cp = cos(cameraPitch)
        return simd_normalize([-sin(cameraYaw) * cp, sin(cameraPitch), -cos(cameraYaw) * cp])
    }

    func yawQuat(for direction: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: atan2(direction.x, direction.z), axis: [0, 1, 0])
    }

    func updatePlayer(dt: Float, grid: PaintGrid, container: Entity) {
        if isPlayerDown {
            respawnTimer -= Double(dt)
            respawnCountdown = max(0, respawnTimer)
            if respawnTimer <= 0 {
                respawnPlayer(container)
            }
            return
        }
        guard !isMatchOver else { return }

        // Firing pops you out of squid form, like Splatoon.
        if isDiving, isFiring {
            setDiving(false)
        }

        let forward = forwardVector()
        let right = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))

        var moveDir: SIMD3<Float> = .zero
        // Touch joystick first, then the sponge joystick (swim + steer with
        // one finger), then the hardware keyboard (desktop testing).
        let stick: SIMD2<Float> = if simd_length(joystick) > 0.06 {
            joystick
        } else if simd_length(diveStick) > 0.06 {
            diveStick
        } else {
            desktopInput.moveVector
        }
        let magnitude = simd_length(stick)
        if magnitude > 0.06 {
            let dir = right * stick.x + forward * stick.y
            if simd_length(dir) > 0.001 {
                moveDir = simd_normalize(dir)
            }
        }

        // Auto-follow camera: smoothly steers the view behind the run
        // direction with a calm damped turn — progressive acceleration and
        // deceleration, no notches, no snapping. Small course corrections
        // never move the camera; once a turn engages it eases all the way
        // in. Paused while firing (aim lock), while aiming a grenade, and
        // shortly after a manual camera drag.
        if moveDir != .zero, !isFiring, !isAimingGrenade, cameraMode == .thirdPerson,
           elapsed - lastManualAimTime > GameConfig.cameraAutoAlignDelay {
            let desiredYaw = atan2(-moveDir.x, -moveDir.z)
            let diff = shortestAngle(desiredYaw - targetCameraYaw)
            if isAutoAligning || abs(diff) > GameConfig.cameraAutoAlignThreshold {
                isAutoAligning = abs(diff) > 0.03
                let blend = 1 - exp(-dt * GameConfig.cameraAutoAlignResponse)
                targetCameraYaw += diff * blend
            }
        } else if !isFiring {
            isAutoAligning = false
        }

        let standing = grid.team(atX: container.position.x, z: container.position.z)
        var speed = GameConfig.playerSpeed * min(magnitude, 1)
        // Weapon mobility class: every weapon carries differently — the
        // dual pistols keep you fast, the sniper and bucket slow you down.
        if !isDiving {
            speed *= weapon.moveSpeedMultiplier
        }
        // Swimming: water is a slow, exposed shortcut — faster in squid form.
        let swimmingNow = !isAirborne && ziplineRide == nil
            && container.position.y < 0.4
            && isInWater(x: container.position.x, z: container.position.z)
        if swimmingNow {
            speed *= isDiving ? GameConfig.waterDiveSpeedFactor : GameConfig.waterWadeSpeedFactor
        }
        if isDiving {
            if standing == localTeam {
                speed *= GameConfig.swimBoost * perks.swimBoostMultiplier
            } else if standing == enemyTeam {
                speed *= GameConfig.swimEnemyPaintPenalty
            } else {
                speed *= GameConfig.swimNeutralPenalty
            }
        } else {
            if standing == localTeam {
                speed *= GameConfig.ownPaintWalkBoost
            } else if standing == enemyTeam {
                speed *= GameConfig.enemyPaintPenalty
            }
        }

        var pos = container.position
        if let ride = ziplineRide {
            // Riding a zipline: the cable owns the position, weapons stay live.
            let line = ziplines[ride.index]
            let span = max(simd_distance(line.start, line.end), 0.01)
            let step = GameConfig.ziplineSpeed / span * dt
            let t = ride.t + (ride.forward ? step : -step)
            if t <= 0 || t >= 1 {
                ziplineRide = nil
                isAirborne = true
                verticalVelocity = 0
            } else {
                ziplineRide = (ride.index, t, ride.forward)
                let cable = line.start + (line.end - line.start) * t
                pos = [cable.x, cable.y - GameConfig.ziplineHangHeight, cable.z]
                container.position = pos
                if !isFiring, !isAimingGrenade {
                    let travel = (line.end - line.start) * (ride.forward ? 1 : -1)
                    let flat = SIMD3<Float>(travel.x, 0, travel.z)
                    if simd_length(flat) > 0.001 {
                        container.orientation = yawQuat(for: simd_normalize(flat))
                    }
                }
            }
        }
        if ziplineRide == nil {
            if moveDir != .zero {
                // Climb assist: while scaling a wall (isClimbing still holds
                // last frame's value here), damp horizontal input so the fast
                // upward slide doesn't fling you sideways off the painted patch.
                // Vertical intent is preserved; only sideways drift is eased.
                var frameMove = moveDir
                if isClimbing {
                    frameMove *= GameConfig.wallClimbHorizontalAssist
                }
                pos += frameMove * speed * dt
                pos = clampToArena(pos)
                pos = resolveObstacles(pos, currentY: container.position.y, team: localTeam)
                // Solid ramps: block walking under or clipping through them.
                pos = resolveRamps(pos, currentY: container.position.y)
                // The opposing spawn bubble is a hard wall for the player.
                pos = pushOutOfEnemyZone(pos, team: localTeam)
            }
            // Wall-climb: pushing into a wall covered in your ink slides you
            // up to its walkable top — painted verticality.
            let climbing = wallClimb(&pos, currentY: container.position.y, moveDir: moveDir, dt: dt)
            isClimbing = climbing
            if climbing {
                verticalVelocity = 0
                isAirborne = false
            } else if isAirborne {
                verticalVelocity -= GameConfig.gravity * dt
                var newY = container.position.y + verticalVelocity * dt
                let ground = walkableHeight(atX: pos.x, z: pos.z, currentY: max(container.position.y, newY))
                if verticalVelocity <= 0, newY <= ground {
                    newY = ground
                    isAirborne = false
                    verticalVelocity = 0
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                pos.y = max(newY, 0)
            } else {
                pos.y = settledHeight(from: container.position.y, atX: pos.x, z: pos.z, dt: dt)
            }
            // Water is swimmable: the body sinks waist-deep and the crossing
            // is slow and exposed — a risky shortcut, never a punitive death.
            if !isAirborne, pos.y < 0.4, isInWater(x: pos.x, z: pos.z) {
                pos.y = GameConfig.waterSinkDepth
                if !wasInWater {
                    wasInWater = true
                    AudioService.shared.playSplat(volume: 0.45)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            } else {
                if !isAirborne {
                    lastSafeGround = pos
                }
                wasInWater = false
            }
            container.position = pos
        }

        // In first person the body always faces the camera direction (true
        // POV); in third person it faces the aim while firing or holding
        // the grenade, else the run direction.
        if isFiring || isAimingGrenade || cameraMode == .firstPerson {
            container.orientation = yawQuat(for: forward)
        } else if moveDir != .zero, ziplineRide == nil {
            container.orientation = yawQuat(for: moveDir)
        }

        // Fire edge: play the weapon-draw animation before the jet starts.
        let firingNow = isFiring && !isDiving && !isAimingGrenade
        if firingNow, !wasFiring {
            fireStanceStart = elapsed
            if weapon == .charger {
                chargeLevel = 0
                chargeConsumed = false
                if let fireLoop = ModelCatalog.heroFire {
                    heroSetLoop(fireLoop)
                }
            } else {
                if let fireLoop = ModelCatalog.heroFire {
                    heroSetLoop(fireLoop)
                }
                heroAnimator?.playOnce(ModelCatalog.heroDraw, restoreAfter: .milliseconds(620))
            }
        }
        // Charger: releasing fires the charged sniper shot (unless the full
        // charge already auto-fired), then the gauge resets.
        if !firingNow, wasFiring, weapon == .charger {
            if !chargeConsumed {
                fireChargedShot()
            }
            chargeLevel = 0
            chargeConsumed = false
        }
        wasFiring = firingNow

        if isDiving {
            heroSetLoop(nil)
            if isClimbing {
                // Climbing happens strictly in sponge form: drive a procedural
                // scaling motion on the sponge instead of the authored human
                // climb loop (which stays reserved for a possible future flow).
                updateDiveClimb()
            } else {
                updateDiveForm(onOwnPaint: standing == localTeam)
            }
        } else if isClimbing {
            // Dedicated wall-climb loop while scaling a painted wall.
            heroSetLoop(ModelCatalog.heroClimb ?? heroRunLoop)
        } else if firingNow {
            if let fireLoop = ModelCatalog.heroFire {
                heroSetLoop(fireLoop)
            }
        } else {
            heroSetLoop(moveDir != .zero ? heroRunLoop : heroStandLoop)
        }

        let drawDone = elapsed - fireStanceStart >= GameConfig.weaponDrawDelay
        fireTimer -= Double(dt)

        // Charger charge-and-hold: the gauge fills while the button is held
        // (capped by the available ink). A full charge NEVER auto-fires —
        // the player can hold the max charge indefinitely (waiting for a
        // target) and releasing ALWAYS fires the shot.
        if firingNow, weapon == .charger, !chargeConsumed {
            let inkCap = max(0.15, min(1, inkExact / GameConfig.chargerMaxInkCost))
            chargeLevel = min(chargeLevel + dt / GameConfig.chargerChargeDuration, inkCap)
        }

        // Machine-gun heat: cools continuously, hard-locks when full until
        // the barrel has fully recovered.
        if weapon == .rapid {
            if isOverheated {
                heatExact = max(0, heatExact - GameConfig.rapidCoolPerSecond * 1.35 * dt)
                if heatExact <= GameConfig.rapidOverheatUnlockLevel {
                    heatExact = 0
                    isOverheated = false
                }
            } else if !(firingNow && drawDone) {
                heatExact = max(0, heatExact - GameConfig.rapidCoolPerSecond * dt)
            }
            publishHeat()
        } else if heatExact != 0 || isOverheated {
            heatExact = 0
            isOverheated = false
            publishHeat()
        }

        let jetActive = firingNow && weapon != .charger
            && drawDone && inkExact >= weapon.inkCostPerShot
            && !(weapon == .rapid && isOverheated)
        if jetActive, fireTimer <= 0 {
            fireTimer = weapon.fireInterval
            inkExact -= weapon.inkCostPerShot
            let rawOrigin = muzzleEntity?.position(relativeTo: nil)
                ?? (container.position + aimVector() * 0.5 + SIMD3<Float>(0, GameConfig.weaponSocketPosition.y, 0))
            let origin = visualFireOrigin(rawMuzzle: rawOrigin, container: container)
            var dir = convergedAimDirection(from: origin)
                + right * Float.random(in: -weapon.spread...weapon.spread)
            dir.y += Float.random(in: -0.02...0.02)
            dir = simd_normalize(dir)
            switch weapon {
            case .bucket:
                fireBucketLob(from: origin, direction: dir)
            case .dual:
                fireDualPair(origin: origin, direction: dir, right: right)
            default:
                // Jets chain three droplets back along the direction so the
                // stream has no visible gaps.
                spawnJetDrop(at: origin, direction: dir, team: localTeam, weapon: weapon)
                spawnJetDrop(at: origin - dir * 0.24, direction: dir, team: localTeam, weapon: weapon)
                spawnJetDrop(at: origin - dir * 0.48, direction: dir, team: localTeam, weapon: weapon)
                sendFire(kind: .jet, origin: origin, direction: dir)
            }
            if weapon == .rapid {
                heatExact = min(1, heatExact + GameConfig.rapidHeatPerShot)
                if heatExact >= 1 {
                    isOverheated = true
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                publishHeat()
            }
            triggerMuzzleEffects()
            if elapsed - lastJetSfx > 0.14 {
                lastJetSfx = elapsed
                AudioService.shared.playSplat(volume: 0.2)
            }
        } else if !isFiring {
            let regen = (isDiving && standing == localTeam)
                ? GameConfig.swimInkRegenPerSecond
                : GameConfig.inkRegenPerSecond
            inkExact = min(GameConfig.maxInk, inkExact + regen * perks.inkRegenMultiplier * dt)
        }

        // Spray cone stays visible for the whole burst with a fast flicker.
        if let spray = sprayCone {
            spray.isEnabled = jetActive
            if jetActive {
                spray.scale = SIMD3<Float>(repeating: 0.9 + 0.25 * abs(sinf(Float(elapsed) * 40)))
            }
        }

        // HP regeneration — faster while submerged in friendly ink: the
        // delay before it kicks in is shorter and each tick is quicker, so
        // diving visibly refills the health bar without being instant.
        let submergedInFriendly = isDiving && standing == localTeam
        let regenDelay = submergedInFriendly ? 0.30 : GameConfig.hpRegenDelay
        let regenInterval = submergedInFriendly
            ? 0.40 * perks.hpRegenMultiplier
            : GameConfig.hpRegenInterval * perks.hpRegenMultiplier
        if playerHP < GameConfig.playerMaxHP, elapsed - lastDamageTime > regenDelay {
            hpRegenTick -= Double(dt)
            if hpRegenTick <= 0 {
                hpRegenTick = regenInterval
                playerHP = min(GameConfig.playerMaxHP, playerHP + 1)
            }
        }
    }

    /// Publishes the machine-gun heat gauge in coarse steps so the HUD
    /// never re-renders every frame.
    func publishHeat() {
        let quantized = (heatExact * 25).rounded() / 25
        if quantized != heatLevel {
            heatLevel = quantized
        }
    }

    /// Bucket launcher: one huge paint blob lobbed in a high arc — it
    /// splashes a wide disc of turf on landing and damages anyone nearby.
    func fireBucketLob(from origin: SIMD3<Float>, direction: SIMD3<Float>) {
        var lob = direction
        lob.y += GameConfig.bucketLobLift
        lob = simd_normalize(lob)
        spawnPaintDrop(
            at: origin,
            direction: lob,
            team: localTeam,
            speed: WeaponType.bucket.projectileSpeed,
            gravity: WeaponType.bucket.projectileGravity,
            damage: WeaponType.bucket.damagePerHit,
            paintRadius: WeaponType.bucket.paintRadius,
            dropScale: 3.2,
            ownerIndex: 0,
            splashRange: GameConfig.bucketSplashRange,
            hitRadius: GameConfig.characterHitRadius + 0.35
        )
        sendFire(kind: .bucket, origin: origin, direction: lob)
        weaponRecoil = 0.18
        AudioService.shared.playSplat(volume: 0.45)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Dual pistols: the right hand fires immediately, the left hand follows
    /// a beat later — landing both shots rewards accurate tracking.
    func fireDualPair(origin: SIMD3<Float>, direction: SIMD3<Float>, right: SIMD3<Float>) {
        spawnJetDrop(at: origin, direction: direction, team: localTeam, weapon: .dual)
        sendFire(kind: .jet, origin: origin, direction: direction)
        let leftOrigin = origin - right * GameConfig.dualOffhandOffset
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(GameConfig.dualStaggerDelay * 1000)))
            guard let self, !self.isPlayerDown, !self.isMatchOver else { return }
            let dir = simd_normalize(direction + right * Float.random(in: -0.02...0.02))
            self.spawnJetDrop(at: leftOrigin, direction: dir, team: self.localTeam, weapon: .dual)
        }
    }

    /// Releases the charger's single straight-line sniper shot. The longer
    /// the hold, the faster, larger and more expensive the shot — a full
    /// charge drains more than half the ink tank. Not spammable.
    func fireChargedShot() {
        guard !chargeConsumed, !isPlayerDown, !isMatchOver,
              let container = playerContainer else { return }
        chargeConsumed = true
        let charge = chargeLevel
        guard charge >= GameConfig.chargerMinCharge,
              inkExact >= GameConfig.chargerMinInkCost else { return }

        let cost = GameConfig.chargerMinInkCost
            + (GameConfig.chargerMaxInkCost - GameConfig.chargerMinInkCost) * charge
        inkExact = max(0, inkExact - cost)

        container.orientation = yawQuat(for: forwardVector())
        let rawOrigin = muzzleEntity?.position(relativeTo: nil)
            ?? (container.position + aimVector() * 0.5 + SIMD3<Float>(0, GameConfig.weaponSocketPosition.y, 0))
        let origin = visualFireOrigin(rawMuzzle: rawOrigin, container: container)
        // Converge on the screen-center target so the sniper hits exactly
        // what the fixed reticle covers — even a head peeking over cover.
        let dir = convergedAimDirection(from: origin)
        let speed = GameConfig.chargerMinSpeed
            + (GameConfig.chargerMaxSpeed - GameConfig.chargerMinSpeed) * charge
        // 50%+ charge = guaranteed kill, derived from the target's max HP so
        // HP balancing changes never break the sniper rule. In a local duel
        // the target is the remote PLAYER (bigger HP pool), never a bot.
        let damage = GameConfig.chargerDamage(
            charge: charge,
            targetMaxHP: isLocalDuel ? GameConfig.playerMaxHP : GameConfig.maxHP
        )
        let radius = GameConfig.chargerMinPaintRadius
            + (GameConfig.chargerMaxPaintRadius - GameConfig.chargerMinPaintRadius) * charge

        // Main slug plus two slower droplets that land short of it, painting
        // a strip of turf along the firing line.
        spawnPaintDrop(
            at: origin, direction: dir, team: localTeam,
            speed: speed, gravity: GameConfig.chargerShotGravity,
            damage: damage, paintRadius: radius, dropScale: 1.3 + charge * 1.2
        )
        spawnPaintDrop(
            at: origin, direction: dir, team: localTeam,
            speed: speed * 0.72, gravity: GameConfig.chargerShotGravity * 2.4,
            damage: 1, paintRadius: radius * 0.7, dropScale: 1.1
        )
        spawnPaintDrop(
            at: origin, direction: dir, team: localTeam,
            speed: speed * 0.45, gravity: GameConfig.chargerShotGravity * 3.8,
            damage: 1, paintRadius: radius * 0.55, dropScale: 0.9
        )
        sendFire(kind: .charged, origin: origin, direction: dir, charge: charge)

        heroAnimator?.playOnce(ModelCatalog.heroDraw, restoreAfter: .milliseconds(500))
        triggerMuzzleEffects()
        weaponRecoil = 0.12 + charge * 0.1
        AudioService.shared.playSplat(volume: 0.3 + charge * 0.3)
        UIImpactFeedbackGenerator(style: charge > 0.7 ? .heavy : .medium).impactOccurred()
    }

    /// Muzzle flash pop + weapon recoil kick.
    func triggerMuzzleEffects() {
        weaponRecoil = 0.1
        if let flash = muzzleFlash {
            flash.isEnabled = true
            flash.scale = SIMD3<Float>(1, 1, 1.7) * Float.random(in: 0.8...1.25)
            flashUntil = elapsed + 0.08
        }
    }

    /// Glues the weapon to the character's animated hand joint every frame
    /// — the weapon bobs with the run, sits close to the body at idle, and
    /// follows every clip instead of staying frozen at a fixed point. Falls
    /// back to the static rest position when no skeleton is visible (first
    /// person, sponge form).
    func updateWeaponEffects(dt: Float) {
        if weaponRecoil > 0 {
            weaponRecoil = max(0, weaponRecoil - dt * 0.9)
        }
        if let container = playerContainer, let socket = weaponSocket, socket.isEnabled {
            let blend = min(1, dt * GameConfig.weaponFollowLerpSpeed)
            let targetPosition = heroHandTracker.handPosition(in: container)
                .map { $0 + GameConfig.weaponHandOffset } ?? weaponRestPosition
            let targetOrientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            let targetScale: Float = 1
            weaponFollowPosition += (targetPosition - weaponFollowPosition) * blend
            weaponFollowScale += (targetScale - weaponFollowScale) * blend
            socket.position = weaponFollowPosition - SIMD3<Float>(0, 0, weaponRecoil)
            socket.orientation = simd_slerp(socket.orientation, targetOrientation, blend)
            socket.scale = SIMD3<Float>(repeating: weaponFollowScale)
            // Off-hand pistol mirrors the main hand across the body.
            if let offhand = offhandSocket {
                offhand.position = [
                    -weaponFollowPosition.x,
                    weaponFollowPosition.y,
                    weaponFollowPosition.z - weaponRecoil * 0.6,
                ]
                offhand.orientation = socket.orientation
            }
        }
        if flashUntil > 0, elapsed >= flashUntil {
            flashUntil = 0
            muzzleFlash?.isEnabled = false
        }
    }

    /// Bobbing of the sponge form while swimming through friendly paint.
    /// The sponge swells and pulses when the squid-surge jump is charging,
    /// so the player can see the 0.5 s charge building even without looking
    /// at the controls.
    func updateDiveForm(onOwnPaint: Bool) {
        guard let form = diveFormEntity else { return }
        let chargeRatio = Float(diveJumpCharge / diveJumpChargeDuration)
        if chargeRatio > 0 {
            let surge = 1 + chargeRatio * 0.22 + 0.08 * sinf(Float(elapsed) * 18)
            form.scale = [surge, surge, surge]
        } else if form.scale.x != 1 {
            form.scale = SIMD3<Float>(repeating: 1)
        }
        if onOwnPaint {
            let bob = sinf(Float(elapsed) * 9) * 0.08
            form.position = [0, 0.05 + bob, 0]
        } else {
            form.position = [0, 0.25, 0]
        }
    }

    /// Procedural climb motion for the sponge form while scaling a wall.
    /// No authored 3D clip: the vertical rise is already carried by the
    /// container's `pos.y`, so here we add a local hand-over-hand feel — a
    /// slight left/right sway plus a small pulsing reach that reads as the
    /// sponge pushing itself up the painted face.
    func updateDiveClimb() {
        guard let form = diveFormEntity else { return }
        let t = Float(elapsed) * 8.5
        let sway = sinf(t) * 0.07
        let reach = abs(sinf(t)) * 0.11
        form.position = [sway, 0.12 + reach, 0]
        // Gentle roll into the sway so the sponge leans with each reach.
        form.orientation = simd_quatf(angle: sway * 0.9, axis: [0, 0, 1])
    }
}
