import SwiftUI

/// Écran "CHOIX DE L'ARÈNE" — bandeau horizontal des modes de jeu en haut,
/// grille de vignettes d'arènes au centre (avec « Carte aléatoire » et les
/// emplacements à venir grisés), bandeau de règle et bouton de lancement en
/// bas. Le mode sélectionné est écrit dans le profil, seule source de vérité
/// pour le lancement du match.
struct ArenaSelectScreen: View {
    @Binding var selectedMap: ArenaMap
    let onBack: () -> Void
    let onConfirm: () -> Void

    private struct ArenaInfo {
        let tags: [String]
        let complexity: String
        let imageName: String
    }

    /// Arène « à venir » purement décorative, pour densifier la grille.
    private struct ComingSoonArena: Identifiable {
        let id = UUID()
        let name: String
        let level: Int
    }

    @State private var profile = ProfileStore.shared
    @State private var isRandom = false
    @State private var appeared = false

    private let arenaInfo: [ArenaMap: ArenaInfo] = [
        .nexusDocks: ArenaInfo(
            tags: ["Conteneurs", "Tyroliennes", "Néons"],
            complexity: "Moyenne",
            imageName: "shipping_container_arena"
        ),
        .templeLost: ArenaInfo(
            tags: ["Canaux", "Pierre moussue", "Cristaux"],
            complexity: "Élevée",
            imageName: "jungle_ruins_skyline"
        ),
    ]

    private let comingSoon: [ComingSoonArena] = [
        ComingSoonArena(name: "Usine Pigmenta", level: 6),
        ComingSoonArena(name: "Toits de Chroma", level: 10),
        ComingSoonArena(name: "Station Néon", level: 14),
    ]

    private var maps: [ArenaMap] { ArenaMap.allCases }

