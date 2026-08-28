import SwiftUI

/// Écran "JOUER" — mosaïque de modes façon borne d'arcade : grandes tuiles
/// illustrées pour les modes jouables, tuiles grisées avec palier de niveau
/// pour ceux à venir, et bandeau compact des défis quotidiens en bas.
/// Match contre l'IA lance le même flux que le bouton JOUER de l'accueil,
/// Entraînement ouvre la salle de tir, Partie personnalisée ouvre le choix
/// de sous-mode avant la connexion locale entre appareils.
struct PlayScreen: View {
    let pigments: Int
    let prisms: Int
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void
    let onPlay: () -> Void
    let onTraining: () -> Void
    let onCustomMatch: (String) -> Void

    private enum ModeKind {
        case quickMatch, training, custom, event
    }

    private struct Mode: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color
        let kind: ModeKind
        let unlockLevel: Int
    }

    private struct DailyChallenge: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let progress: Double
        let current: Int
        let goal: Int
        let reward: String
    }

    @State private var showCustomModes = false
    @State private var meta = MetaStore.shared
    @State private var appeared = false

    private let quickMatch = Mode(
        icon: "bolt.fill", title: "MATCH CONTRE L'IA",
        subtitle: "Duel 1v1 — lance-toi tout de suite",
        tint: Color(hex: "FF7A1A"), kind: .quickMatch, unlockLevel: 0
    )
    private let training = Mode(
        icon: "figure.run", title: "ENTRAÎNEMENT",
        subtitle: "Mannequins et cibles mobiles",
        tint: Color(hex: "2EE6D6"), kind: .training, unlockLevel: 0
    )
    private let custom = Mode(
        icon: "person.3.fill", title: "PARTIE PERSONNALISÉE",
        subtitle: "Duel local entre amis",
        tint: Color(hex: "9A3DF5"), kind: .custom, unlockLevel: 0
    )
    private let event = Mode(
        icon: "trophy.fill", title: "MODE ÉVÉNEMENT",
        subtitle: "Défi limité, récompenses exclusives",
        tint: Color(hex: "F5C518"), kind: .event, unlockLevel: 8
    )

    private let dailyChallenges: [DailyChallenge] = [
        DailyChallenge(icon: "paintpalette.fill", title: "Peindre 3 000 m²", progress: 0.7, current: 2100, goal: 3000, reward: "+150"),
        DailyChallenge(icon: "target", title: "Éliminer 8 rivaux", progress: 0.375, current: 3, goal: 8, reward: "+80"),
        DailyChallenge(icon: "flag.checkered", title: "Finir 2 matchs", progress: 0.5, current: 1, goal: 2, reward: "+40"),
    ]

    var body: some View {
        MenuScreenScaffold(
            title: "MODES DE JEU",
            activeTab: .play,
            pigments: pigments,
            prisms: prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            VStack(spacing: 8 * scale) {
                // Mosaïque de modes.
                HStack(spacing: 8 * scale) {
                    modeTile(quickMatch, scale: scale, isHero: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 8 * scale) {
                        modeTile(training, scale: scale, isHero: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        modeTile(custom, scale: scale, isHero: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 8 * scale) {
                        modeTile(event, scale: scale, isHero: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        lockedPlaceholder(title: "CLASSÉE", level: 12, scale: scale)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)

                // Défis quotidiens compacts.
                HStack(spacing: 7 * scale) {
                    ForEach(dailyChallenges) { challenge in
                        challengePill(challenge, scale: scale)
                    }
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { appeared = true }
            }
        }
        .fullScreenCover(isPresented: $showCustomModes) {
            CustomModeScreen(
                onBack: { showCustomModes = false },
                onSelect: { title in
                    showCustomModes = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCustomMatch(title) }
                }
            )
        }
    }

    // MARK: - Tuile de mode

    private func modeTile(_ mode: Mode, scale: CGFloat, isHero: Bool) -> some View {
        let locked = meta.accountLevel < mode.unlockLevel
        return Button {
            guard !locked else { return }
            switch mode.kind {
            case .quickMatch: onPlay()
            case .training: onTraining()
            case .custom: showCustomModes = true
            case .event: break
            }
            UIImpactFeedbackGenerator(style: isHero ? .medium : .light).impactOccurred()
        } label: {
            ZStack {
                ArcadeTileBackground(tint: mode.tint, isLocked: locked)

                // Éclaboussure d'encre décorative en fond de tuile.
                Image(systemName: mode.icon)
                    .font(.system(size: (isHero ? 92 : 54) * scale, weight: .black))
                    .foregroundStyle(mode.tint.opacity(locked ? 0.05 : 0.16))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 14 * scale, y: 10 * scale)
                    .clipped()

                VStack(alignment: .leading, spacing: 3 * scale) {
                    Image(systemName: mode.icon)
                        .font(.system(size: (isHero ? 26 : 18) * scale, weight: .black))
                        .foregroundStyle(locked ? .white.opacity(0.3) : mode.tint)
                        .shadow(color: locked ? .clear : mode.tint.opacity(0.7), radius: 8)

                    Spacer(minLength: 0)

                    Text(mode.title)
                        .font(.system(size: (isHero ? 15 : 11) * scale, weight: .black, design: .rounded))
                        .foregroundStyle(locked ? .white.opacity(0.45) : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.leading)

                    Text(locked ? "Bientôt disponible" : mode.subtitle)
                        .font(.system(size: (isHero ? 10 : 8.5) * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)

                    if !locked {
                        HStack(spacing: 4) {
                            Text("JOUER")
                                .font(.system(size: (isHero ? 10 : 8.5) * scale, weight: .black, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: (isHero ? 9 : 7.5) * scale, weight: .black))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(Capsule().fill(Color.menuAccent))
                        .padding(.top, 2 * scale)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(10 * scale)

                if locked {
                    ArcadeLockOverlay(requirement: "Niv.\(mode.unlockLevel)", scale: scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(PressableStyle())
        .disabled(locked)
    }

    /// Tuile "à venir" purement décorative, pour densifier la mosaïque.
    private func lockedPlaceholder(title: String, level: Int, scale: CGFloat) -> some View {
        ZStack {
            ArcadeTileBackground(tint: .gray, isLocked: true)
            VStack(spacing: 4 * scale) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(10 * scale)
            ArcadeLockOverlay(requirement: "Niv.\(level)", scale: scale)
        }
        .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Défi quotidien compact

    private func challengePill(_ challenge: DailyChallenge, scale: CGFloat) -> some View {
        HStack(spacing: 7 * scale) {
            Image(systemName: challenge.icon)
                .font(.system(size: 11 * scale, weight: .black))
                .foregroundStyle(.menuAccent)
                .frame(width: 22 * scale, height: 22 * scale)
                .background(Circle().fill(.white.opacity(0.1)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 2)
                    Text(challenge.reward)
                        .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.menuAccent)
                        .lineLimit(1)
                }
                ArcadeStatBar(value: challenge.progress, tint: ArcadeKit.cash, scale: scale)
                Text("\(challenge.current) / \(challenge.goal)")
                    .font(.system(size: 7.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 7 * scale)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 11).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Sub-mode picker for "PARTIE PERSONNALISÉE" — Duel local (the existing
/// device-to-device pairing), plus Partie classique / Match par équipes
/// personnalisé, which reuse the exact same local connection flow under a
/// different label. Classée stays locked, tied to future online multiplayer.
private struct CustomModeScreen: View {
    let onBack: () -> Void
    let onSelect: (String) -> Void

    private struct Option: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color
        let locked: Bool
    }

    private let options: [Option] = [
        Option(icon: "person.2.fill", title: "Duel local", subtitle: "Deux iPhones proches — 1 contre 1", tint: Color(hex: "2EE6D6"), locked: false),
        Option(icon: "slider.horizontal.3", title: "Partie classique", subtitle: "Règles libres, connexion locale", tint: Color(hex: "FF7A1A"), locked: false),
        Option(icon: "person.3.fill", title: "Match par équipes", subtitle: "Équipes sur-mesure entre amis", tint: Color(hex: "9A3DF5"), locked: false),
        Option(icon: "trophy.fill", title: "Classée", subtitle: "Bientôt disponible", tint: Color(hex: "F5C518"), locked: true),
    ]

    @State private var showLockedNotice = false
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
                        title: "PARTIE PERSONNALISÉE",
                        scale: scale,
                        onBack: onBack,
                        pigments: meta.pigments,
                        prisms: meta.prisms
                    )

                    HStack(spacing: 8 * scale) {
                        ForEach(options) { option in
                            optionTile(option, scale: scale)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    ArcadeInfoBar(
                        text: "Les parties personnalisées se jouent entre appareils proches, en Wi-Fi ou Bluetooth.",
                        scale: scale
                    )
                }
                .padding(menuBaseMargin)
            }
        }
        .alert("Bientôt disponible", isPresented: $showLockedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Le mode Classé arrivera avec le multijoueur en ligne. En attendant, essaie un Duel local, une Partie classique ou un Match par équipes personnalisé.")
        }
    }

    private func optionTile(_ option: Option, scale: CGFloat) -> some View {
        Button {
            guard !option.locked else {
                showLockedNotice = true
                return
            }
            onSelect(option.title)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            ZStack {
                ArcadeTileBackground(tint: option.tint, isLocked: option.locked)

                Image(systemName: option.icon)
                    .font(.system(size: 58 * scale, weight: .black))
                    .foregroundStyle(option.tint.opacity(option.locked ? 0.05 : 0.15))
                    .rotationEffect(.degrees(-12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 12 * scale, y: 8 * scale)
                    .clipped()

                VStack(alignment: .leading, spacing: 4 * scale) {
                    Image(systemName: option.icon)
                        .font(.system(size: 20 * scale, weight: .black))
                        .foregroundStyle(option.locked ? .white.opacity(0.3) : option.tint)
                        .shadow(color: option.locked ? .clear : option.tint.opacity(0.7), radius: 8)
                    Spacer(minLength: 0)
                    Text(option.title.uppercased())
                        .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(option.locked ? .white.opacity(0.45) : .white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.leading)
                    Text(option.subtitle)
                        .font(.system(size: 8.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(10 * scale)

                if option.locked {
                    ArcadeLockOverlay(requirement: "En ligne", scale: scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        }
        .buttonStyle(PressableStyle())
    }
}

#Preview {
    PlayScreen(
        pigments: 9470, prisms: 355, onBack: {}, onSelectTab: { _ in }, onSettings: {},
        onPlay: {}, onTraining: {}, onCustomMatch: { _ in }
    )
}
