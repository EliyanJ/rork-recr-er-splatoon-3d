import SwiftUI

/// Timer, coverage bar, player hearts, banners and status overlays.
struct GameHUDView: View {
    let controller: GameController

    @State private var isScoreboardVisible = false
    @State private var isSettingsVisible = false

    var body: some View {
        ZStack {
            DamageVignette(controller: controller)

            CrosshairOverlay(controller: controller)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        hearts
                        if controller.isKeyboardConnected {
                            keyboardHint
                        }
                        if !controller.isTraining, !controller.isMatchOver, !controller.isPlayerDown, !isScoreboardVisible {
                            enemyLivesRow
                        }
                    }
                    Spacer()
                    VStack(spacing: 8) {
                        if controller.isTraining {
                            trainingBadge
                        } else {
                            if controller.matchMode != .turfWar {
                                modeScoreRow
                            }
                            timerView
                        }
                        if let banner = controller.banner {
                            bannerView(banner)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            settingsButton
                            scoreboardButton
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(.top, 8)
                .padding(.horizontal, 20)
                Spacer()
            }

            if let event = controller.splatEvent {
                SplatEventBanner(event: event)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 4)
            }

            if isScoreboardVisible {
                ScoreboardOverlay(controller: controller) {
                    isScoreboardVisible = false
                }
            }

            if isSettingsVisible {
                SettingsOverlay(controller: controller) {
                    isSettingsVisible = false
                }
            }

            if controller.isPlayerDown {
                respawnOverlay
            }

            if controller.isMatchOver {
                Text("TEMPS ÉCOULÉ !")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8)
                    .transition(.scale.combined(with: .opacity))
            }

            if let stats = controller.paintPerfStats {
                paintPerfOverlay(stats)
            }