    private func tint(for map: ArenaMap) -> Color {
        switch map {
        case .nexusDocks: Color(hex: "FF7A1A")
        case .templeLost: Color(hex: "35C46A")
        }
    }

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let scale = menuScaleFactor(for: geo.size.height)
                VStack(spacing: 8 * scale) {
                    header(scale: scale)
                    modeStrip(scale: scale)
                    arenaGrid(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomBar(scale: scale)
                }
                .padding(menuBaseMargin)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
        }
    }

    // MARK: - En-tête

    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Button {
                onBack()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5 * scale) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12 * scale, weight: .black))
                    Text("LOBBY")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6 * scale)
                .background(Capsule().fill(.black.opacity(0.55)))
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            Spacer(minLength: 0)

            Text(profile.matchMode.displayName.uppercased())
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)

            Spacer(minLength: 0)

            // Équilibre visuel avec le bouton retour.
            Color.clear.frame(width: 74 * scale, height: 1)
        }
    }

    // MARK: - Bandeau horizontal des modes

    private func modeStrip(scale: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6 * scale) {
                ForEach(MatchMode.allCases) { mode in
                    modeChip(mode, scale: scale)
                }
                ForEach(0..<2, id: \.self) { index in
                    lockedModeChip(title: index == 0 ? "Capture" : "Escorte", level: 8 + index * 4, scale: scale)
                }
            }
            .padding(.vertical, 1)
        }
        .contentMargins(.horizontal, 2)
    }

    private func modeChip(_ mode: MatchMode, scale: CGFloat) -> some View {
        let isActive = profile.matchMode == mode
        return Button {
            profile.matchMode = mode
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 2 * scale) {
                Image(systemName: mode.iconSystemName)
                    .font(.system(size: 14 * scale, weight: .black))
                Text(mode.displayName)
                    .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(isActive ? .black : .white.opacity(0.8))
            .frame(width: 84 * scale)
            .padding(.vertical, 6 * scale)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color.menuAccent : Color.menuPanel.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? .clear : .white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
    }

    private func lockedModeChip(title: String, level: Int, scale: CGFloat) -> some View {
        VStack(spacing: 2 * scale) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14 * scale, weight: .black))
            Text(title)
                .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white.opacity(0.35))
        .frame(width: 84 * scale)
        .padding(.vertical, 6 * scale)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Text("Niv.\(level)")
                .font(.system(size: 7 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(3)
        }
    }

    // MARK: - Grille des arènes

    private func arenaGrid(scale: CGFloat) -> some View {
        let columns = [GridItem(.adaptive(minimum: 118 * scale), spacing: 8 * scale)]
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8 * scale) {
                randomTile(scale: scale)
                ForEach(maps) { map in
                    arenaTile(map, scale: scale)
                }
                ForEach(comingSoon) { arena in
                    comingSoonTile(arena, scale: scale)
                }
            }
            .padding(.bottom, 2)
        }
    }

    /// Tuile « Carte aléatoire » — tire une arène au hasard au lancement.
    private func randomTile(scale: CGFloat) -> some View {
        Button {
            isRandom = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack {
                ArcadeTileBackground(tint: Color(hex: "3DB8F5"), isSelected: isRandom)
                VStack(spacing: 5 * scale) {
                    Image(systemName: "die.face.5.fill")
                        .font(.system(size: 26 * scale, weight: .black))
                        .foregroundStyle(Color(hex: "3DB8F5"))
                        .shadow(color: Color(hex: "3DB8F5").opacity(0.7), radius: 7)
                    Text("CARTE ALÉATOIRE")
                        .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(8 * scale)
            }
            .frame(height: 84 * scale)
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
    }

    private func arenaTile(_ map: ArenaMap, scale: CGFloat) -> some View {
        let info = arenaInfo[map]
        let isSelected = !isRandom && selectedMap == map
        return Button {
            isRandom = false
            selectedMap = map
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .bottom) {
                // Vignette photo de l'arène, ancrée par un Color pour ne pas
                // déborder de la tuile.
                Color(hex: "12131A")
                    .overlay {
                        if let name = info?.imageName, UIImage(named: name) != nil {
                            Image(name)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                VStack(spacing: 1) {
                    Text(map.displayName.uppercased())
                        .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(Int(map.width))×\(Int(map.depth)) m · \(info?.complexity ?? "—")")
                        .font(.system(size: 7.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6 * scale)
            }
            .frame(height: 84 * scale)
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
            .overlay(
                RoundedRectangle(cornerRadius: ArcadeKit.tileCorner)
                    .stroke(isSelected ? Color.menuAccent : tint(for: map).opacity(0.55), lineWidth: isSelected ? 2.5 : 1.5)
            )
            .shadow(color: isSelected ? Color.menuAccent.opacity(0.5) : .clear, radius: 8)
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
    }

    private func comingSoonTile(_ arena: ComingSoonArena, scale: CGFloat) -> some View {
        ZStack {
            ArcadeTileBackground(tint: .gray, isLocked: true)
            VStack(spacing: 4 * scale) {
                Spacer(minLength: 0)
                Text(arena.name.uppercased())
                    .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(8 * scale)
            ArcadeLockOverlay(requirement: "Niv.\(arena.level)", scale: scale)
        }
        .frame(height: 84 * scale)
        .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Bas d'écran : règle du mode + lancement

    private func bottomBar(scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            ArcadeInfoBar(text: profile.matchMode.subtitle, scale: scale)
                .frame(maxWidth: .infinity)

            Button {
                if isRandom, let random = maps.randomElement() {
                    selectedMap = random
                }
                onConfirm()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12 * scale, weight: .black))
                    Text("AU COMBAT !")
                        .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20 * scale)
                .padding(.vertical, 10 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [ArcadeKit.cash, ArcadeKit.cash.opacity(0.68)], startPoint: .top, endPoint: .bottom))
                )
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1.5))
                .shadow(color: ArcadeKit.cash.opacity(0.45), radius: 8, y: 3)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

#Preview {
    ArenaSelectScreen(selectedMap: .constant(.nexusDocks), onBack: {}, onConfirm: {})
}
