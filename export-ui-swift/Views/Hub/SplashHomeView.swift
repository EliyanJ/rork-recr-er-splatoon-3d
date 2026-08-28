import SwiftUI

/// Écran d'accueil "SPLASH" — refonte client inspirée des lobbys de jeux
/// console : colonne de menu peinte à gauche (JOUER dominant), header joueur,
/// devises + notifications en haut à droite, carte Saison et barre sociale.
/// Données factices pour l'instant (backend plus tard) ; les boutons ouvrent
/// les écrans existants (Armurerie, Boutique, Saison, Profil, Réglages).
struct SplashHomeView: View {
    let onPlay: () -> Void
    let onTraining: () -> Void
    let onCustomMatch: (String) -> Void

    // MARK: Données factices (backend plus tard)
    private let mockName = "Inkling"
    private let mockLevel = 16
    private let mockXP = 3500
    private let mockXPMax = 5600
    private let mockPigments = 9470
    private let mockPrisms = 355
    private let mockSeasonEnd = "23 j 12 h"
    private let mockSeasonTier = 45
    private let mockSeasonProgress: Double = 0.62

    @State private var showArmory = false
    @State private var showShop = false
    @State private var showSeason = false
    @State private var showProfile = false
    @State private var showProfileScreen = false
    @State private var showPlay = false
    @State private var showMissions = false
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showMail = false
    @State private var showOdds = false
    @State private var appeared = false
    @State private var playPulse = false

    private let splashYellow = Color(hex: "FFC400")
    private let panelBlack = Color(hex: "121216")

    /// Marge uniforme ajoutée par-dessus la zone sûre du système (encoche,
    /// île dynamique, coins arrondis, home indicator). Le système gère déjà
    /// nativement le "vrai" espace interdit pour l'orientation courante ; on
    /// ne fait qu'ajouter un peu de respiration esthétique par-dessus.
    private let baseMargin: CGFloat = 14

    /// Réduit polices/tailles/espacements quand la hauteur disponible est
    /// restreinte (typique du paysage sur iPhone) — responsive à toutes les
    /// tailles d'écran, sans jamais faire déborder le contenu.
    private func scaleFactor(for height: CGFloat) -> CGFloat {
        min(1, max(0.68, height / 420))
    }

