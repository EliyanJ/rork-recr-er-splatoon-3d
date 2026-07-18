import Foundation
import RealityKit
import SwiftUI
import UIKit
import simd

/// Characters: hero + bot model assembly, weapon sockets, dive form.
/// Verbatim from `GameController` — no behaviour change.
extension GameController {
    func buildPlayer(_ root: Entity) async {
        let skin = ProfileStore.shared.selectedSkin
        let spec = skin.spec
        let container = await makeGeneratedModelContainer(
            resourceName: spec.resourceName,
            targetSize: GameConfig.characterHeight,
            anchor: .bottom,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: [0, 0, 1],
            worldPosition: playerHome,
            fallback: { Self.fallbackCharacter(team: localTeam) }
        )
        container.orientation = simd_quatf(angle: baseFacing(for: localTeam), axis: [0, 1, 0])
        root.addChild(container)
        playerContainer = container
        heroRuntime = container.findEntity(named: "generated_model_runtime")

        addBlobShadow(to: container)
        let tag = makeNameTag(text: ProfileStore.shared.playerName, color: localTeam.uiColor)
        container.addChild(tag)
        playerNameTag = tag
        await attachPlayerWeaponRig(to: container)
        await buildDiveForm(in: container)
        attachAccessory(to: container)

        let animator = GeneratedModelAnimationPlayer(container: container)
        await animator.preload(
            [
                ModelCatalog.heroIdle, ModelCatalog.heroRun, ModelCatalog.heroVictory,
                ModelCatalog.heroSplat, ModelCatalog.heroFire, ModelCatalog.heroJump,
                ModelCatalog.heroDraw,
                ModelCatalog.heroThrow, ModelCatalog.heroPlant, ModelCatalog.heroArmedIdle,
                ModelCatalog.heroHit, ModelCatalog.heroInjuredRun, ModelCatalog.heroInjuredIdle,
                skin.idleAnim, skin.runAnim, skin.jumpAnim, skin.armedIdleAnim,
                skin.victoryAnim, skin.hitAnim, skin.injuredIdleAnim, skin.injuredRunAnim,
            ]
            .compactMap { $0 }
        )
        heroAnimator = animator
        heroSetLoop(heroStandLoop)
        applyBodyVisibility()
    }

    /// Attaches the cosmetic accessory (tinted with the player's accent
    /// color) chosen in the locker room — purely visual, shown both there
    /// and in-match. Safe no-op for `.none`.
    func attachAccessory(to container: Entity) {
        let accessory = ProfileStore.shared.selectedAccessory
        guard accessory != .none else { return }
        let accentColor = UIColor(ProfileStore.shared.accentColor)
        let material = SimpleMaterial(color: accentColor, roughness: 0.35, isMetallic: true)
        let mesh: MeshResource
        let localPosition: SIMD3<Float>
        switch accessory {
        case .none:
            return
        case .band:
            mesh = .generateBox(size: [0.62, 0.09, 0.62], cornerRadius: 0.04)
            localPosition = [0, GameConfig.characterHeight * 0.92, 0]
        case .cape:
            mesh = .generateBox(size: [0.5, 0.6, 0.06], cornerRadius: 0.03)
            localPosition = [0, GameConfig.characterHeight * 0.72, -0.18]
        case .visor:
            mesh = .generateBox(size: [0.5, 0.12, 0.14], cornerRadius: 0.03)
            localPosition = [0, GameConfig.characterHeight * 0.9, 0.22]
        }
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "player_accessory"
        entity.position = localPosition
        container.addChild(entity)
    }

    /// Sponge dive form shown while submerged in paint — the generated 3D
    /// sponge when available, otherwise a simple squishy blob.
    func buildDiveForm(in container: Entity) async {
        let form = Entity()
        form.name = "dive_form"
        let spec = ModelCatalog.sponge
        var loaded: Entity?
        if let name = spec.resourceName {
            loaded = try? await Entity(named: name)
        }
        attachGeneratedModelVisual(
            loaded ?? Self.fallbackSponge(),
            to: form,
            targetSize: 0.85,
            scaleAxis: .positiveY,
            anchor: .bottom,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: spec.localFrontAxis == nil ? nil : [0, 0, 1]
        )
        // Rename so animation players never grab this runtime by mistake.
        form.findEntity(named: "generated_model_runtime")?.name = "dive_form_runtime"
        form.isEnabled = false
        container.addChild(form)
        diveFormEntity = form
    }