            if controller.isTraining {
                trainingWeaponStand
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: controller.isMatchOver)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.banner)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isScoreboardVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isSettingsVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: controller.splatEvent)
    }

    /// Debug-only overlay: live paint draw-call count (batched vs the legacy
    /// one-entity-per-tile design). Shown when `GameConfig.paintPerfDebug` is on.
    private func paintPerfOverlay(_ stats: PaintPerfStats) -> some View {
        let saved = stats.legacyDrawCalls - stats.activeEntities
        let factor = stats.activeEntities > 0
            ? Double(stats.legacyDrawCalls) / Double(stats.activeEntities)
            : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text("PAINT PERF")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.yellow)
            Text("draw calls: \(stats.activeEntities)")
                .foregroundStyle(.green)
            Text("legacy (per-tile): \(stats.legacyDrawCalls)")
                .foregroundStyle(.white.opacity(0.7))
            Text("saved: \(saved)  (\(String(format: "%.1f", factor))×)")
                .foregroundStyle(.cyan)
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.6)))
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .padding(.bottom, 120)
        .allowsHitTesting(false)
    }

    /// Opens the in-match settings panel (volume, HUD layout, graphics).
    private var settingsButton: some View {
        Button {
            isSettingsVisible.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(8)
                .background(Circle().fill(.black.opacity(0.45)))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Opens the live in-match scoreboard.
    private var scoreboardButton: some View {
        Button {
            isScoreboardVisible.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.system(size: 14, weight: .bold))
                Text("SCORES")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Live team score for Duel Mortel (kills) and Contrôle de Zones (points)
    /// — pinned above the timer so the objective that actually decides the
    /// match is always in view, not just the turf-coverage bar.
    private var modeScoreRow: some View {
        let isZone = controller.matchMode == .zoneControl
        let leftScore = isZone ? controller.zoneScoreOrange : controller.orangeKillScore
        let rightScore = isZone ? controller.zoneScorePurple : controller.purpleKillScore
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text("\(leftScore)")
                    .foregroundStyle(Team.orange.color)
                Image(systemName: controller.matchMode.iconSystemName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("\(rightScore)")
                    .foregroundStyle(Team.purple.color)
            }
            .font(.system(size: 22, weight: .black, design: .rounded))
            .monospacedDigit()
            .shadow(color: .black.opacity(0.5), radius: 3)
            if isZone {
                HStack(spacing: 5) {
                    ForEach(Array(controller.zoneControllers.enumerated()), id: \.offset) { _, owner in
                        Circle()
                            .fill(owner?.color ?? Color.white.opacity(0.35))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1.5))
    }

    /// ENTRAÎNEMENT badge replacing the countdown timer — the sandbox never
    /// ends on its own.
    private var trainingBadge: some View {
        Label("ENTRAÎNEMENT", systemImage: "target")
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.45)))
            .overlay(Capsule().stroke(Color(hex: "2EE6D6").opacity(0.6), lineWidth: 1.5))
    }

    /// Always-on weapon switcher for the training sandbox — no respawn wait
    /// needed, so it floats above the controls at all times.
    private var trainingWeaponStand: some View {
        VStack(spacing: 6) {
            Text("STAND D'ARMES")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(WeaponType.allCases) { weapon in
                        weaponSwapButton(weapon)
                    }
                }
                .padding(.horizontal, 4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 118)
        .allowsHitTesting(true)
    }

    /// Desktop testing helper — shown only while a hardware keyboard is
    /// connected (simulator or device).
    private var keyboardHint: some View {
        Text("Flèches : bouger · M : tirer · G : grenade\nEspace : saut · C : nage · glisser : viser")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.35)))
    }

    /// Top-left row of rival head icons — lit while the enemy is alive,
    /// blacked out while they wait to respawn. One glance = who's left.
    /// Sits just above the TOP TUEURS ranking so status + standings read
    /// together in one corner instead of splitting the screen.
    private var enemyLivesRow: some View {
        HStack(spacing: 8) {
            ForEach(controller.enemyStatuses) { enemy in
                ZStack {
                    Circle()
                        .fill(enemy.isAlive ? controller.enemyTeam.color : Color.black.opacity(0.75))
                        .frame(width: 26, height: 26)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(enemy.isAlive ? .white : .white.opacity(0.22))
                }
                .overlay(
                    Circle().stroke(
                        enemy.isAlive ? Color.white.opacity(0.6) : Color.white.opacity(0.12),
                        lineWidth: 1.5
                    )
                )
                .shadow(
                    color: enemy.isAlive ? controller.enemyTeam.color.opacity(0.55) : .clear,
                    radius: 4
                )
                .scaleEffect(enemy.isAlive ? 1 : 0.86)
                .animation(.spring(response: 0.3, dampingFraction: 0.65), value: enemy.isAlive)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: controller.enemyStatuses)
    }

    private var hearts: some View {
        HStack(spacing: 4) {
            ForEach(0..<GameConfig.playerMaxHP, id: \.self) { index in
                Image(systemName: "drop.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(
                        index < controller.playerHP
                            ? controller.localTeam.color
                            : Color.white.opacity(0.2)
                    )
            }
        }
        .padding(.top, 6)
        .opacity(0)
    }

    private var timerView: some View {
        let seconds = Int(controller.timeRemaining.rounded(.up))
        let isUrgent = seconds <= 10 && !controller.isMatchOver
        return Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: 32, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isUrgent ? Color.red : .white)
            .shadow(color: .black.opacity(0.5), radius: 4)
            .scaleEffect(isUrgent ? 1.1 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isUrgent)
    }

    private func bannerView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.55)))
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Respawn screen — the pause is also the moment to swap weapons.
    private var respawnOverlay: some View {
        VStack(spacing: 14) {
            Text("SPLAT !")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(Team.purple.color)
                .shadow(color: .black.opacity(0.6), radius: 8)
            Text("Réapparition dans \(max(1, Int(controller.respawnCountdown.rounded(.up))))…")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))

            VStack(spacing: 8) {
                Text("CHANGER D'ARME")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(WeaponType.allCases) { weapon in
                            weaponSwapButton(weapon)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contentMargins(.horizontal, 24)
                .scrollIndicators(.hidden)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Team.purple.color.opacity(0.18).ignoresSafeArea())
        .transition(.opacity)
    }

    private func weaponSwapButton(_ weapon: WeaponType) -> some View {
        let isSelected = controller.weapon == weapon
        return Button {
            controller.selectWeapon(weapon)
            ProfileStore.shared.selectedWeapon = weapon
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: weapon.iconSystemName)
                    .font(.system(size: 22, weight: .bold))
                Text(weapon.displayName)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isSelected ? .black : .white)
            .frame(width: 74, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Team.orange.color : Color.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? .white : .white.opacity(0.25), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Damage vignette — enemy paint creeps in from the screen edges when the
/// player takes hits. The lower the HP, the thicker the encroachment, with
/// a quick extra pulse on every hit. The CENTER of the screen always stays
/// clear so enemies remain visible even near 0 HP. The HP drops in the top
/// left are hidden, so this screen-edge paint becomes the main health readout.
private struct DamageVignette: View {
    let controller: GameController
    @State private var hitFlash: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let missing = 1 - Double(controller.playerHP) / Double(GameConfig.playerMaxHP)
            let base = (missing <= 0.01 || controller.isPlayerDown || controller.isMatchOver)
                ? 0 : 0.22 + 0.74 * missing
            let intensity = min(0.95, base + hitFlash)
            let minSide = min(proxy.size.width, proxy.size.height)
            let maxSide = max(proxy.size.width, proxy.size.height)
            let paint = controller.enemyTeam.color

            ZStack {
                if intensity > 0.01 {
                    // Thick radial ink band around the safe center area.
                    RadialGradient(
                        colors: [
                            .clear,
                            paint.opacity(0.3 * intensity),
                            paint.opacity(intensity)
                        ],
                        center: .center,
                        startRadius: minSide * (0.30 - 0.12 * missing),
                        endRadius: maxSide * (0.55 + 0.08 * missing)
                    )
                    .blendMode(.sourceAtop)

                    // Large paint blobs pooling in the corners — reads as ink,
                    // not fog. They grow bigger and more opaque as HP drops.
                    ForEach(0..<4, id: \.self) { corner in
                        Circle()
                            .fill(paint.opacity(intensity * 0.95))
                            .frame(width: minSide * (0.48 + 0.22 * missing), height: minSide * (0.48 + 0.22 * missing))
                            .blur(radius: 30 + 20 * missing)
                            .position(
                                x: corner % 2 == 0 ? 0 : proxy.size.width,
                                y: corner < 2 ? 0 : proxy.size.height
                            )
                    }

                    // Dripping ink streaks running down the top edge when HP
                    // is low — reinforces the "you're covered in paint" feeling.
                    if missing > 0.35 {
                        ForEach(0..<3, id: \.self) { index in
                            let xOffset = proxy.size.width * (0.2 + Double(index) * 0.3)
                            Capsule()
                                .fill(paint.opacity(0.55 * intensity))
                                .frame(width: 18 + 22 * missing, height: proxy.size.height * (0.18 + 0.22 * missing))
                                .blur(radius: 12)
                                .position(x: xOffset, y: -proxy.size.height * 0.05)
                        }
                    }

                    // Hit flash: a brief, bright paint flash over the edges.
                    if hitFlash > 0.01 {
                        RadialGradient(
                            colors: [.clear, paint.opacity(hitFlash * 0.7)],
                            center: .center,
                            startRadius: minSide * 0.25,
                            endRadius: maxSide * 0.55
                        )
                    }
                }
            }
            .animation(.easeOut(duration: 0.35), value: controller.playerHP)
            .animation(.easeOut(duration: 0.55), value: hitFlash)
            .onChange(of: controller.damagePulse) { _, _ in
                hitFlash = 0.40
                withAnimation(.easeOut(duration: 0.55)) { hitFlash = 0 }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Fixed center-screen reticle — the game converges every shot onto the
/// point the center of the screen covers, so the crosshair never wanders
/// or sticks to nearby objects. Isolated in its own view so lock/firing
/// state changes don't re-render the whole HUD.
private struct CrosshairOverlay: View {
    let controller: GameController

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if !controller.isPlayerDown && !controller.isMatchOver && !controller.isDiving
                    && !controller.isAimingGrenade {
                    reticle.position(
                        CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    )
                }
            }
            .onAppear { controller.viewportSize = proxy.size }
            .onChange(of: proxy.size) { _, newSize in
                controller.viewportSize = newSize
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var reticle: some View {
        let firing = controller.isFiring
        let locked = controller.isAimOnTarget
        // Dynamic reticle: shrinks and recolors when the shot will connect.
        let color: Color = locked ? .red : (firing ? Team.orange.color : .white)
        let charge = controller.chargeLevel
        return ZStack {
            // Charger gauge wrapped around the reticle — white when full.
            if controller.weapon == .charger, charge > 0.01 {
                Circle()
                    .stroke(.black.opacity(0.35), lineWidth: 3.5)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: CGFloat(charge))
                    .stroke(
                        charge >= 0.99 ? Color.white : Color.yellow,
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
            }
            // Machine-gun heat ring — turns red near overheat, flashes when
            // the gun is locked out.
            if controller.weapon == .rapid, controller.heatLevel > 0.01 {
                Circle()
                    .stroke(.black.opacity(0.35), lineWidth: 3.5)
                    .frame(width: 42, height: 42)
                Circle()
                    .trim(from: 0, to: CGFloat(controller.heatLevel))
                    .stroke(
                        controller.isOverheated
                            ? Color.red
                            : (controller.heatLevel > 0.7 ? Color.orange : Color.cyan),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                    )
                    .frame(width: 42, height: 42)
                    .rotationEffect(.degrees(-90))
                if controller.isOverheated {
                    Text("SURCHAUFFE")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.red)
                        .offset(y: 34)
                }
            }
            Circle()
                .stroke(color.opacity(0.85), lineWidth: 2)
                .frame(width: 26, height: 26)
            Circle()
                .fill(color)
                .frame(width: 4.5, height: 4.5)
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(color.opacity(0.9))
                    .frame(width: 2, height: 7)
                    .offset(y: -20)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
        .scaleEffect(locked ? 0.72 : (firing ? 1.18 : 1))
        .shadow(color: .black.opacity(0.55), radius: 2)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: firing)
        .animation(.spring(response: 0.16, dampingFraction: 0.65), value: locked)
    }
}



/// Full in-match scoreboard: kills / deaths / assists / KDA and painted
/// turf per fighter, grouped by team. Tapping the scrim closes it.
private struct ScoreboardOverlay: View {
    let controller: GameController
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 10) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "list.number")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.menuAccent)
                        Text("TABLEAU DES SCORES")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(PressableStyle())
                }

                teamSection(.orange, title: "ÉQUIPE ORANGE")
                teamSection(.purple, title: "ÉQUIPE VIOLETTE")
            }
            .padding(16)
            .frame(maxWidth: 430)
            .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.94)))
            .overlay(PaintedPanel(skew: 4).stroke(.menuAccent.opacity(0.45), lineWidth: 1.5))
            .padding(.horizontal, 30)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private func teamSection(_ team: Team, title: String) -> some View {
        let fighters = controller.stats
            .filter { $0.team == team }
            .sorted { ($0.kills, $0.paintTiles) > ($1.kills, $1.paintTiles) }
        return VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(team.color))
                Spacer()
                Text("K / D / A · KDA")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            ForEach(fighters) { fighter in
                statRow(fighter)
            }
        }
    }

    private func statRow(_ fighter: FighterStats) -> some View {
        // Painted turf stays a secret until the results screen — only kills,
        // deaths, assists and KDA are worth checking mid-match.
        let kda = Double(fighter.kills + fighter.assists) / Double(max(1, fighter.deaths))
        return HStack(spacing: 8) {
            Circle()
                .fill(fighter.team.color)
                .frame(width: 8, height: 8)
            Text(fighter.name)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            if fighter.id == 0 {
                Text("TOI")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Team.orange.color))
            }
            Spacer()
            Text("\(fighter.kills) / \(fighter.deaths) / \(fighter.assists)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
            Text(String(format: "%.1f", kda))
                .font(.system(size: 12, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.yellow)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(fighter.id == 0 ? Color.menuAccent.opacity(0.16) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(fighter.id == 0 ? Color.menuAccent.opacity(0.5) : .clear, lineWidth: 1.2)
        )
    }
}

