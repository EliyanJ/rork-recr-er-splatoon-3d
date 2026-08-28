import SwiftUI

/// End-of-match screen: podium of the top 3 fighters, coverage bar, then
/// the meta progression sequence — animated XP breakdown, level bar filling
/// up (level-up popup when a threshold is crossed), Pigments earned and the
/// possibly-earned chest with its reveal screen.
struct ResultsView: View {
    let result: MatchResult
    let summary: MatchMetaSummary
    let onReplay: () -> Void
    let onMenu: () -> Void

    @State private var appeared = false

    // Suspense : le terrain peint n'est "scanné" qu'à l'arrivée sur cet
    // écran — victoire/défaite ne se dévoile qu'après ce court instant.
    @State private var isRevealed = false
    @State private var animatedOrangePercent = 0
    @State private var animatedPurplePercent = 0

    // Séquence XP animée
    @State private var revealedXPLines = 0
    @State private var xpBarProgress: Double = 0
    @State private var displayedLevel: Int = 1
    @State private var showLevelUp = false
    @State private var chestReveal: ChestRevealPayload?
    @State private var chestOpened = false

    private var title: String {
        switch result.outcome {
        case .win: "VICTOIRE !"
        case .lose: "DÉFAITE…"
        case .draw: "ÉGALITÉ !"
        }
    }

    private var titleColor: Color {
        switch result.outcome {
        case .win: result.localTeam.color
        case .lose: result.localTeam.opponent.color
        case .draw: .white
        }
    }

    /// Values counted up during the pre-reveal beat — paint percentages in
    /// Guerre de Peinture, the mode's team scores (kills / zone points) in
    /// the other modes, so the suspense moment matches what actually
    /// decided the match.
    private var revealTargets: (mine: Int, theirs: Int) {
        switch result.mode {
        case .turfWar:
            return (result.orangePercent, result.purplePercent)
        case .deathmatch, .zoneControl:
            let mine = result.localTeam == .orange ? result.orangeScore : result.purpleScore
            let theirs = result.localTeam == .orange ? result.purpleScore : result.orangeScore
            return (mine, theirs)
        }
    }

    private var scanningTitle: String {
        switch result.mode {
        case .turfWar: "ANALYSE DU TERRAIN…"
        case .deathmatch: "DÉCOMPTE DES ÉLIMINATIONS…"
        case .zoneControl: "DÉCOMPTE DES POINTS DE ZONE…"
        }
    }

    /// "%" suffix only applies to the turf-coverage reveal.
    private var revealSuffix: String {
        result.mode == .turfWar ? "%" : ""
    }

    /// Top 3 fighters of the match, sorted by kills then painted turf.
    private var podium: [FighterStats] {
        Array(
            result.standings
                .sorted { ($0.kills, $0.paintTiles) > ($1.kills, $1.paintTiles) }
                .prefix(3)
        )
    }

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            Circle()
                .fill(titleColor.opacity(0.35))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .allowsHitTesting(false)

            if isRevealed {
                resultsContent
                    .transition(.opacity)
            } else {
                scanningOverlay
                    .transition(.opacity)
            }

