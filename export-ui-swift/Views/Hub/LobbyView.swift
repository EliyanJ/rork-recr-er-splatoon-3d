import SwiftUI

/// Lobby de passage entre l'Accueil et le match : choix du mode (Normal
/// actif, Classé verrouillé pour l'instant), choix de la map, équipe
/// affichée, résumé du loadout avec accès direct à l'écran Équipement
/// (fullscreen), et le bouton PRÊT qui lance la partie. Le Duel local (et ses
/// variantes) vit désormais dans Partie personnalisée, accessible depuis
/// l'écran JOUER — ce lobby ne gère plus que le match Normal contre l'IA.
/// Même habillage (panneaux peints, marge responsive) que les 5 autres
/// écrans du menu.
struct LobbyView: View {
    let onReady: () -> Void
    let onBack: () -> Void

    private enum Mode: String, CaseIterable {
        case normal, ranked

        var title: String {
            switch self {
            case .normal: "Normal"
            case .ranked: "Classé"
            }
        }

        var isLocked: Bool { self == .ranked }
    }

    @State private var mode: Mode = .normal
    @State private var selectedMap: ArenaMap = ProfileStore.shared.selectedMap
    @State private var botDifficulty: BotDifficulty = ProfileStore.shared.botDifficulty
    @State private var matchMode: MatchMode = ProfileStore.shared.matchMode
    @State private var showArmory = false
    @State private var showLockedNotice = false
    @State private var showArenaSelect = false
    @State private var showPlayerConnect = false
    @State private var showSettings = false
    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared

    private let squad = ["Splatty-Bot", "InkMaster-Bot"]
    private let rivals = ["Violette-Bot", "Kraken-Bot", "Poulpe-Bot"]

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let scale = menuScaleFactor(for: geo.size.height)
                VStack(spacing: 10 * scale) {
                    MenuHeaderBar(
                        title: "PRÉPARATION DU MATCH",
                        scale: scale,
                        onBack: onBack,
                        pigments: meta.pigments,
                        prisms: meta.prisms,
                        onSettings: { showSettings = true }
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10 * scale) {
                            modePicker(scale: scale)
                            mapRow(scale: scale)
                            matchModeRow(scale: scale)
                            botDifficultyRow(scale: scale)
                            playersCard(scale: scale)
                            loadoutCard(scale: scale)
                        }
                        .padding(.bottom, 4)
                    }