/// Stylized one-shot elimination callout shown at the very top of the
/// screen. Only appears when the local player scores a kill. Uses the
/// player's team color, a splash icon, and animates in with a scale pop
/// then slides up and fades out.
private struct SplatEventBanner: View {
    let event: GameController.SplatEvent
    @State private var didPop = false
    @State private var fadeOut = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "drop.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Team.orange.color)
                .scaleEffect(didPop ? 1 : 0.3)

            Text(event.headline)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Team.orange.color)

            Text(event.name)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Team.orange.color.opacity(0.35)))
                .overlay(Capsule().stroke(Team.orange.color, lineWidth: 2))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(
            Capsule().fill(.black.opacity(0.7))
        )
        .overlay(
            Capsule().stroke(Team.orange.color.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: Team.orange.color.opacity(0.4), radius: 12)
        .scaleEffect(didPop ? 1 : 0.5)
        .offset(y: fadeOut ? -30 : 0)
        .opacity(fadeOut ? 0 : (didPop ? 1 : 0))
        .onAppear {
            didPop = false
            fadeOut = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                didPop = true
            }
            withAnimation(.easeIn(duration: 0.4).delay(1.6)) {
                fadeOut = true
            }
        }
        .id(event.id)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

/// Settings panel: independent volume sliders, real target-FPS picker,
/// graphics quality, and (in match) the HUD reposition mode — all persisted
/// to the profile. Usable from the hub menu too (controller = nil).
struct SettingsOverlay: View {
    let controller: GameController?
    let onClose: () -> Void