            if showLevelUp {
                levelUpPopup
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: showLevelUp)
        .animation(.easeInOut(duration: 0.4), value: isRevealed)
        .onAppear {
            Task { await runRevealSequence() }
        }
        .fullScreenCover(item: $chestReveal) { payload in
            ChestRevealView(payload: payload) { chestReveal = nil }
        }
    }

    // MARK: Séquence XP

    private func playXPSequence() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            for index in 1...max(1, summary.xpLines.count) {
                revealedXPLines = index
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .milliseconds(280))
            }
            // Barre d'XP : remplit jusqu'au niveau suivant si franchi.
            if summary.levelAfter > summary.levelBefore {
                withAnimation(.easeInOut(duration: 0.7)) { xpBarProgress = 1 }
                try? await Task.sleep(for: .milliseconds(750))
                displayedLevel = summary.levelAfter
                xpBarProgress = 0
                showLevelUp = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(1400))
                showLevelUp = false
                withAnimation(.easeInOut(duration: 0.6)) {
                    xpBarProgress = summary.progressAfter
                }
            } else {
                withAnimation(.easeInOut(duration: 0.9)) {
                    xpBarProgress = summary.progressAfter
                }
            }
        }
    }

    /// Runs once on appear: a short "scanning the battlefield" beat that
    /// counts the final coverage percentages up from zero before the
    /// victory/defeat title and the rest of the recap fade in. Turns the
    /// once-instant reveal into a real suspense moment.
    private func runRevealSequence() async {
        try? await Task.sleep(for: .milliseconds(200))
        let targets = revealTargets
        let steps = 22
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            animatedOrangePercent = Int((Double(targets.mine) * t).rounded())
            animatedPurplePercent = Int((Double(targets.theirs) * t).rounded())
            UISelectionFeedbackGenerator().selectionChanged()
            try? await Task.sleep(for: .milliseconds(38))
        }
        animatedOrangePercent = targets.mine
        animatedPurplePercent = targets.theirs
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .milliseconds(550))

        withAnimation(.easeInOut(duration: 0.4)) {
            isRevealed = true
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
            appeared = true
        }
        displayedLevel = summary.levelBefore
        xpBarProgress = summary.progressBefore
        playXPSequence()
    }

    /// Pre-reveal beat: the terrain gets "scanned" and the coverage numbers
    /// count up before the outcome is known — victory/defeat stays hidden
    /// until this finishes.
    private var scanningOverlay: some View {
        // Bar fractions: percent scale for turf, share of combined score
        // for the kill/zone modes.
        let barDenominator = result.mode == .turfWar
            ? 100
            : max(animatedOrangePercent + animatedPurplePercent, 1)
        return VStack(spacing: 22) {
            Image(systemName: result.mode == .turfWar ? "viewfinder.circle.fill" : result.mode.iconSystemName)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.menuAccent)
                .symbolEffect(.pulse)

            Text(scanningTitle)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(2)

            HStack {
                Text("\(animatedOrangePercent)\(revealSuffix)")
                    .foregroundStyle(result.localTeam.color)
                Spacer()
                Text("\(animatedPurplePercent)\(revealSuffix)")
                    .foregroundStyle(result.localTeam.opponent.color)
            }
            .font(.system(size: 28, weight: .black, design: .rounded))
            .monospacedDigit()
            .frame(maxWidth: 300)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(result.localTeam.color)
                            .frame(width: geo.size.width * CGFloat(animatedOrangePercent) / CGFloat(barDenominator))
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(result.localTeam.opponent.color)
                            .frame(width: geo.size.width * CGFloat(animatedPurplePercent) / CGFloat(barDenominator))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            .frame(maxWidth: 300)
        }
        .padding(32)
        .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.92)))
        .overlay(PaintedPanel(skew: 4).stroke(.menuAccent.opacity(0.5), lineWidth: 1.5))
    }

    private var levelUpPopup: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.menuAccent)
            Text("NIVEAU SUPÉRIEUR !")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Niveau \(summary.levelAfter)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.menuAccent)
        }
        .padding(28)
        .background(PaintedPanel(skew: 5).fill(Color.menuPanel.opacity(0.96)))
        .overlay(PaintedPanel(skew: 5).stroke(.menuAccent.opacity(0.75), lineWidth: 2))
    }

    // MARK: Podium + progression

    /// Adapts to the real screen: landscape phones get a side-by-side layout
    /// (podium | XP + coverage + actions) using the full width; portrait
    /// keeps a stacked scroll — nothing clipped, no dead margins.
    private var resultsContent: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height
            Group {
                if isLandscape {
                    VStack(spacing: 8) {
                        titleBadge(fontSize: 26)
                            .scaleEffect(appeared ? 1 : 0.4)
                            .opacity(appeared ? 1 : 0)

                        HStack(alignment: .center, spacing: 24) {
                            VStack(spacing: 12) {
                                podiumRow
                                modeSummarySection
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)

                            VStack(spacing: 12) {
                                xpCard
                                rewardsRow
                                actionButtons
                            }
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            titleBadge(fontSize: 34)
                                .scaleEffect(appeared ? 1 : 0.4)
                                .opacity(appeared ? 1 : 0)

                            podiumRow
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 16)

                            xpCard
                                .opacity(appeared ? 1 : 0)

                            rewardsRow
                                .opacity(appeared ? 1 : 0)

                            modeSummarySection
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)

                            actionButtons
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 24)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height)
                    }
                }
            }
        }
    }

    /// Graffiti-style painted badge for the outcome title — replaces the
    /// plain floating text with a tilted panel matching the rest of the UI.
    private func titleBadge(fontSize: CGFloat) -> some View {
        Text(title)
            .font(.system(size: fontSize, weight: .black, design: .rounded))
            .foregroundStyle(titleColor)
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .padding(.horizontal, 26)
            .padding(.vertical, 10)
            .background(PaintedPanel(skew: 6).fill(Color.menuPanel.opacity(0.55)))
            .overlay(PaintedPanel(skew: 6).stroke(titleColor.opacity(0.6), lineWidth: 2))
    }

    // MARK: Carte XP animée

    private var xpCard: some View {
        VStack(spacing: 8) {
            ForEach(Array(summary.xpLines.enumerated()), id: \.element.id) { index, line in
                HStack {
                    Text(line.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("+\(line.amount) XP")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Team.orange.color)
                        .monospacedDigit()
                }
                .opacity(revealedXPLines > index ? 1 : 0)
                .offset(x: revealedXPLines > index ? 0 : 18)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: revealedXPLines)
            }

            Rectangle()
                .fill(.white.opacity(0.15))
                .frame(height: 1)

            HStack {
                Text("Total")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("+\(summary.totalXP) XP")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                Text("Niv.\(displayedLevel)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .monospacedDigit()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Team.orange.color, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(4, geo.size.width * xpBarProgress))
                    }
                }
                .frame(height: 10)
                Text("Niv.\(min(MetaStore.maxLevel, displayedLevel + 1))")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            if let chest = summary.chestEarned {
                Button {
                    guard !chestOpened else { return }
                    let rewards = MetaStore.shared.openChest(chest)
                    guard !rewards.isEmpty else { return }
                    chestOpened = true
                    chestReveal = ChestRevealPayload(chest: chest, rewards: rewards)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text(chestOpened ? "\(chest.displayName) ouvert ✓" : "🎁 \(chest.displayName) débloqué !")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                        Spacer()
                        if !chestOpened {
                            Text("OUVRIR")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(chest.tint))
                        }
                    }
                    .foregroundStyle(chestOpened ? .green : chest.tint)
                    .padding(10)
                    .background(PaintedPanel(skew: 3).fill(chest.tint.opacity(0.14)))
                    .overlay(PaintedPanel(skew: 3).stroke(chest.tint.opacity(0.55), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            if !summary.newTitles.isEmpty {
                ForEach(summary.newTitles) { title in
                    Label("Titre débloqué : « \(title.name) »", systemImage: "rosette")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.menuAccent)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 360)
        .background(PaintedPanel(skew: 5).fill(Color.menuPanel.opacity(0.88)))
        .overlay(PaintedPanel(skew: 5).stroke(.white.opacity(0.15), lineWidth: 1.5))
    }

    private var actionButtons: some View {
        HStack(spacing: 14) {
            Button {
                onReplay()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Text("REJOUER")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(
                        PaintedPanel(skew: 5)
                            .fill(Color.menuAccent)
                            .shadow(color: Color.menuAccent.opacity(0.5), radius: 12, y: 4)
                    )
            }
            .buttonStyle(PressableStyle())

            Button {
                onMenu()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("ACCUEIL")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)
                    .background(PaintedPanel(skew: -5).fill(Color.menuPanel.opacity(0.7)))
                    .overlay(PaintedPanel(skew: -5).stroke(.white.opacity(0.35), lineWidth: 2))
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// Podium of the match's 3 best fighters — 2 / 1 / 3 layout, crown on
    /// the champion, the player highlighted.
    private var podiumRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if podium.count > 1 {
                podiumCard(fighter: podium[1], rank: 2, height: 78)
            }
            if !podium.isEmpty {
                podiumCard(fighter: podium[0], rank: 1, height: 100)
            }
            if podium.count > 2 {
                podiumCard(fighter: podium[2], rank: 3, height: 66)
            }
        }
    }

    private func podiumCard(fighter: FighterStats, rank: Int, height: CGFloat) -> some View {
        let isPlayer = fighter.id == 0
        return VStack(spacing: 5) {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.yellow)
            }
            Image(systemName: "person.fill")
                .font(.system(size: rank == 1 ? 30 : 24, weight: .bold))
                .foregroundStyle(fighter.team.color)
            Text(fighter.name)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(fighter.kills) éclaboussures")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Text("\(rank)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(rank == 1 ? .menuAccent : .white.opacity(0.6))
        }
        .frame(width: 104, height: height + 60, alignment: .bottom)
        .padding(.vertical, 8)
        .background(
            PaintedPanel(skew: rank == 1 ? 4 : (rank == 2 ? -3 : 3))
                .fill(Color.menuPanel.opacity(isPlayer ? 0.9 : 0.7))
        )
        .overlay(
            PaintedPanel(skew: rank == 1 ? 4 : (rank == 2 ? -3 : 3))
                .stroke(
                    isPlayer ? Team.orange.color : (rank == 1 ? Color.menuAccent.opacity(0.8) : .white.opacity(0.15)),
                    lineWidth: isPlayer || rank == 1 ? 2 : 1
                )
        )
    }

    /// Pigments earned this match.
    private var rewardsRow: some View {
        HStack(spacing: 12) {
            rewardChip(icon: "paintpalette.fill", tint: Team.orange.color, text: "+\(summary.pigmentsEarned) Pigments")
        }
    }

    private func rewardChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(.black.opacity(0.4)))
        .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1.5))
    }

    /// Adapts the final score recap to the mode actually played — turf
    /// coverage bar for Guerre de Peinture, team kill totals for Duel
    /// Mortel, team zone points for Contrôle de Zones.
    @ViewBuilder
    private var modeSummarySection: some View {
        switch result.mode {
        case .turfWar:
            coverageSummary
        case .deathmatch:
            scoreSummary(
                label: "ÉLIMINATIONS",
                mine: result.localTeam == .orange ? result.orangeScore : result.purpleScore,
                theirs: result.localTeam == .orange ? result.purpleScore : result.orangeScore
            )
        case .zoneControl:
            scoreSummary(
                label: "POINTS DE ZONE",
                mine: result.localTeam == .orange ? result.orangeScore : result.purpleScore,
                theirs: result.localTeam == .orange ? result.purpleScore : result.orangeScore
            )
        }
    }

    /// Shared side-by-side score recap for Duel Mortel / Contrôle de Zones —
    /// same visual language as the turf coverage bar, just a raw score
    /// instead of a percentage split.
    private func scoreSummary(label: String, mine: Int, theirs: Int) -> some View {
        let total = max(mine + theirs, 1)
        return VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            HStack {
                Text("Vous — \(mine)")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(result.localTeam.color)
                Spacer()
                Text("\(theirs) — Rivaux")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(result.localTeam.opponent.color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(result.localTeam.color)
                            .frame(width: geo.size.width * CGFloat(mine) / CGFloat(total))
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(result.localTeam.opponent.color)
                            .frame(width: geo.size.width * CGFloat(theirs) / CGFloat(total))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
        }
        .frame(maxWidth: 340)
    }

    /// Coverage bar that stretches with the available width instead of a
    /// hardcoded size — stays centered and fully visible on every phone.
    private var coverageSummary: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Vous — \(result.orangePercent)%")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(result.localTeam.color)
                Spacer()
                Text("\(result.purplePercent)% — Rivaux")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(result.localTeam.opponent.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(result.localTeam.color)
                            .frame(width: geo.size.width * CGFloat(result.orangePercent) / 100)
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(result.localTeam.opponent.color)
                            .frame(width: geo.size.width * CGFloat(result.purplePercent) / 100)
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 16)
        }
        .frame(maxWidth: 340)
    }
}

#Preview {
    ResultsView(
        result: MatchResult(
            outcome: .win,
            localTeam: .orange,
            mode: .turfWar,
            orangePercent: 54,
            purplePercent: 38,
            paintedTiles: 420,
            standings: [
                FighterStats(id: 0, name: "Inkling", team: .orange, kills: 6, deaths: 2, assists: 1, paintTiles: 300),
                FighterStats(id: 3, name: "Kraze", team: .purple, kills: 4, deaths: 3, assists: 0, paintTiles: 200),
                FighterStats(id: 1, name: "Nino", team: .orange, kills: 3, deaths: 1, assists: 2, paintTiles: 150),
            ],
            orangeScore: 0,
            purpleScore: 0
        ),
        summary: MatchMetaSummary(
            xpLines: [
                XPLine(label: "Couverture", amount: 80),
                XPLine(label: "Éliminations", amount: 72),
                XPLine(label: "Victoire", amount: 50),
            ],
            totalXP: 202,
            pigmentsEarned: 96,
            levelBefore: 3,
            levelAfter: 4,
            progressBefore: 0.7,
            progressAfter: 0.2,
            chestEarned: .silver,
            newTitles: []
        ),
        onReplay: {},
        onMenu: {}
    )
}
