import SwiftUI

/// Écran "MISSIONS" — quatre catégories (Quotidiennes / Hebdomadaires /
/// Saisonnières / Accomplissements), chacune avec une liste de missions et
/// leur barre de progression. Données factices, réclamation simulée
/// localement (crédite Pigments/Prismes réels via MetaStore).
struct MissionsScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private enum Category: String, CaseIterable {
        case daily, weekly, season, achievements

        var title: String {
            switch self {
            case .daily: "Quotidiennes"
            case .weekly: "Hebdomadaires"
            case .season: "Saisonnières"
            case .achievements: "Exploits"
            }
        }
    }

    private struct Mission: Identifiable {
        let id = String(UUID().uuidString.prefix(8))
        let icon: String
        let title: String
        let current: Int
        let goal: Int
        let rewardPigments: Int
        let rewardPrisms: Int
        var claimed: Bool = false

        var progress: Double { min(1, Double(current) / Double(goal)) }
        var isComplete: Bool { current >= goal }
    }

    @State private var meta = MetaStore.shared
    @State private var category: Category = .daily
    @State private var missions: [Category: [Mission]] = [
        .daily: [
            Mission(icon: "paintpalette.fill", title: "Peins 3 000 m² d'encre", current: 2100, goal: 3000, rewardPigments: 150, rewardPrisms: 0),
            Mission(icon: "target", title: "Élimine 8 rivaux", current: 8, goal: 8, rewardPigments: 80, rewardPrisms: 0),
            Mission(icon: "flag.checkered", title: "Termine 2 matchs", current: 1, goal: 2, rewardPigments: 0, rewardPrisms: 40),
        ],
        .weekly: [
            Mission(icon: "trophy.fill", title: "Gagne 5 matchs", current: 3, goal: 5, rewardPigments: 400, rewardPrisms: 0),
            Mission(icon: "shippingbox.fill", title: "Ouvre 3 coffres", current: 3, goal: 3, rewardPigments: 0, rewardPrisms: 60),
            Mission(icon: "scope", title: "Maîtrise une arme au niveau 2", current: 1, goal: 1, rewardPigments: 200, rewardPrisms: 0),
        ],
        .season: [
            Mission(icon: "star.fill", title: "Atteins le palier 30 du Carnet", current: 45, goal: 30, rewardPigments: 0, rewardPrisms: 150),
            Mission(icon: "map.fill", title: "Joue sur les 2 arènes", current: 2, goal: 2, rewardPigments: 300, rewardPrisms: 0),
        ],
        .achievements: [
            Mission(icon: "crown.fill", title: "Deviens Champion de Crew (10 victoires)", current: 4, goal: 10, rewardPigments: 0, rewardPrisms: 200),
            Mission(icon: "burst.fill", title: "50 éliminations au total", current: 50, goal: 50, rewardPigments: 500, rewardPrisms: 0),
            Mission(icon: "leaf.fill", title: "Étale 5 000 m² d'encre à vie", current: 3200, goal: 5000, rewardPigments: 0, rewardPrisms: 100),
        ],
    ]

    var body: some View {
        MenuScreenScaffold(
            title: "MISSIONS",
            activeTab: .missions,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            VStack(spacing: 9 * scale) {
                categoryPicker(scale: scale)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8 * scale) {
                        ForEach(missions[category] ?? []) { mission in
                            missionRow(mission, scale: scale)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }

    private func categoryPicker(scale: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6 * scale) {
                ForEach(Category.allCases, id: \.rawValue) { item in
                    Button {
                        category = item
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(item.title.uppercased())
                            .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(category == item ? .black : .white.opacity(0.75))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7 * scale)
                            .background(Capsule().fill(category == item ? Color.menuAccent : .white.opacity(0.1)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func missionRow(_ mission: Mission, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: mission.icon)
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(mission.claimed ? .green : .menuAccent)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                Text(mission.title)
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { proxy in
                        Capsule()
                            .fill(mission.isComplete ? Color.green : Color(hex: "35C46A"))
                            .frame(width: proxy.size.width * mission.progress)
                    }
                }
                .frame(height: 6 * scale)

                Text("\(min(mission.current, mission.goal)) / \(mission.goal)")
                    .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            Spacer(minLength: 6)

            claimButton(mission, scale: scale)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9 * scale)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(mission.isComplete && !mission.claimed ? Color.menuAccent.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func claimButton(_ mission: Mission, scale: CGFloat) -> some View {
        Button {
            claim(mission)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            VStack(spacing: 2) {
                if mission.rewardPigments > 0 {
                    Text("+\(mission.rewardPigments) 🎨").font(.system(size: 9 * scale, weight: .black, design: .rounded))
                }
                if mission.rewardPrisms > 0 {
                    Text("+\(mission.rewardPrisms) 💎").font(.system(size: 9 * scale, weight: .black, design: .rounded))
                }
            }
            .foregroundStyle(mission.claimed ? .white.opacity(0.5) : .black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6 * scale)
            .frame(minWidth: 58 * scale)
            .background(
                Capsule().fill(mission.claimed ? .white.opacity(0.1) : (mission.isComplete ? Color.menuAccent : .white.opacity(0.15)))
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(mission.claimed || !mission.isComplete)
    }

    private func claim(_ mission: Mission) {
        guard var list = missions[category], let index = list.firstIndex(where: { $0.id == mission.id }) else { return }
        guard list[index].isComplete, !list[index].claimed else { return }
        if list[index].rewardPigments > 0 { meta.grantPigments(list[index].rewardPigments) }
        if list[index].rewardPrisms > 0 { meta.grantPrisms(list[index].rewardPrisms) }
        list[index].claimed = true
        missions[category] = list
    }
}

#Preview {
    MissionsScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