    /// Procedural stand-in sponge: a squishy yellow block with a scrub layer.
    static func fallbackSponge() -> ModelEntity {
        let body = ModelEntity(
            mesh: .generateBox(size: [0.78, 0.5, 0.6], cornerRadius: 0.16),
            materials: [SimpleMaterial(
                color: UIColor(red: 0.98, green: 0.85, blue: 0.25, alpha: 1),
                roughness: 0.85,
                isMetallic: false
            )]
        )
        body.position = [0, 0.25, 0]
        let scrub = ModelEntity(
            mesh: .generateBox(size: [0.78, 0.14, 0.6], cornerRadius: 0.06),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.7, isMetallic: false)]
        )
        scrub.position = [0, 0.32, 0]
        body.addChild(scrub)
        return body
    }

    /// Builds the player's weapon socket, muzzle FX rig, and the visual for
    /// the currently equipped weapon.
    func attachPlayerWeaponRig(to container: Entity) async {
        let socket = Entity()
        socket.name = "weapon_socket"
        let rest = GameConfig.weaponSocketPosition
        socket.position = rest
        weaponRestPosition = rest
        weaponFollowPosition = rest
        container.addChild(socket)
        weaponSocket = socket

        await applyWeaponVisual()

        // Muzzle marker at the front of the weapon — the paint jet spawns here.
        let muzzle = Entity()
        muzzle.name = "muzzle"
        muzzle.position = [0, 0.04, 0.62]
        socket.addChild(muzzle)
        muzzleEntity = muzzle

        let flash = ModelEntity(
            mesh: .generateSphere(radius: 0.12),
            materials: [UnlitMaterial(color: localTeam.uiColor)]
        )
        flash.scale = [1, 1, 1.7]
        flash.isEnabled = false
        muzzle.addChild(flash)
        muzzleFlash = flash

        // Bright spray cone at the nozzle — stays on for the whole burst so
        // the jet reads as one continuous stream.
        let spray = ModelEntity(
            mesh: .generateCone(height: 1.3, radius: 0.16),
            materials: [UnlitMaterial(color: localTeam.uiColor)]
        )
        spray.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        spray.position = [0, 0, 0.65]
        spray.isEnabled = false
        muzzle.addChild(spray)
        sprayCone = spray
    }

    /// Generated-model spec matching a weapon — nil resources fall back to
    /// the procedural stand-ins until the generated models are bundled.
    static func weaponSpec(for weapon: WeaponType) -> ModelCatalog.GeneratedModelSpec {
        switch weapon {
        case .blaster: ModelCatalog.blaster
        case .charger: ModelCatalog.sniper
        case .rapid: ModelCatalog.machineGun
        case .bucket: ModelCatalog.bucketLauncher
        case .dual: ModelCatalog.pistol
        }
    }

    /// Normalized front-axis length of each weapon's visual.
    static func weaponVisualSize(for weapon: WeaponType) -> Float {
        switch weapon {
        case .blaster: GameConfig.weaponTargetSize
        case .charger: 1.4
        case .rapid: 1.1
        case .bucket: 1.15
        case .dual: 0.62
        }
    }

    static func fallbackWeaponVisual(for weapon: WeaponType) -> ModelEntity {
        switch weapon {
        case .blaster: fallbackBlaster()
        case .charger: fallbackSniper()
        case .rapid: fallbackMachineGun()
        case .bucket: fallbackBucket()
        case .dual: fallbackPistol()
        }
    }

    /// Swaps the weapon visual in the player's hand to match `weapon` —
    /// every weapon has its own dedicated 3D model. Dual pistols add a
    /// mirrored off-hand socket carrying the second pistol.
    func applyWeaponVisual() async {
        guard let socket = weaponSocket else { return }
        socket.findEntity(named: "weapon_runtime")?.removeFromParent()
        offhandSocket?.removeFromParent()
        offhandSocket = nil

        let spec = Self.weaponSpec(for: weapon)
        var loaded: Entity?
        if let name = spec.resourceName {
            loaded = try? await Entity(named: name)
        }
        Self.attachWeaponVisual(
            loaded ?? Self.fallbackWeaponVisual(for: weapon),
            to: socket,
            spec: spec,
            targetSize: Self.weaponVisualSize(for: weapon)
        )
        if let muzzle = muzzleEntity, muzzle.parent !== socket {
            muzzle.removeFromParent()
            socket.addChild(muzzle)
        }

        if weapon == .dual, let container = playerContainer {
            let offhand = Entity()
            offhand.name = "offhand_socket"
            var rest = GameConfig.weaponSocketPosition
            rest.x = -rest.x
            offhand.position = rest
            container.addChild(offhand)
            var second: Entity?
            if let name = spec.resourceName {
                second = try? await Entity(named: name)
            }
            Self.attachWeaponVisual(
                second ?? Self.fallbackPistol(),
                to: offhand,
                spec: spec,
                targetSize: Self.weaponVisualSize(for: .dual)
            )
            offhand.findEntity(named: "weapon_runtime")?.name = "offhand_weapon_runtime"
            offhandSocket = offhand
        }
        // Cosmetic weapon skin (Armurerie → Skins): pure tint, zero stats.
        if let hex = MetaStore.shared.equippedSkinColorHex(for: weapon) {
            Self.tintWeapon(in: socket, hex: hex)
            if let offhand = offhandSocket {
                Self.tintWeapon(in: offhand, hex: hex)
            }
        }
        applyBodyVisibility()
        updateMuzzlePlacement()
    }

    /// Tints every material of the weapon model with the equipped skin
    /// color — cosmetic reskin, no gameplay impact.
    static func tintWeapon(in socket: Entity, hex: String) {
        var value = UInt64()
        Scanner(string: hex).scanHexInt64(&value)
        let color = UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
        func visit(_ entity: Entity) {
            if var model = entity.components[ModelComponent.self] {
                model.materials = model.materials.map { material in
                    if var pbm = material as? PhysicallyBasedMaterial {
                        pbm.baseColor.tint = color
                        return pbm
                    }
                    if var unlit = material as? UnlitMaterial {
                        unlit.color.tint = color
                        return unlit
                    }
                    return material
                }
                entity.components.set(model)
            }
            for child in entity.children { visit(child) }
        }
        visit(socket)
    }

    /// Rides the muzzle at the weapon's business end — the nozzle,
    /// center-anchored.
    func updateMuzzlePlacement() {
        switch weapon {
        case .charger: muzzleEntity?.position = [0, 0.05, 0.78]
        case .bucket: muzzleEntity?.position = [0, 0.14, 0.62]
        case .dual: muzzleEntity?.position = [0, 0.03, 0.4]
        default: muzzleEntity?.position = [0, 0.04, 0.62]
        }
    }

    /// Switches the equipped weapon — used from the loadout screen (before
    /// the scene exists) and from the respawn overlay mid-match.
    func selectWeapon(_ newWeapon: WeaponType) {
        guard weapon != newWeapon else { return }
        weapon = newWeapon
        fireTimer = 0
        chargeLevel = 0
        chargeConsumed = false
        heatExact = 0
        heatLevel = 0
        isOverheated = false
        Task { await applyWeaponVisual() }
    }

    /// Flips between the over-the-shoulder view and true first person.
    func toggleCameraMode() {
        cameraMode = cameraMode.toggled
        ProfileStore.shared.cameraMode = cameraMode
        applyBodyVisibility()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The hero's body is hidden in first person (true POV) and while diving;
    /// the weapon stays in view except in sponge form.
    func applyBodyVisibility() {
        heroRuntime?.isEnabled = !isDiving && cameraMode == .thirdPerson
        // The weapon gives way to the grenade while it sits in the hand.
        weaponSocket?.isEnabled = !isDiving && handGrenade == nil
        offhandSocket?.isEnabled = !isDiving && handGrenade == nil
        diveFormEntity?.isEnabled = isDiving
    }

    /// Normalizes a weapon visual into a hand socket, keeping the weapon's
    /// runtime name distinct so animation players never grab it by mistake.
    ///
    /// `gripAtBack` re-anchors long two-handed weapons on their handle end
    /// instead of their center. Without this the hands would hold the middle
    /// of the weapon.
    static func attachWeaponVisual(
        _ visual: Entity,
        to socket: Entity,
        spec: ModelCatalog.GeneratedModelSpec,
        targetSize: Float,
        gripAtBack: Bool = false,
        hingeOffset: Float = 0
    ) {
        attachGeneratedModelVisual(
            visual,
            to: socket,
            targetSize: targetSize,
            scaleAxis: spec.localFrontAxis ?? .positiveZ,
            anchor: .center,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: [0, 0, 1]
        )
        guard let runtime = socket.findEntity(named: "generated_model_runtime") else { return }
        runtime.name = "weapon_runtime"
        if gripAtBack {
            let bounds = visual.visualBounds(relativeTo: socket)
            let length = bounds.max.z - bounds.min.z
            // Hands wrap the handle slightly ahead of its very tip.
            runtime.position.z -= bounds.min.z + length * 0.12 + hingeOffset
        }
    }

    /// Loads a bundled template entity by name, or nil when the name is nil or
    /// the resource fails to load. Used to fan out roster template decodes
    /// concurrently via `async let`.
    static func loadTemplate(_ name: String?) async -> Entity? {
        guard let name else { return nil }
        return try? await Entity(named: name)
    }

    /// Spawns 2 orange teammates and 3 purple rivals — a full 3v3 lobby.
    func buildBots(_ root: Entity) async {
        let heroSpec = ModelCatalog.hero
        let rivalSpec = ModelCatalog.rival
        // Load all four fighter/weapon templates concurrently — they are
        // independent decodes, so waiting for them in parallel roughly halves
        // the roster load time versus the previous serial chain.
        async let heroTemplateLoad = Self.loadTemplate(heroSpec.resourceName)
        async let rivalTemplateLoad = Self.loadTemplate(rivalSpec.resourceName)
        async let blasterTemplateLoad = Self.loadTemplate(ModelCatalog.blaster.resourceName)
        // Every match fields at least one designated sniper bot on the rival
        // side — it carries the charger and hunts elevated vantage points.
        async let sniperTemplateLoad = Self.loadTemplate(ModelCatalog.sniper.resourceName)
        let heroTemplate = await heroTemplateLoad
        let rivalTemplate = await rivalTemplateLoad
        let blasterTemplate = await blasterTemplateLoad
        let sniperTemplate = await sniperTemplateLoad

        // Local duel: no AI — the only opponent is the remote player's
        // puppet, driven by the network state stream. Its team and base
        // follow the network role (host = orange/left, guest = purple/right).
        if isLocalDuel {
            let remoteIsOrange = enemyTeam == .orange
            await spawnBot(
                root, team: enemyTeam,
                template: remoteIsOrange ? heroTemplate : rivalTemplate,
                spec: remoteIsOrange ? heroSpec : rivalSpec,
                weaponTemplate: blasterTemplate, home: remoteHome,
                facing: baseFacing(for: enemyTeam),
                name: localMatch.remoteName
            )
            remoteBot = bots.last
            remoteSnapshots.removeAll(keepingCapacity: true)
            remoteRenderTime = -1
            // The puppet's real HP lives on the other device — the local
            // simulation must never resolve its death.
            remoteBot?.hp = Int.max / 2

            // Partie personnalisée: the host lobby can add AI bots to each
            // team. Both devices build the exact same roster (homes, names,
            // netIDs) in the same order; only the HOST simulates them — the
            // guest renders network puppets driven by the `botState` stream.
            let perTeam = min(GameConfig.duelBotsPerTeam, min(allyHomes.count, enemyHomes.count))
            guard perTeam > 0 else { return }
            let isPuppet = !localMatch.isHost
            // The first bot of EACH team is the designated sniper — the same
            // deterministic rule on host and guest keeps both rosters (and
            // their weapon visuals) identical without streaming anything.
            for index in 0..<perTeam {
                let isSniper = index == 0
                await spawnBot(
                    root, team: .orange, template: heroTemplate, spec: heroSpec,
                    weaponTemplate: isSniper ? sniperTemplate : blasterTemplate,
                    home: allyHomes[index],
                    facing: baseFacing(for: .orange),
                    name: allyBotNames[index % allyBotNames.count],
                    netID: index, isNetPuppet: isPuppet,
                    weapon: isSniper ? .charger : .blaster
                )
            }
            for index in 0..<perTeam {
                let isSniper = index == 0
                await spawnBot(
                    root, team: .purple, template: rivalTemplate, spec: rivalSpec,
                    weaponTemplate: isSniper ? sniperTemplate : blasterTemplate,
                    home: enemyHomes[index],
                    facing: baseFacing(for: .purple),
                    name: rivalBotNames[index % rivalBotNames.count],
                    netID: perTeam + index, isNetPuppet: isPuppet,
                    weapon: isSniper ? .charger : .blaster
                )
            }
            if isPuppet {
                // Puppet HP lives on the host — never resolve deaths locally.
                for bot in bots where bot.isNetPuppet {
                    bot.hp = Int.max / 2
                }
            }
            refreshEnemyStatuses()
            return
        }

        for (index, home) in allyHomes.enumerated() {
            await spawnBot(
                root, team: .orange, template: heroTemplate, spec: heroSpec,
                weaponTemplate: blasterTemplate, home: home, facing: .pi / 2,
                name: allyBotNames[index % allyBotNames.count]
            )
        }
        // The first rival is always the squad's sniper: charger in hand,
        // perched on the map's vantage points.
        for (index, home) in enemyHomes.enumerated() {
            let isSniper = index == 0
            await spawnBot(
                root, team: .purple, template: rivalTemplate, spec: rivalSpec,
                weaponTemplate: isSniper ? sniperTemplate : blasterTemplate,
                home: home, facing: -.pi / 2,
                name: rivalBotNames[index % rivalBotNames.count],
                weapon: isSniper ? .charger : .blaster
            )
        }
    }

    func spawnBot(
        _ root: Entity,
        team: Team,
        template: Entity?,
        spec: ModelCatalog.GeneratedModelSpec,
        weaponTemplate: Entity?,
        home: SIMD3<Float>,
        facing: Float,
        name: String,
        netID: Int? = nil,
        isNetPuppet: Bool = false,
        weapon: WeaponType = .blaster
    ) async {
        let container = Entity()
        let visual = template?.clone(recursive: true) ?? Self.fallbackCharacter(team: team)
        attachGeneratedModelVisual(
            visual,
            to: container,
            targetSize: GameConfig.characterHeight,
            anchor: .bottom,
            localFrontAxis: spec.localFrontAxis,
            localUpAxis: spec.localUpAxis,
            desiredWorldForward: [0, 0, 1]
        )
        let bodyRuntime = container.findEntity(named: "generated_model_runtime")
        container.position = home
        container.orientation = simd_quatf(angle: facing, axis: [0, 1, 0])
        root.addChild(container)
        addBlobShadow(to: container)
        let tag = makeNameTag(text: name, color: team.uiColor)
        container.addChild(tag)

        // Every fighter carries its weapon in hand — blaster by default,
        // the long charger rifle for the designated sniper bot.
        let socket = Entity()
        socket.name = "weapon_socket"
        socket.position = GameConfig.weaponSocketPosition
        container.addChild(socket)
        Self.attachWeaponVisual(
            weaponTemplate?.clone(recursive: true) ?? Self.fallbackWeaponVisual(for: weapon),
            to: socket,
            spec: Self.weaponSpec(for: weapon),
            targetSize: Self.weaponVisualSize(for: weapon),
            gripAtBack: weapon == .charger
        )

        let animator = GeneratedModelAnimationPlayer(container: container)
        if team == .orange {
            await animator.preload(
                [
                    ModelCatalog.heroIdle, ModelCatalog.heroRun, ModelCatalog.heroSplat,
                    ModelCatalog.heroArmedIdle, ModelCatalog.heroHit, ModelCatalog.heroInjuredRun,
                ].compactMap { $0 }
            )
        } else {
            await animator.preload(
                [
                    ModelCatalog.rivalIdle, ModelCatalog.rivalRun, ModelCatalog.rivalSplat,
                    ModelCatalog.rivalArmedIdle, ModelCatalog.rivalHit, ModelCatalog.rivalInjuredRun,
                ].compactMap { $0 }
            )
        }
        let statsIndex = liveStats.count
        liveStats.append(FighterStats(id: statsIndex, name: name, team: team))
        let bot = BotAgent(
            container: container,
            animator: animator,
            home: home,
            team: team,
            weaponSocket: socket,
            nameTag: tag,
            statsIndex: statsIndex
        )
        bot.netID = netID
        bot.isNetPuppet = isNetPuppet
        bot.bodyRuntime = bodyRuntime
        bot.currentWeapon = weapon
        newWaypoint(for: bot)
        bots.append(bot)
        // Every fighter (solo AI bot or remote duel puppet) gets a sponge
        // dive form so it can submerge tactically like a real player.
        await buildBotDiveForm(for: bot)
    }

    func addBlobShadow(to container: Entity) {
        var material = UnlitMaterial(color: .black)
        material.blending = .transparent(opacity: 0.3)
        let shadow = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.55), materials: [material])
        shadow.position = [0, 0.04, 0]
        container.addChild(shadow)
    }

    static func fallbackCharacter(team: Team) -> ModelEntity {
        let material = SimpleMaterial(color: team.uiColor, roughness: 0.4, isMetallic: false)
        let body = ModelEntity(
            mesh: .generateBox(size: [0.5, 1.1, 0.32], cornerRadius: 0.12),
            materials: [material]
        )
        let head = ModelEntity(mesh: .generateSphere(radius: 0.24), materials: [material])
        head.position = [0, 0.78, 0]
        body.addChild(head)
        return body
    }

    static func fallbackBlaster() -> ModelEntity {
        let material = SimpleMaterial(color: .white, roughness: 0.3, isMetallic: false)
        let body = ModelEntity(
            mesh: .generateBox(size: [0.12, 0.14, 0.42], cornerRadius: 0.03),
            materials: [material]
        )
        let nozzle = ModelEntity(
            mesh: .generateBox(size: [0.09, 0.09, 0.14], cornerRadius: 0.02),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.3, isMetallic: false)]
        )
        nozzle.position = [0, 0, 0.26]
        body.addChild(nozzle)
        return body
    }

    /// Procedural stand-in sniper: long slender barrel with a scope on top.
    static func fallbackSniper() -> ModelEntity {
        let material = SimpleMaterial(color: .white, roughness: 0.3, isMetallic: false)
        let body = ModelEntity(
            mesh: .generateBox(size: [0.1, 0.12, 0.8], cornerRadius: 0.03),
            materials: [material]
        )
        let barrel = ModelEntity(
            mesh: .generateCylinder(height: 0.4, radius: 0.035),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.3, isMetallic: false)]
        )
        barrel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        barrel.position = [0, 0.01, 0.55]
        body.addChild(barrel)
        let scope = ModelEntity(
            mesh: .generateCylinder(height: 0.22, radius: 0.045),
            materials: [SimpleMaterial(color: UIColor(white: 0.15, alpha: 1), roughness: 0.3, isMetallic: true)]
        )
        scope.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        scope.position = [0, 0.11, 0.05]
        body.addChild(scope)
        return body
    }

    /// Procedural stand-in machine gun: boxy body with a triple barrel.
    static func fallbackMachineGun() -> ModelEntity {
        let body = ModelEntity(
            mesh: .generateBox(size: [0.16, 0.18, 0.5], cornerRadius: 0.04),
            materials: [SimpleMaterial(color: UIColor(red: 0.18, green: 0.83, blue: 0.77, alpha: 1), roughness: 0.35, isMetallic: false)]
        )
        let barrelMaterial = SimpleMaterial(color: UIColor(white: 0.9, alpha: 1), roughness: 0.3, isMetallic: true)
        for offset: SIMD2<Float> in [[0, 0.05], [-0.045, -0.03], [0.045, -0.03]] {
            let barrel = ModelEntity(mesh: .generateCylinder(height: 0.3, radius: 0.028), materials: [barrelMaterial])
            barrel.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            barrel.position = [offset.x, offset.y, 0.38]
            body.addChild(barrel)
        }
        return body
    }

    /// Procedural stand-in bucket launcher: wide tube with a bucket below.
    static func fallbackBucket() -> ModelEntity {
        let tube = ModelEntity(
            mesh: .generateCylinder(height: 0.6, radius: 0.11),
            materials: [SimpleMaterial(color: UIColor(red: 0.98, green: 0.8, blue: 0.25, alpha: 1), roughness: 0.35, isMetallic: false)]
        )
        tube.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let bucket = ModelEntity(
            mesh: .generateCylinder(height: 0.22, radius: 0.13),
            materials: [SimpleMaterial(color: UIColor(red: 0.95, green: 0.35, blue: 0.62, alpha: 1), roughness: 0.3, isMetallic: true)]
        )
        bucket.position = [0, -0.18, 0]
        tube.addChild(bucket)
        return tube
    }

    /// Procedural stand-in pistol: compact sidearm.
    static func fallbackPistol() -> ModelEntity {
        let material = SimpleMaterial(color: UIColor(red: 0.61, green: 0.3, blue: 1, alpha: 1), roughness: 0.3, isMetallic: false)
        let body = ModelEntity(
            mesh: .generateBox(size: [0.08, 0.1, 0.28], cornerRadius: 0.02),
            materials: [material]
        )
        let grip = ModelEntity(
            mesh: .generateBox(size: [0.07, 0.16, 0.08], cornerRadius: 0.02),
            materials: [SimpleMaterial(color: .white, roughness: 0.4, isMetallic: false)]
        )
        grip.position = [0, -0.11, -0.08]
        body.addChild(grip)
        let nozzle = ModelEntity(
            mesh: .generateBox(size: [0.06, 0.06, 0.08], cornerRadius: 0.015),
            materials: [SimpleMaterial(color: Team.orange.uiColor, roughness: 0.3, isMetallic: false)]
        )
        nozzle.position = [0, 0, 0.17]
        body.addChild(nozzle)
        return body
    }

}
