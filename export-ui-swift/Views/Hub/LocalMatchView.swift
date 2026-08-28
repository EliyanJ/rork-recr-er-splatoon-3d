import SwiftUI

/// Local duel lobby — one device hosts, the other joins over Wi-Fi/Bluetooth
/// (direct iPhone-to-iPhone, no server). Once both are connected the host
/// picks the arena and launches; both devices enter the match together.
/// Même habillage (panneaux peints, marge responsive) que les autres écrans
/// du menu.
struct LocalMatchView: View {
    /// Called on BOTH devices when the host launches the match.
    let onStart: (ArenaMap, MatchMode) -> Void
    let onBack: () -> Void
    /// Header label — same connection flow reused for Duel local, Partie
    /// classique and Match par équipes personnalisé (only the wording changes).
    var modeTitle: String = "DUEL LOCAL"

    @State private var service = LocalMatchService.shared
    @State private var selectedMap: ArenaMap = ProfileStore.shared.selectedMap
    @State private var selectedMode: MatchMode = ProfileStore.shared.matchMode
    @State private var selectedBots: Int = ProfileStore.shared.duelBotsPerTeam
    @State private var selectedBotLevel: BotDifficulty = ProfileStore.shared.botDifficulty
    @State private var meta = MetaStore.shared

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
                        title: modeTitle.uppercased(),
                        scale: scale,
                        onBack: {
                            service.stop()
                            onBack()
                        },
                        pigments: meta.pigments,
                        prisms: meta.prisms
                    )

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12 * scale) {
                            infoCard(scale: scale)

                            switch service.phase {
                            case .idle:
                                roleButtons(scale: scale)
                            case .hosting:
                                waitingCard(
                                    icon: "antenna.radiowaves.left.and.right",
                                    title: "EN ATTENTE D'UN JOUEUR…",
                                    subtitle: "Ton frère doit choisir « Rejoindre » sur son iPhone, à proximité, avec Wi-Fi et Bluetooth activés.",
                                    scale: scale
                                )
                            case .browsing, .connecting:
                                browsingCard(scale: scale)
                            case .connected, .inMatch:
                                connectedCard(scale: scale)
                            }

                            if let error = service.lastError {
                                Text(error)
                                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color(hex: "F5304B"))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 12)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(menuBaseMargin)
            }
        }
        .onAppear {
            service.onStart = { map, mode, bots in
                GameConfig.currentMap = map
                GameConfig.currentMode = mode
                GameConfig.duelBotsPerTeam = bots
                onStart(map, mode)
            }
        }
    }

    private func infoCard(scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: "person.line.dotted.person.fill")
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundStyle(Team.orange.color)
            Text("Partie en local sur le même réseau : deux iPhones proches, Wi-Fi/Bluetooth activés. L'hôte peut ajouter des bots dans chaque équipe. Aucun compte, aucun serveur.")
                .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func roleButtons(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            roleButton(
                icon: "antenna.radiowaves.left.and.right",
                title: "HÉBERGER",
                subtitle: "Crée la partie — l'autre joueur te rejoint",
                accent: Team.orange.color,
                skew: 4,
                scale: scale
            ) {
                service.host()
            }
            roleButton(
                icon: "magnifyingglass",
                title: "REJOINDRE",
                subtitle: "Cherche une partie hébergée à proximité",
                accent: Team.purple.color,
                skew: -4,
                scale: scale
            ) {
                service.browse()
            }
        }
    }

    private func roleButton(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        skew: CGFloat,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12 * scale) {
                Image(systemName: icon)
                    .font(.system(size: 20 * scale, weight: .black))
                    .foregroundStyle(accent)
                    .frame(width: 48 * scale, height: 48 * scale)
                    .background(Circle().fill(.white.opacity(0.1)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * scale, weight: .black))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity)
            .background(PaintedPanel(skew: skew).fill(Color.menuPanel.opacity(0.88)))
            .overlay(PaintedPanel(skew: skew).stroke(accent.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }

    private func waitingCard(icon: String, title: String, subtitle: String, scale: CGFloat) -> some View {
        VStack(spacing: 12 * scale) {
            ZStack {
                Circle()
                    .fill(Team.orange.color.opacity(0.15))
                    .frame(width: 70 * scale, height: 70 * scale)
                Image(systemName: icon)
                    .font(.system(size: 26 * scale, weight: .bold))
                    .foregroundStyle(Team.orange.color)
            }
            ProgressView()
                .tint(.white)
            Text(title)
                .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            cancelButton(scale: scale)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
    }

    private func browsingCard(scale: CGFloat) -> some View {
        VStack(spacing: 12 * scale) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.white)
                Text(service.phase == .connecting ? "CONNEXION…" : "RECHERCHE DE PARTIES…")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            if service.foundPeers.isEmpty {
                Text("Aucune partie trouvée pour l'instant. L'hôte doit avoir appuyé sur « Héberger ».")
                    .font(.system(size: 10.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            } else {
                ForEach(service.foundPeers, id: \.self) { name in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        service.join(peerNamed: name)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 14 * scale, weight: .bold))
                                .foregroundStyle(Team.purple.color)
                            Text("Partie de \(name)")
                                .font(.system(size: 13 * scale, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("REJOINDRE")
                                .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Team.orange.color))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            cancelButton(scale: scale)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
    }

    private func connectedCard(scale: CGFloat) -> some View {
        VStack(spacing: 14 * scale) {
            HStack(spacing: 12 * scale) {
                duelChip(name: ProfileStore.shared.playerName, team: .orange, label: "TOI", scale: scale)
                Text("VS")
                    .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                duelChip(name: service.remoteName, team: .purple, label: nil, scale: scale)
            }

            Label("Connectés — prêt pour le duel !", systemImage: "checkmark.seal.fill")
                .font(.system(size: 12.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(hex: "35C46A"))

            if service.isHost {
                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("ARÈNE")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 10 * scale) {
                        ForEach(ArenaMap.allCases) { map in
                            mapPick(map, scale: scale)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("TYPE DE PARTIE")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 8 * scale) {
                        ForEach(MatchMode.allCases) { candidate in
                            modePick(candidate, scale: scale)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8 * scale) {
                    Text("BOTS PAR ÉQUIPE")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 8 * scale) {
                        ForEach([0, 1, 2], id: \.self) { count in
                            botCountPick(count, scale: scale)
                        }
                    }
                }

                if selectedBots > 0 {
                    VStack(alignment: .leading, spacing: 8 * scale) {
                        Text("NIVEAU DES BOTS")
                            .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                        HStack(spacing: 8 * scale) {
                            ForEach(BotDifficulty.allCases) { level in
                                botLevelPick(level, scale: scale)
                            }
                        }
                    }
                }

                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    GameConfig.currentMap = selectedMap
                    GameConfig.currentMode = selectedMode
                    GameConfig.duelBotsPerTeam = selectedBots
                    ProfileStore.shared.matchMode = selectedMode
                    ProfileStore.shared.duelBotsPerTeam = selectedBots
                    ProfileStore.shared.botDifficulty = selectedBotLevel
                    service.startMatch(
                        map: selectedMap,
                        mode: selectedMode,
                        bots: selectedBots,
                        botLevel: selectedBotLevel
                    )
                    onStart(selectedMap, selectedMode)
                } label: {
                    Label("LANCER LE DUEL", systemImage: "flag.checkered")
                        .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 * scale)
                        .background(
                            Capsule()
                                .fill(Team.orange.color)
                                .shadow(color: Team.orange.color.opacity(0.55), radius: 12, y: 4)
                        )
                }
                .buttonStyle(PressableStyle())
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("En attente du lancement par l'hôte…")
                        .font(.system(size: 11.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            cancelButton(scale: scale)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
    }

    private func duelChip(name: String, team: Team, label: String?, scale: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 17 * scale, weight: .bold))
                .foregroundStyle(team.color)
                .frame(width: 42 * scale, height: 42 * scale)
                .background(Circle().fill(.white.opacity(0.1)))
            Text(name)
                .font(.system(size: 11.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let label {
                Text(label)
                    .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(team.color))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10 * scale)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(team.color.opacity(0.6), lineWidth: 1.5)
        )
    }

    private func modePick(_ candidate: MatchMode, scale: CGFloat) -> some View {
        let isSelected = selectedMode == candidate
        return Button {
            selectedMode = candidate
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: candidate.iconSystemName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(candidate.displayName.uppercased())
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * scale)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isSelected ? 0.14 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Team.orange.color : .white.opacity(0.14), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func botCountPick(_ count: Int, scale: CGFloat) -> some View {
        let isSelected = selectedBots == count
        return Button {
            selectedBots = count
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: count == 0 ? "person.2.fill" : "person.fill.badge.plus")
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(count == 0 ? "AUCUN" : "+\(count) BOT\(count > 1 ? "S" : "")")
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * scale)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isSelected ? 0.14 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Team.orange.color : .white.opacity(0.14), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func botLevelPick(_ level: BotDifficulty, scale: CGFloat) -> some View {
        let isSelected = selectedBotLevel == level
        return Button {
            selectedBotLevel = level
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: level.iconSystemName)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(level.displayName.uppercased())
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10 * scale)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isSelected ? 0.14 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Team.orange.color : .white.opacity(0.14), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func mapPick(_ map: ArenaMap, scale: CGFloat) -> some View {
        let isSelected = selectedMap == map
        return Button {
            selectedMap = map
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: map.iconSystemName)
                    .font(.system(size: 18 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(map.displayName.uppercased())
                    .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12 * scale)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(isSelected ? 0.14 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Team.orange.color : .white.opacity(0.14), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func cancelButton(scale: CGFloat) -> some View {
        Button {
            service.stop()
        } label: {
            Text("ANNULER")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.1)))
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    LocalMatchView(onStart: { _, _ in }, onBack: {})
}