    var body: some View {
        ZStack {
            // Le fond seul ignore la zone sûre : il doit couvrir tout l'écran,
            // y compris sous l'île dynamique / le home indicator.
            GeometryReader { screenGeo in
                background(size: screenGeo.size)
            }
            .ignoresSafeArea()

            // Ce GeometryReader, lui, RESPECTE la zone sûre : sa taille exclut
            // déjà nativement l'île dynamique/l'encoche/le home indicator pour
            // l'orientation courante — plus fiable qu'un calcul manuel.
            GeometryReader { geo in
                let scale = scaleFactor(for: geo.size.height)

                VStack(spacing: 0) {
                    topBar(scale: scale)

                    HStack(alignment: .top, spacing: 0) {
                        leftColumn(height: geo.size.height, scale: scale)
                            .frame(width: min(320, geo.size.width * 0.4))

                        Spacer(minLength: 0)

                        VStack {
                            Spacer()
                            socialBar(scale: scale)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(baseMargin)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.05)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                playPulse = true
            }
        }
        .fullScreenCover(isPresented: $showPlay) {
            PlayScreen(
                pigments: MetaStore.shared.pigments,
                prisms: MetaStore.shared.prisms,
                onBack: { showPlay = false },
                onSelectTab: { navigate(to: $0, from: \.showPlay) },
                onSettings: { showSettings = true },
                onPlay: {
                    showPlay = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onPlay() }
                },
                onTraining: {
                    showPlay = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onTraining() }
                },
                onCustomMatch: { title in
                    showPlay = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCustomMatch(title) }
                }
            )
        }
        .fullScreenCover(isPresented: $showArmory) {
            EquipmentScreen(
                onBack: { showArmory = false },
                onSelectTab: { navigate(to: $0, from: \.showArmory) },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showShop) {
            ShopScreen(
                onBack: { showShop = false },
                onSelectTab: { navigate(to: $0, from: \.showShop) },
                onSettings: { showSettings = true },
                onShowOdds: { showOdds = true },
                onOpenSeason: {
                    showShop = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showSeason = true }
                }
            )
        }
        .fullScreenCover(isPresented: $showSeason) {
            SeasonPassView(
                onBack: { showSeason = false },
                onSelectTab: { navigate(to: $0, from: \.showSeason) },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showMissions) {
            MissionsScreen(
                onBack: { showMissions = false },
                onSelectTab: { navigate(to: $0, from: \.showMissions) },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showProfile) {
            RankScreen(
                onBack: { showProfile = false },
                onSelectTab: { navigate(to: $0, from: \.showProfile) },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showProfileScreen) {
            ProfileScreen(
                onBack: { showProfileScreen = false },
                onSelectTab: { navigate(to: $0, from: \.showProfileScreen) },
                onSettings: { showSettings = true }
            )
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(onClose: { showSettings = false })
        }
        .sheet(isPresented: $showNotifications) {
            noticeSheet(
                title: "NOTIFICATIONS",
                icon: "bell.fill",
                rows: [
                    ("gift.fill", "Récompense quotidienne", "Ton bonus de connexion t'attend !"),
                    ("flame.fill", "Défi hebdo", "Peins 5 000 m² avant dimanche."),
                    ("sparkles", "Saison 1", "Nouveau palier débloqué : palier \(mockSeasonTier).")
                ]
            )
        }
        .sheet(isPresented: $showMail) {
            noticeSheet(
                title: "MESSAGES",
                icon: "envelope.fill",
                rows: [
                    ("megaphone.fill", "Équipe Splash", "Bienvenue dans la Saison 1 — No rules, just splash !"),
                    ("wrench.and.screwdriver.fill", "Notes de mise à jour", "Refonte réseau : matchs plus fluides en duel local.")
                ]
            )
        }
        .sheet(isPresented: $showOdds) { OddsView() }
    }

    // MARK: - Navigation croisée (barre basse des 5 écrans)

    /// Ferme l'écran courant puis ouvre la destination choisie dans la barre
    /// de navigation basse (ou revient simplement à l'accueil).
    private func navigate(to tab: MenuTab, from current: ReferenceWritableKeyPath<SplashHomeView, Bool>) {
        self[keyPath: current] = false
        guard tab != .home else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            switch tab {
            case .home: break
            case .play: showPlay = true
            case .armory: showArmory = true
            case .shop: showShop = true
            case .missions: showMissions = true
            case .rank: showProfile = true
            }
        }
    }

    // MARK: - Fond

    private func background(size: CGSize) -> some View {
        ZStack {
            if UIImage(named: "shipping_container_arena") != nil {
                Image("shipping_container_arena")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .frame(width: size.width, height: size.height)
            } else {
                MenuBackground()
                    .frame(width: size.width, height: size.height)
            }

            // Voile sombre à gauche pour asseoir le menu
            LinearGradient(
                colors: [.black.opacity(0.72), .black.opacity(0.35), .clear, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [.black.opacity(0.35), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 90)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Barre du haut

    private func topBar(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            playerHeader(scale: scale)

            Spacer(minLength: 6)

            currencyPill(icon: "paintpalette.fill", tint: Color(hex: "FF2E8A"), value: mockPigments, scale: scale, onPlus: nil)
            currencyPill(icon: "diamond.fill", tint: Color(hex: "2EE6D6"), value: mockPrisms, scale: scale) {
                showShop = true
            }

            circleButton(icon: "bell.fill", badge: true, scale: scale) { showNotifications = true }
            circleButton(icon: "envelope.fill", badge: false, scale: scale) { showMail = true }
            circleButton(icon: "gearshape.fill", badge: false, scale: scale) { showSettings = true }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -18)
    }

    private func playerHeader(scale: CGFloat) -> some View {
        Button {
            showProfileScreen = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8 * scale) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle().fill(panelBlack)
                        Circle().stroke(splashYellow, lineWidth: 2)
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 13 * scale, weight: .black))
                            .foregroundStyle(splashYellow)
                    }
                    .frame(width: 32 * scale, height: 32 * scale)

                    Text("\(mockLevel)")
                        .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(splashYellow))
                        .offset(x: 5, y: -3)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(mockName)
                        .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule()
                                .fill(splashYellow)
                                .frame(width: 76 * scale * CGFloat(mockXP) / CGFloat(mockXPMax))
                        }
                        .frame(width: 76 * scale, height: 5)

