import SwiftUI

/// Écran "CLASSEMENT" — podium top 3, filtres Classé/Régional/Amis, liste de
/// rangs avec le joueur mis en évidence à sa position. Données factices.
struct RankScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private enum Filter: String, CaseIterable {
        case ranked, regional, friends

        var title: String {
            switch self {
            case .ranked: "Classé"
            case .regional: "Régional"
            case .friends: "Amis"
            }
        }
    }

    private struct RankedPlayer: Identifiable {
        let id = UUID()
        let rank: Int
        let name: String
        let score: Int
        let isYou: Bool
    }

    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared
    @State private var filter: Filter = .ranked

    private func leaderboard(for filter: Filter) -> [RankedPlayer] {
        switch filter {
        case .ranked:
            return [
                RankedPlayer(rank: 1, name: "Kraken-Bot", score: 18420, isYou: false),
                RankedPlayer(rank: 2, name: "Violette-Bot", score: 17110, isYou: false),
                RankedPlayer(rank: 3, name: "Poulpe-Bot", score: 15980, isYou: false),
                RankedPlayer(rank: 4, name: "Splatty-Bot", score: 14200, isYou: false),
                RankedPlayer(rank: 5, name: profile.playerName, score: 12750, isYou: true),
                RankedPlayer(rank: 6, name: "InkMaster-Bot", score: 11430, isYou: false),
                RankedPlayer(rank: 7, name: "Néon-Bot", score: 9870, isYou: false),
            ]
        case .regional:
            return [
                RankedPlayer(rank: 1, name: "Violette-Bot", score: 21040, isYou: false),
                RankedPlayer(rank: 2, name: profile.playerName, score: 19870, isYou: true),
                RankedPlayer(rank: 3, name: "Kraken-Bot", score: 18220, isYou: false),
                RankedPlayer(rank: 4, name: "Néon-Bot", score: 16110, isYou: false),
            ]
        case .friends:
            return [
                RankedPlayer(rank: 1, name: profile.playerName, score: 12750, isYou: true),
                RankedPlayer(rank: 2, name: "Splatty-Bot", score: 14200, isYou: false),
                RankedPlayer(rank: 3, name: "InkMaster-Bot", score: 11430, isYou: false),
            ]
        }
    }

    var body: some View {
        MenuScreenScaffold(
            title: "CLASSEMENT",
            activeTab: .rank,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            let players = leaderboard(for: filter)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10 * scale) {
                    filterPicker(scale: scale)

                    if players.count >= 3 {
                        podium(players: Array(players.prefix(3)), scale: scale)
                    }

                    VStack(spacing: 6 * scale) {
                        ForEach(players) { player in
                            rankRow(player, scale: scale)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func filterPicker(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            ForEach(Filter.allCases, id: \.rawValue) { item in
                Button {
                    filter = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(item.title.uppercased())
                        .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(filter == item ? .black : .white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7 * scale)
                        .background(Capsule().fill(filter == item ? Color.menuAccent : .white.opacity(0.1)))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func podium(players: [RankedPlayer], scale: CGFloat) -> some View {
        let ordered = [players[safe: 1], players[safe: 0], players[safe: 2]].compactMap { $0 }
        return HStack(alignment: .bottom, spacing: 8 * scale) {
            ForEach(ordered) { player in
                podiumColumn(player, scale: scale)
            }
        }
        .padding(.top, 4)
    }

    private func podiumColumn(_ player: RankedPlayer, scale: CGFloat) -> some View {
        let height: CGFloat = player.rank == 1 ? 76 : (player.rank == 2 ? 60 : 48)
        let tint: Color = player.rank == 1 ? .menuAccent : (player.rank == 2 ? Color(hex: "C7CBD1") : Color(hex: "C8763A"))
        return VStack(spacing: 5 * scale) {
            ZStack {
                Circle().fill(tint.opacity(0.9))
                Text("\(player.rank)")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(width: 30 * scale, height: 30 * scale)

            Text(player.name)
                .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66 * scale)

            VStack {
                Spacer(minLength: 0)
                Text("\(player.score)")
                    .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.bottom, 4)
                    .monospacedDigit()
            }
            .frame(width: 66 * scale, height: height * scale)
            .background(PaintedPanel(skew: 3).fill(tint))
        }
    }

    private func rankRow(_ player: RankedPlayer, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Text("#\(player.rank)")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(player.isYou ? .menuAccent : .white.opacity(0.55))
                .frame(width: 30 * scale, alignment: .leading)
                .monospacedDigit()

            Image(systemName: player.isYou ? "person.fill" : "cpu.fill")
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(player.isYou ? .black : .white.opacity(0.85))
                .frame(width: 24 * scale, height: 24 * scale)
                .background(Circle().fill(player.isYou ? Color.menuAccent : .white.opacity(0.12)))

            Text(player.name)
                .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if player.isYou {
                Text("TOI")
                    .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.menuAccent))
            }

            Spacer(minLength: 4)

            Text("\(player.score)")
                .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8 * scale)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(player.isYou ? 0.14 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(player.isYou ? Color.menuAccent.opacity(0.6) : .clear, lineWidth: 1.5))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    RankScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