                    readyButton(scale: scale)
                }
                .padding(menuBaseMargin)
            }
        }
        .fullScreenCover(isPresented: $showArmory) {
            EquipmentScreen(
                onBack: { showArmory = false },
                onSelectTab: { _ in showArmory = false },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(onClose: { showSettings = false })
        }
        .alert("Bientôt disponible", isPresented: $showLockedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Le mode Classé arrivera avec le multijoueur en ligne. En attendant : match Normal contre l'IA, ou Partie personnalisée entre amis depuis l'écran JOUER.")
        }
        .fullScreenCover(isPresented: $showArenaSelect) {
            ArenaSelectScreen(
                selectedMap: $selectedMap,
                onBack: { showArenaSelect = false },
                onConfirm: { showArenaSelect = false }
            )
        }
        .fullScreenCover(isPresented: $showPlayerConnect) {
            PlayerConnectScreen {
                showPlayerConnect = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    launchMatch()
                }
            }
        }
    }

    private func modePicker(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            ForEach(Mode.allCases, id: \.rawValue) { item in
                Button {
                    if item.isLocked {
                        showLockedNotice = true
                    } else {
                        mode = item
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        if item.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9 * scale, weight: .black))
                        }
                        Text(item.title.uppercased())
                            .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(mode == item ? .black : .white.opacity(item.isLocked ? 0.4 : 0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9 * scale)
                    .background(
                        Capsule().fill(mode == item ? Color.menuAccent : .white.opacity(0.1))
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    /// Thumbnail gradient per map — keeps the two existing maps pixel-identical.
    private func mapGradient(_ map: ArenaMap) -> [Color] {
        switch map {
        case .nexusDocks: [Color(hex: "FF7A1A").opacity(0.55), Color(hex: "8A2BE2").opacity(0.5)]
        case .templeLost: [Color(hex: "35C46A").opacity(0.55), Color(hex: "1AF0C4").opacity(0.4)]
        }
    }

    private func mapRow(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            Text("ARÈNE")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Button {
                showArenaSelect = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12 * scale) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: mapGradient(selectedMap),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52 * scale, height: 52 * scale)
                        Image(systemName: selectedMap.iconSystemName)
                            .font(.system(size: 20 * scale, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedMap.displayName.uppercased())
                            .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text(selectedMap.tagline)
                            .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 11 * scale, weight: .bold))
                        Text("CHANGER")
                            .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.menuAccent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10 * scale)
                .frame(maxWidth: .infinity)
                .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.88)))
                .overlay(PaintedPanel(skew: 4).stroke(Color.menuAccent.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(PressableStyle())
        }
    }

    /// Win-condition variant for the next match — applies to every player
    /// and bot in the match, whether it's Match contre l'IA or Partie
    /// personnalisée.
    private func matchModeRow(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack {
                Text("TYPE DE PARTIE")
                    .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Image(systemName: matchMode.iconSystemName)
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(Color.menuAccent)
            }
            Text(matchMode.subtitle)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            HStack(spacing: 8 * scale) {
                ForEach(MatchMode.allCases) { candidate in
                    Button {
                        matchMode = candidate
                        ProfileStore.shared.matchMode = candidate
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(candidate.displayName.uppercased())
                            .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(matchMode == candidate ? .black : .white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9 * scale)
                            .background(
                                Capsule().fill(matchMode == candidate ? Color.menuAccent : .white.opacity(0.1))
                            )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    /// Bot skill tier — every AI teammate and rival in the match shares it.
    private func botDifficultyRow(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            HStack {
                Text("NIVEAU DES BOTS")
                    .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Image(systemName: botDifficulty.iconSystemName)
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(Color.menuAccent)
                Text(botDifficulty.subtitle)
                    .font(.system(size: 8.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(spacing: 8 * scale) {
                ForEach(BotDifficulty.allCases) { level in
                    Button {
                        botDifficulty = level
                        ProfileStore.shared.botDifficulty = level
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(level.displayName.uppercased())
                            .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(botDifficulty == level ? .black : .white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9 * scale)
                            .background(
                                Capsule().fill(botDifficulty == level ? Color.menuAccent : .white.opacity(0.1))
                            )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func playersCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text("ÉQUIPES — 3 VS 3")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 12 * scale) {
                VStack(spacing: 6 * scale) {
                    playerChip(name: profile.playerName, team: .orange, isYou: true, scale: scale)
                    ForEach(squad, id: \.self) { name in
                        playerChip(name: name, team: .orange, isYou: false, scale: scale)
                    }
                }
                Text("VS")
                    .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                VStack(spacing: 6 * scale) {
                    ForEach(rivals, id: \.self) { name in
                        playerChip(name: name, team: .purple, isYou: false, scale: scale)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func playerChip(name: String, team: Team, isYou: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: isYou ? "person.fill" : "cpu.fill")
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(team.color)
            Text(name)
                .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            if isYou {
                Text("TOI")
                    .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.menuAccent))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isYou ? team.color.opacity(0.8) : .white.opacity(0.1), lineWidth: 1.5)
        )
    }

    private func loadoutCard(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            loadoutSlot(
                icon: profile.selectedWeapon.iconSystemName,
                title: profile.selectedWeapon.displayName,
                label: "Arme",
                scale: scale
            )
            loadoutSlot(
                icon: meta.equippedGadget.iconSystemName,
                title: meta.equippedGadget.displayName,
                label: "Gadget",
                scale: scale
            )
            Spacer(minLength: 0)
            Button {
                showArmory = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Text("MODIFIER")
                    .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9 * scale)
                    .background(Capsule().fill(Color.menuAccent))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func launchMatch() {
        onReady()
    }

    private func loadoutSlot(icon: String, title: String, label: String, scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: icon)
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(.menuAccent)
                .frame(width: 32 * scale, height: 32 * scale)
                .background(Circle().fill(.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text(title)
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func readyButton(scale: CGFloat) -> some View {
        Button {
            ProfileStore.shared.selectedMap = selectedMap
            GameConfig.currentMap = selectedMap
            GameConfig.currentMode = matchMode
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showPlayerConnect = true
        } label: {
            Label("PRÊT", systemImage: "flag.checkered")
                .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 50 * scale)
                .padding(.vertical, 14 * scale)
                .background(
                    Capsule()
                        .fill(Team.orange.color)
                        .shadow(color: Team.orange.color.opacity(0.55), radius: 14, y: 4)
                )
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    LobbyView(onReady: {}, onBack: {})
}
