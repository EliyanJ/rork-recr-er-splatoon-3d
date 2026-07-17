import SwiftUI

/// Écran "SAISON 1" — même habillage que les 5 écrans du menu (fond plein
/// écran, en-tête, marge de sécurité responsive, barre de navigation basse),
/// avec un rail de gauche à 3 onglets : Passe de combat (paliers 1-50 en
/// scroll horizontal, piste gratuite + premium), Quêtes et Défis (listes
/// factices avec réclamation qui crédite réellement Pigments/Prismes).
struct SeasonPassView: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private enum SeasonTab: String, CaseIterable {
        case rewards, quests, challenges

        var title: String {
            switch self {
            case .rewards: "Passe de combat"
            case .quests: "Quêtes"
            case .challenges: "Défis"
            }
        }

        var icon: String {
            switch self {
            case .rewards: "crown.fill"
            case .quests: "target"
            case .challenges: "trophy.fill"
            }
        }
    }

    private struct SeasonTask: Identifiable {
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
    @State private var showBuyConfirm = false
    @State private var tab: SeasonTab = .rewards

    @State private var quests: [SeasonTask] = [
        SeasonTask(icon: "paintpalette.fill", title: "Peins 2 000 m² d'encre cette saison", current: 1450, goal: 2000, rewardPigments: 120, rewardPrisms: 0),
        SeasonTask(icon: "flag.checkered", title: "Termine 10 matchs classés", current: 6, goal: 10, rewardPigments: 0, rewardPrisms: 30),
        SeasonTask(icon: "scope", title: "Élimine 25 rivaux avec le Sniper", current: 25, goal: 25, rewardPigments: 200, rewardPrisms: 0),
    ]

    @State private var challenges: [SeasonTask] = [
        SeasonTask(icon: "trophy.fill", title: "Atteins le palier 20 du Carnet", current: 45, goal: 20, rewardPigments: 0, rewardPrisms: 80),
        SeasonTask(icon: "shippingbox.fill", title: "Ouvre 5 coffres cette saison", current: 3, goal: 5, rewardPigments: 150, rewardPrisms: 0),
        SeasonTask(icon: "crown.fill", title: "Débloque la piste Premium", current: 0, goal: 1, rewardPigments: 0, rewardPrisms: 100),
    ]

    var body: some View {
        MenuScreenScaffold(
            title: "SAISON 1",
            activeTab: .shop,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            VStack(spacing: 8 * scale) {
                Text("CYCLE 1 · L'ENTREPÔT SUD")
                    .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(Team.orange.color)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 10 * scale) {
                    sidebar(scale: scale)
                        .frame(width: 128 * scale)

                    contentArea(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert("Débloquer la piste Premium ?", isPresented: $showBuyConfirm) {
            Button("Débloquer — 💎 \(MetaStore.premiumPassPrice)") {
                if meta.buyPremiumPass() {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(meta.prisms >= MetaStore.premiumPassPrice
                 ? "Toutes les récompenses premium des paliers déjà atteints seront créditées immédiatement."
                 : "Il te manque des Prismes — recharge dans la Boutique.")
        }
    }

    // MARK: - Rail de gauche

    private func sidebar(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            ForEach(SeasonTab.allCases, id: \.rawValue) { item in
                Button {
                    tab = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 7 * scale) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13 * scale, weight: .bold))
                        Text(item.title.uppercased())
                            .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(tab == item ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                tab == item
                                ? AnyShapeStyle(LinearGradient(colors: [.menuAccent, Team.orange.color], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.white.opacity(0.08))
                            )
                    )
                }
                .buttonStyle(PressableStyle())
            }

            Spacer(minLength: 6)

            VStack(alignment: .leading, spacing: 3) {
                Label("SAISON 1", systemImage: "clock.fill")
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Fin dans 32j 14h")
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Team.orange.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.4)))
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private func contentArea(scale: CGFloat) -> some View {
        switch tab {
        case .rewards:
            VStack(spacing: 9 * scale) {
                progressCard(scale: scale)
                tiersScroll(scale: scale)
                if !meta.hasPremiumPass {
                    buyButton(scale: scale)
                }
            }
        case .quests:
            taskList(quests: $quests, scale: scale, emptyText: "Aucune quête pour l'instant.")
        case .challenges:
            taskList(quests: $challenges, scale: scale, emptyText: "Aucun défi pour l'instant.")
        }
    }

    private func progressCard(scale: CGFloat) -> some View {
        VStack(spacing: 7 * scale) {
            HStack {
                Text("Palier \(meta.seasonTier) / \(MetaStore.seasonTierCount)")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text(meta.hasPremiumPass ? "PREMIUM ✓" : "PISTE GRATUITE")
                    .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(meta.hasPremiumPass ? .menuAccent : .white.opacity(0.5))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [Team.orange.color, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(6, geo.size.width * meta.seasonTierProgress))
                }
            }
            .frame(height: 9 * scale)
            Text("L'XP de chaque match fait avancer le Carnet.")
                .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12 * scale)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.4)))
    }

    private func tiersScroll(scale: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 9 * scale) {
                    ForEach(1...MetaStore.seasonTierCount, id: \.self) { tier in
                        tierColumn(tier, scale: scale)
                            .id(tier)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(max(1, meta.seasonTier), anchor: .center)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func tierColumn(_ tier: Int, scale: CGFloat) -> some View {
        let reached = tier <= meta.seasonTier
        let isCurrent = tier == meta.seasonTier + 1
        return VStack(spacing: 7 * scale) {
            Text("\(tier)")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(reached ? Team.orange.color : (isCurrent ? .white : .white.opacity(0.4)))
                .frame(width: 28 * scale, height: 20 * scale)
                .background(Capsule().fill(.white.opacity(reached || isCurrent ? 0.15 : 0.06)))

            rewardCell(MetaStore.freeReward(tier: tier), unlocked: reached, premium: false, scale: scale)
            rewardCell(MetaStore.premiumReward(tier: tier), unlocked: reached && meta.hasPremiumPass, premium: true, scale: scale)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14).fill(isCurrent ? Team.orange.color.opacity(0.12) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isCurrent ? Team.orange.color.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func rewardCell(_ reward: SeasonReward, unlocked: Bool, premium: Bool, scale: CGFloat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: unlocked ? "checkmark.circle.fill" : reward.iconSystemName)
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(unlocked ? .green : (premium ? .menuAccent : Team.orange.color))
            Text(reward.displayName)
                .font(.system(size: 7.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(unlocked ? 0.9 : 0.6))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 64 * scale)
            Text(premium ? "PREMIUM" : "GRATUIT")
                .font(.system(size: 6 * scale, weight: .black, design: .rounded))
                .foregroundStyle(premium ? .menuAccent.opacity(0.8) : .white.opacity(0.4))
        }
        .frame(width: 74 * scale, height: 76 * scale)
        .background(RoundedRectangle(cornerRadius: 12).fill(premium ? Color.menuAccent.opacity(0.08) : .white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(premium ? Color.menuAccent.opacity(0.35) : .white.opacity(0.12), lineWidth: 1))
    }

    private func buyButton(scale: CGFloat) -> some View {
        Button {
            showBuyConfirm = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label("DÉBLOQUER LA PISTE PREMIUM — 💎 \(MetaStore.premiumPassPrice)", systemImage: "crown.fill")
                .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12 * scale)
                .background(Capsule().fill(Color.menuAccent).shadow(color: .menuAccent.opacity(0.45), radius: 10, y: 3))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Quêtes / Défis

    private func taskList(quests: Binding<[SeasonTask]>, scale: CGFloat, emptyText: String) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8 * scale) {
                if quests.wrappedValue.isEmpty {
                    Text(emptyText)
                        .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 24)
                } else {
                    ForEach(quests.wrappedValue) { task in
                        taskRow(task, scale: scale) { claim(task, in: quests) }
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func taskRow(_ task: SeasonTask, scale: CGFloat, onClaim: @escaping () -> Void) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: task.icon)
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(task.claimed ? .green : .menuAccent)
                .frame(width: 30 * scale, height: 30 * scale)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { proxy in
                        Capsule()
                            .fill(task.isComplete ? Color.green : Color(hex: "35C46A"))
                            .frame(width: proxy.size.width * task.progress)
                    }
                }
                .frame(height: 6 * scale)

                Text("\(min(task.current, task.goal)) / \(task.goal)")
                    .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }

            Spacer(minLength: 6)

            Button(action: onClaim) {
                VStack(spacing: 2) {
                    if task.rewardPigments > 0 {
                        Text("+\(task.rewardPigments) 🎨").font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    }
                    if task.rewardPrisms > 0 {
                        Text("+\(task.rewardPrisms) 💎").font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    }
                }
                .foregroundStyle(task.claimed ? .white.opacity(0.5) : .black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6 * scale)
                .frame(minWidth: 58 * scale)
                .background(Capsule().fill(task.claimed ? .white.opacity(0.1) : (task.isComplete ? Color.menuAccent : .white.opacity(0.15))))
            }
            .buttonStyle(PressableStyle())
            .disabled(task.claimed || !task.isComplete)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9 * scale)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(task.isComplete && !task.claimed ? Color.menuAccent.opacity(0.6) : .clear, lineWidth: 1.5))
    }

    private func claim(_ task: SeasonTask, in list: Binding<[SeasonTask]>) {
        guard let index = list.wrappedValue.firstIndex(where: { $0.id == task.id }) else { return }
        guard list.wrappedValue[index].isComplete, !list.wrappedValue[index].claimed else { return }
        if list.wrappedValue[index].rewardPigments > 0 { meta.grantPigments(list.wrappedValue[index].rewardPigments) }
        if list.wrappedValue[index].rewardPrisms > 0 { meta.grantPrisms(list.wrappedValue[index].rewardPrisms) }
        list.wrappedValue[index].claimed = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

#Preview {
    SeasonPassView(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
