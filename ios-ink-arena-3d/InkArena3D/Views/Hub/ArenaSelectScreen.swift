import SwiftUI

/// Écran "CHOIX DE L'ARÈNE" — colonne de menu à gauche (Arène actif, Mode de
/// jeu / Règles / Équipes pour l'instant informatifs), cartes d'arènes en
/// grand format au centre avec pagination, panneau d'infos à droite. Utilise
/// les vraies arènes du jeu (Nexus Docks / Temple Lost) ; seuls les tags et
/// la complexité sont factices (pas encore modélisés).
struct ArenaSelectScreen: View {
    @Binding var selectedMap: ArenaMap
    let onBack: () -> Void
    let onConfirm: () -> Void

    private enum SideMenu: String, CaseIterable {
        case arena, mode, rules, teams

        var title: String {
            switch self {
            case .arena: "ARÈNE"
            case .mode: "MODE DE JEU"
            case .rules: "RÈGLES"
            case .teams: "ÉQUIPES"
            }
        }

        var icon: String {
            switch self {
            case .arena: "map.fill"
            case .mode: "flag.checkered"
            case .rules: "book.closed.fill"
            case .teams: "person.3.fill"
            }
        }

        var isLocked: Bool { self == .rules }
    }

    private struct ArenaInfo {
        let tags: [String]
        let complexity: String
        let type: String
        let goodToKnow: String
    }

    @State private var sideMenu: SideMenu = .arena
    @State private var pageIndex = 0
    @State private var appeared = false

    private let arenaInfo: [ArenaMap: ArenaInfo] = [
        .nexusDocks: ArenaInfo(
            tags: ["Conteneurs", "Tyroliennes", "Néons", "Grues"],
            complexity: "Moyenne",
            type: "Industriel — coucher de soleil",
            goodToKnow: "Les tyroliennes permettent des flanks rapides sur les toits — surveille les hauteurs."
        ),
        .templeLost: ArenaInfo(
            tags: ["Canaux d'eau", "Pierre moussue", "Cristaux", "Cascades"],
            complexity: "Élevée",
            type: "Jungle engloutie — ambiance mystique",
            goodToKnow: "L'eau ralentit tes déplacements hors de ton encre : reste sur ton pigment pour rester rapide."
        ),
    ]

    /// Card gradient per map — keeps the two existing maps pixel-identical.
    private func cardGradient(_ map: ArenaMap) -> [Color] {
        switch map {
        case .nexusDocks: [Color(hex: "FF7A1A").opacity(0.6), Color(hex: "8A2BE2").opacity(0.5)]
        case .templeLost: [Color(hex: "35C46A").opacity(0.6), Color(hex: "1AF0C4").opacity(0.45)]
        }
    }

    private var maps: [ArenaMap] { ArenaMap.allCases }

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let scale = menuScaleFactor(for: geo.size.height)
                VStack(spacing: 10 * scale) {
                    header(scale: scale)

                    HStack(alignment: .top, spacing: 12 * scale) {
                        sideColumn(scale: scale)
                            .frame(width: min(150, geo.size.width * 0.2))

                        centerArenas(scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        infoPanel(scale: scale)
                            .frame(width: min(190, geo.size.width * 0.26))
                    }
                    .frame(maxHeight: .infinity)

                    confirmButton(scale: scale)
                }
                .padding(menuBaseMargin)
            }
        }
        .onAppear {
            pageIndex = maps.firstIndex(of: selectedMap) ?? 0
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { appeared = true }
        }
    }

    // MARK: Header

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

            Text("CHOIX DE L'ARÈNE")
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 0)
        }
    }

    // MARK: Colonne de gauche

    private func sideColumn(scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ForEach(SideMenu.allCases, id: \.rawValue) { item in
                Button {
                    guard !item.isLocked else { return }
                    sideMenu = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7 * scale) {
                        Image(systemName: item.isLocked ? "lock.fill" : item.icon)
                            .font(.system(size: 11 * scale, weight: .black))
                            .frame(width: 16 * scale)
                        Text(item.title)
                            .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(item.isLocked ? .white.opacity(0.3) : (sideMenu == item ? .black : .white))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8 * scale)
                    .frame(maxWidth: .infinity)
                    .background(
                        PaintedPanel(skew: 3)
                            .fill(sideMenu == item ? Color.menuAccent : Color.menuPanel.opacity(0.8))
                    )
                    .overlay(PaintedPanel(skew: 3).stroke(.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .opacity(item.isLocked ? 0.7 : 1)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Cartes d'arène centrales

    private func centerArenas(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            TabView(selection: $pageIndex) {
                ForEach(Array(maps.enumerated()), id: \.element.id) { index, map in
                    arenaCard(map, scale: scale)
                        .tag(index)
                        .padding(.horizontal, 4)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: pageIndex) { _, newValue in
                guard maps.indices.contains(newValue) else { return }
                selectedMap = maps[newValue]
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            HStack(spacing: 6) {
                ForEach(maps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == pageIndex ? Color.menuAccent : .white.opacity(0.25))
                        .frame(width: index == pageIndex ? 20 : 6, height: 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: pageIndex)
                }
            }
        }
    }

    private func arenaCard(_ map: ArenaMap, scale: CGFloat) -> some View {
        let info = arenaInfo[map]
        return VStack(alignment: .leading, spacing: 8 * scale) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: cardGradient(map),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: map.iconSystemName)
                    .font(.system(size: 46 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(map.displayName.uppercased())
                        .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(map.tagline)
                        .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)
                }
                .padding(14)
            }
            .frame(height: 140 * scale)

            if let info {
                HStack(spacing: 6 * scale) {
                    ForEach(info.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.1)))
                    }
                }
            }
        }
        .padding(10 * scale)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(selectedMap == map ? Color.menuAccent : .white.opacity(0.12), lineWidth: 2)
        )
    }

    // MARK: Panneau d'infos

    private func infoPanel(scale: CGFloat) -> some View {
        let info = arenaInfo[selectedMap]
        return VStack(alignment: .leading, spacing: 10 * scale) {
            Text("INFOS DE L'ARÈNE")
                .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            infoRow(icon: "ruler.fill", label: "Taille", value: "\(Int(selectedMap.width))×\(Int(selectedMap.depth)) m", scale: scale)
            infoRow(icon: "gauge.with.needle.fill", label: "Complexité", value: info?.complexity ?? "—", scale: scale)
            infoRow(icon: "tag.fill", label: "Type", value: info?.type ?? "—", scale: scale)

            Divider().overlay(.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 4) {
                Label("À SAVOIR", systemImage: "lightbulb.fill")
                    .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.menuAccent)
                Text(info?.goodToKnow ?? "")
                    .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(5)
            }

            Spacer(minLength: 0)
        }
        .padding(12 * scale)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func infoRow(icon: String, label: String, value: String, scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: icon)
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(.menuAccent)
                .frame(width: 14 * scale)
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Text(value)
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    // MARK: Confirmer

    private func confirmButton(scale: CGFloat) -> some View {
        Button {
            onConfirm()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Text("CONFIRMER \(selectedMap.displayName.uppercased())")
                .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.vertical, 11 * scale)
                .background(Capsule().fill(Color.menuAccent))
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    ArenaSelectScreen(selectedMap: .constant(.nexusDocks), onBack: {}, onConfirm: {})
}