    @State private var master = ProfileStore.shared.masterVolume
    @State private var music = ProfileStore.shared.musicVolume
    @State private var sfx = ProfileStore.shared.sfxVolume
    @State private var quality = ProfileStore.shared.graphicsQuality
    @State private var autoQuality = ProfileStore.shared.autoGraphicsQuality
    @State private var fps = ProfileStore.shared.targetFPS
    @State private var sensitivity = ProfileStore.shared.cameraSensitivity
    /// Guards against an accidental tap ending the match.
    @State private var showQuitConfirm = false

    /// Real framerate choices, capped by what the display supports.
    private var fpsOptions: [Int] {
        let maxHz = UIScreen.main.maximumFramesPerSecond
        return [30, 60, 120].filter { $0 <= max(maxHz, 60) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 12) {
                // Header pinned OUTSIDE the scroll area — the close button is
                // always visible and tappable, whatever the screen height.
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.menuAccent)
                        Text("PARAMÈTRES")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        settingsBody
                    }
                    .padding(.bottom, 4)
                }

                Button(action: onClose) {
                    Text("FERMER")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.menuAccent))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(18)
            .frame(maxWidth: 380)
            .frame(maxHeight: 520)
            .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.95)))
            .overlay(PaintedPanel(skew: 4).stroke(.menuAccent.opacity(0.45), lineWidth: 1.5))
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .alert("Quitter la partie ?", isPresented: $showQuitConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Quitter", role: .destructive) {
                controller?.leaveMatch()
            }
        } message: {
            Text("Tu vas abandonner ce match en cours et revenir au menu principal. Cette action est irréversible.")
        }
    }

    /// Scrollable body of the settings panel.
    @ViewBuilder
    private var settingsBody: some View {
                volumeSlider("Général", value: $master) { ProfileStore.shared.masterVolume = $0 }
                volumeSlider("Musique", value: $music) { ProfileStore.shared.musicVolume = $0 }
                volumeSlider("Effets sonores", value: $sfx) { ProfileStore.shared.sfxVolume = $0 }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SENSIBILITÉ DU VISEUR")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text(String(format: "%.2f×", sensitivity))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                    Slider(value: $sensitivity, in: 0.5...1.6) { editing in
                        if !editing { ProfileStore.shared.cameraSensitivity = sensitivity }
                    }
                    .tint(Team.orange.color)
                    Text("Vitesse de rotation caméra/viseur quand tu glisses le doigt à l'écran.")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("IMAGES PAR SECONDE (FPS)")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("cible réelle du moteur")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Picker("FPS", selection: $fps) {
                        ForEach(fpsOptions, id: \.self) { option in
                            Text("\(option)").tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: fps) { _, newValue in
                        ProfileStore.shared.targetFPS = newValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $autoQuality) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AJUSTEMENT AUTOMATIQUE")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Détecte le niveau adapté à ton appareil, et l'ajuste encore si le jeu ramène en partie.")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    .tint(Team.orange.color)
                    .onChange(of: autoQuality) { _, newValue in
                        ProfileStore.shared.autoGraphicsQuality = newValue
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }

                    HStack {
                        Text("QUALITÉ GRAPHIQUE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        if autoQuality {
                            Text("Auto (\(DevicePerformance.recommendedQuality.displayName))")
                                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                                .foregroundStyle(Team.orange.color)
                        }
                    }
                    Picker("Qualité", selection: $quality) {
                        ForEach(GraphicsQuality.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(autoQuality)
                    .opacity(autoQuality ? 0.45 : 1)
                    .onChange(of: quality) { _, newValue in ProfileStore.shared.graphicsQuality = newValue }
                    Text(quality.subtitle)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                if let controller {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CAMÉRA")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Button {
                            controller.toggleCameraMode()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: controller.cameraMode.toggled.iconSystemName)
                                    .font(.system(size: 15, weight: .bold))
                                Text("Passer en \(controller.cameraMode.toggled.displayName)")
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(PressableStyle())
                    }

                    Button {
                        controller.hudEditSnapshot = ProfileStore.shared.hudOffsets
                        controller.isHUDEditMode = true
                        onClose()
                    } label: {
                        Label("REPOSITIONNER LES BOUTONS", systemImage: "hand.draw.fill")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(PaintedPanel(skew: 3).fill(Team.orange.color.opacity(0.85)))
                            .overlay(PaintedPanel(skew: 3).stroke(.white.opacity(0.3), lineWidth: 1.5))
                    }
                    .buttonStyle(PressableStyle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text("QUITTER")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        Button {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                            showQuitConfirm = true
                        } label: {
                            Label("QUITTER LA PARTIE", systemImage: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.35)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.6), lineWidth: 1.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.top, 4)
                }
    }

    private func volumeSlider(_ label: String, value: Binding<Double>, onCommit: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.menuAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.35)))
            }
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if !editing { onCommit(value.wrappedValue) }
            })
            .tint(Color.menuAccent)
        }
    }
}