                        Text("\(mockXP) / \(mockXPMax)")
                            .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.5)))
        }
        .buttonStyle(PressableStyle())
    }

    private func currencyPill(
        icon: String,
        tint: Color,
        value: Int,
        scale: CGFloat,
        onPlus: (() -> Void)?
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11 * scale, weight: .bold))
                .foregroundStyle(tint)
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            if let onPlus {
                Button {
                    onPlus()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 13 * scale, weight: .bold))
                        .foregroundStyle(tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private func circleButton(icon: String, badge: Bool, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 29 * scale, height: 29 * scale)
                    .background(Circle().fill(.black.opacity(0.55)))
                    .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                if badge {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 1, y: -1)
                }
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Colonne de gauche

    private func leftColumn(height: CGFloat, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            logo(scale: scale)
                .frame(height: 46 * scale)
                .padding(.top, 2)

            playMenuButton(scale: scale)
                .frame(height: 44 * scale)

            menuButton(
                icon: "scope", title: "ÉQUIPEMENT", subtitle: "Armes, gadgets, skins",
                badge: false, index: 1, scale: scale
            ) { showArmory = true }
            menuButton(
                icon: "bag.fill", title: "BOUTIQUE", subtitle: "Skins, coffres et plus",
                badge: false, index: 2, scale: scale
            ) { showShop = true }
            menuButton(
                icon: "target", title: "MISSIONS", subtitle: "Défis et récompenses",
                badge: true, index: 3, scale: scale
            ) { showMissions = true }
            menuButton(
                icon: "chart.bar.fill", title: "CLASSEMENT", subtitle: "Voir ton classement",
                badge: false, index: 4, scale: scale
            ) { showProfile = true }

            Spacer(minLength: 2)

            seasonCard(scale: scale)
                .frame(height: 34 * scale)
        }
    }

    private func logo(scale: CGFloat) -> some View {
        Group {
            if UIImage(named: "splash_graffiti_logo") != nil {
                Image("splash_graffiti_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("SPLASH")
                    .font(.system(size: 34 * scale, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 5, y: 2)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(splashYellow)
                            .frame(width: 9, height: 9)
                            .offset(x: 6, y: -4)
                    }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
    }

    private func playMenuButton(scale: CGFloat) -> some View {
        Button {
            showPlay = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18 * scale, weight: .black))
                    .foregroundStyle(.black)

                VStack(alignment: .leading, spacing: 1) {
                    Text("JOUER")
                        .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                    Text("Rejoindre une partie")
                        .font(.system(size: 8.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                PaintedPanel(skew: 5)
                    .fill(splashYellow)
                    .shadow(color: splashYellow.opacity(playPulse ? 0.55 : 0.25), radius: playPulse ? 12 : 6, y: 3)
            )
            .overlay(
                PaintedPanel(skew: 5)
                    .stroke(.white.opacity(0.85), lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle())
        .scaleEffect(playPulse ? 1.015 : 1)
        .staggered(appeared, index: 0)
    }

    private func menuButton(
        icon: String,
        title: String,
        subtitle: String,
        badge: Bool,
        index: Int,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: icon)
                    .font(.system(size: 13 * scale, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 20 * scale)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)

                if badge {
                    Circle()
                        .fill(Color(hex: "FF6A00"))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5 * scale)
            .frame(maxWidth: .infinity)
            .background(PaintedPanel(skew: 4).fill(panelBlack.opacity(0.88)))
            .overlay(PaintedPanel(skew: 4).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .staggered(appeared, index: index)
    }

    private func seasonCard(scale: CGFloat) -> some View {
        Button {
            showSeason = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 8 * scale) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 13 * scale, weight: .black))
                    .foregroundStyle(Color(hex: "2EE6D6"))

                VStack(alignment: .leading, spacing: 1) {
                    Text("SAISON 1")
                        .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Fin dans : \(mockSeasonEnd)")
                        .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(Color(hex: "FF6A00"))
                        .frame(width: 56 * scale * mockSeasonProgress)
                }
                .frame(width: 56 * scale, height: 5)

                Text("\(mockSeasonTier)")
                    .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(4)
                    .background(Circle().fill(splashYellow))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PaintedPanel(skew: 3).fill(panelBlack.opacity(0.88)))
            .overlay(PaintedPanel(skew: 3).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .staggered(appeared, index: 5)
    }

    // MARK: - Barre sociale

    private func socialBar(scale: CGFloat) -> some View {
        HStack(spacing: 12 * scale) {
            Text("SUIVEZ-NOUS")
                .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.trailing, 2)
                .lineLimit(1)

            socialIcon(symbol: "bubble.left.and.bubble.right.fill", scale: scale)
            socialText("𝕏", scale: scale)
            socialIcon(symbol: "camera.fill", scale: scale)
            socialIcon(symbol: "music.note", scale: scale)
            socialIcon(symbol: "play.rectangle.fill", scale: scale)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7 * scale)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private func socialIcon(symbol: String, scale: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22 * scale, height: 22 * scale)
        }
        .buttonStyle(PressableStyle())
    }

    private func socialText(_ glyph: String, scale: CGFloat) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(glyph)
                .font(.system(size: 14 * scale, weight: .black))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22 * scale, height: 22 * scale)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Feuilles factices (notifications / messages)

    private func noticeSheet(
        title: String,
        icon: String,
        rows: [(String, String, String)]
    ) -> some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.1).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                ForEach(rows, id: \.1) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.0)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(splashYellow)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(.white.opacity(0.08)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.1)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text(row.2)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Entrée décalée des boutons

private struct StaggeredEntrance: ViewModifier {
    let shown: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : -46)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06),
                value: shown
            )
    }
}

private extension View {
    func staggered(_ shown: Bool, index: Int) -> some View {
        modifier(StaggeredEntrance(shown: shown, index: index))
    }
}

#Preview {
    SplashHomeView(onPlay: {}, onTraining: {}, onCustomMatch: { _ in })
}
