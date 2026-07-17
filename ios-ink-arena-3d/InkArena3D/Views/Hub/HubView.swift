import SwiftUI

/// Reveal payload: which chest was opened and what it contained.
struct ChestRevealPayload: Identifiable {
    let id = UUID()
    let chest: ChestType
    let rewards: [ChestReward]
}

/// Tabbed client hub — Accueil / Armurerie / Boutique / Profil, with a
/// persistent status bar (level, XP, both currencies) on every tab and the
/// shared modal screens (réglages, glossaire, carnet de saison, coffres,
/// probabilités) presented from here.
struct HubView: View {
    let onPlay: () -> Void

    enum Tab: String, CaseIterable {
        case home, armory, shop, profile

        var title: String {
            switch self {
            case .home: "Accueil"
            case .armory: "Armurerie"
            case .shop: "Boutique"
            case .profile: "Profil"
            }
        }

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .armory: "shield.lefthalf.filled"
            case .shop: "storefront.fill"
            case .profile: "person.crop.circle.fill"
            }
        }
    }

    @State private var tab: Tab = .home
    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared
    @State private var showSecondaryMenu = false
    @State private var showSettings = false
    @State private var showGlossary = false
    @State private var showSeasonPass = false
    @State private var showOdds = false
    @State private var showLegal = false
    @State private var chestReveal: ChestRevealPayload?

    var body: some View {
        ZStack {
            MenuBackground()

            VStack(spacing: 0) {
                statusBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                Group {
                    switch tab {
                    case .home:
                        HomeTabView(
                            onPlay: onPlay,
                            onOpenSeason: { showSeasonPass = true },
                            onOpenChest: openNextChest,
                            onOpenMenu: { showSecondaryMenu = true }
                        )
                    case .armory:
                        EquipmentScreen(
                            onBack: { tab = .home },
                            onSelectTab: { _ in },
                            onSettings: { showSettings = true }
                        )
                    case .shop:
                        ShopTabView(
                            onShowOdds: { showOdds = true },
                            onOpenSeason: { showSeasonPass = true }
                        )
                    case .profile:
                        ProfileTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                tabBar
            }
        }
        .sheet(isPresented: $showSecondaryMenu) { secondaryMenu }
        .fullScreenCover(isPresented: $showSettings) {
            ZStack {
                MenuBackground()
                SettingsOverlay(controller: nil) { showSettings = false }
            }
        }
        .sheet(isPresented: $showGlossary) { GlossaryView() }
        .fullScreenCover(isPresented: $showSeasonPass) {
            SeasonPassView(
                onBack: { showSeasonPass = false },
                onSelectTab: { _ in showSeasonPass = false },
                onSettings: { showSettings = true }
            )
        }
        .sheet(isPresented: $showOdds) { OddsView() }
        .sheet(isPresented: $showLegal) { legalSheet }
        .fullScreenCover(item: $chestReveal) { payload in
            ChestRevealView(payload: payload) { chestReveal = nil }
        }
    }

    private func openNextChest() {
        guard let type = meta.nextReadyChest else { return }
        let rewards = meta.openChest(type)
        guard !rewards.isEmpty else { return }
        chestReveal = ChestRevealPayload(chest: type, rewards: rewards)
    }

    // MARK: - Barre de statut (fixe sur les 4 onglets)

    private var statusBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(profile.accentColor.opacity(0.9))
                    Text("\(meta.accountLevel)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.playerName)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule()
                                .fill(Team.orange.color)
                                .frame(width: max(4, geo.size.width * meta.accountLevelProgress))
                        }
                    }
                    .frame(width: 74, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.45)))

            Spacer(minLength: 4)

            currencyChip(icon: "paintpalette.fill", tint: Team.orange.color, value: meta.pigments)
            currencyChip(icon: "diamond.fill", tint: Color(hex: "3DB8F5"), value: meta.prisms) {
                tab = .shop
            }

            Button {
                showSecondaryMenu = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(9)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func currencyChip(
        icon: String,
        tint: Color,
        value: Int,
        onPlus: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
            if let onPlus {
                Button(action: onPlus) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.45)))
        .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1.5))
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.rawValue) { item in
                Button {
                    tab = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: .bold))
                            .symbolEffect(.bounce, value: tab == item)
                        Text(item.title)
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(tab == item ? Team.orange.color : .white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.black.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
    }

    // MARK: - Menu secondaire (⚙️)

    private var secondaryMenu: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("MENU")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                menuRow(icon: "gearshape.fill", title: "Réglages") {
                    showSecondaryMenu = false
                    showSettings = true
                }
                menuRow(icon: "questionmark.circle.fill", title: "Comment jouer") {
                    showSecondaryMenu = false
                    showGlossary = true
                }
                menuRow(icon: "envelope.fill", title: "Support / Contact") {
                    if let url = URL(string: "mailto:support@inkarena.app") {
                        UIApplication.shared.open(url)
                    }
                }
                menuRow(icon: "doc.text.fill", title: "CGU & Confidentialité") {
                    showSecondaryMenu = false
                    showLegal = true
                }

                Text("Version 1.0")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .presentationDetents([.medium])
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Team.orange.color)
                    .frame(width: 26)
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var legalSheet: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("CGU & CONFIDENTIALITÉ")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Splash est un jeu d'arène en 3D. Ta progression (niveau, devises, cosmétiques, historique de matchs) est stockée uniquement sur ton appareil — aucune donnée personnelle n'est collectée ni transmise.\n\nLes achats en jeu sont facultatifs et purement cosmétiques : aucun objet acheté n'augmente les statistiques de combat. Les probabilités d'obtention des coffres sont affichées avant tout achat (Boutique → Probabilités).\n\nEn jouant, tu acceptes ces conditions d'utilisation.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(3)
                }
                .padding(24)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    HubView(onPlay: {})
}
