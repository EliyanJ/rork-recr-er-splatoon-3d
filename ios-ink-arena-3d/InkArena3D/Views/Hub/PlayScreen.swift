import SwiftUI

/// Écran "JOUER" — choix du mode de match (Match contre l'IA, Entraînement
/// et Partie personnalisée actifs, Mode événement à venir) puis les défis
/// quotidiens en cours. Données factices ; Match contre l'IA lance le même
/// flux que le bouton JOUER de l'accueil (lobby → IA), Entraînement ouvre la
/// salle de tir sandbox, et Partie personnalisée ouvre le choix de sous-mode
/// (Duel local / Partie classique / Match par équipes) avant la connexion
/// locale entre appareils.
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
        let locked: Bool
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

    private let modes: [Mode] = [
        Mode(icon: "bolt.fill", title: "MATCH CONTRE L'IA", subtitle: "Duel 1v1 contre l'IA — lance-toi tout de suite", tint: .menuAccent, kind: .quickMatch, locked: false),
        Mode(icon: "figure.run", title: "ENTRAÎNEMENT", subtitle: "Mannequins, cibles mobiles, change d'arme librement", tint: Color(hex: "2EE6D6"), kind: .training, locked: false),
        Mode(icon: "person.3.fill", title: "PARTIE PERSONNALISÉE", subtitle: "Duel local, règles et équipes sur-mesure entre amis", tint: Color(hex: "9A3DF5"), kind: .custom, locked: false),
        Mode(icon: "trophy.fill", title: "MODE ÉVÉNEMENT", subtitle: "Défi limité dans le temps, récompenses exclusives", tint: Color(hex: "FF6A00"), kind: .event, locked: true),
    ]

    private let dailyChallenges: [DailyChallenge] = [
        DailyChallenge(icon: "paintpalette.fill", title: "Peins 3 000 m² d'encre", progress: 0.7, current: 2100, goal: 3000, reward: "+150 🎨"),
        DailyChallenge(icon: "target", title: "Élimine 8 rivaux", progress: 0.375, current: 3, goal: 8, reward: "+80 🎨"),
        DailyChallenge(icon: "flag.checkered", title: "Termine 2 matchs", progress: 0.5, current: 1, goal: 2, reward: "+40 💎"),
    ]

    var body: some View {
        MenuScreenScaffold(
            title: "JOUER",
            activeTab: .play,
            pigments: pigments,
            prisms: prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12 * scale) {
                    VStack(spacing: 9 * scale) {
                        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                            modeCard(mode, scale: scale, index: index)
                        }
                    }

                    Text("DÉFIS QUOTIDIENS")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.top, 4)

                    VStack(spacing: 8 * scale) {
                        ForEach(dailyChallenges) { challenge in
                            challengeRow(challenge, scale: scale)
                        }
                    }
                }
                .padding(.bottom, 4)
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

    private func modeCard(_ mode: Mode, scale: CGFloat, index: Int) -> some View {
        Button {
            guard !mode.locked else { return }
            switch mode.kind {
            case .quickMatch: onPlay()
            case .training: onTraining()
            case .custom: showCustomModes = true
            case .event: break
            }
            UIImpactFeedbackGenerator(style: index == 0 ? .medium : .light).impactOccurred()
        } label: {
            HStack(spacing: 12 * scale) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20 * scale, weight: .black))
                    .foregroundStyle(mode.locked ? .white.opacity(0.35) : mode.tint)
                    .frame(width: 40 * scale)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(mode.locked ? .white.opacity(0.4) : .white)
                        if mode.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9 * scale, weight: .black))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Text(mode.locked ? "Bientôt disponible" : mode.subtitle)
                        .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if !mode.locked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity)
            .background(PaintedPanel(skew: index.isMultiple(of: 2) ? 4 : -4).fill(Color.menuPanel.opacity(mode.locked ? 0.55 : 0.88)))
            .overlay(PaintedPanel(skew: index.isMultiple(of: 2) ? 4 : -4).stroke(mode.locked ? .white.opacity(0.08) : mode.tint.opacity(0.5), lineWidth: 1.5))
            .opacity(mode.locked ? 0.75 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(mode.locked)
    }

    private func challengeRow(_ challenge: DailyChallenge, scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: challenge.icon)
                .font(.system(size: 13 * scale, weight: .bold))
                .foregroundStyle(.menuAccent)
                .frame(width: 26 * scale, height: 26 * scale)
                .background(Circle().fill(.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(challenge.title)
                        .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(challenge.reward)
                        .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.menuAccent)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color(hex: "35C46A"))
                            .frame(width: proxy.size.width * challenge.progress)
                    }
                }
                .frame(height: 6 * scale)
                Text("\(challenge.current) / \(challenge.goal)")
                    .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9 * scale)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))
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
        let locked: Bool
    }

    private let options: [Option] = [
        Option(icon: "person.2.fill", title: "Duel local", subtitle: "Deux iPhones proches, Wi-Fi/Bluetooth — 1 contre 1", locked: false),
        Option(icon: "slider.horizontal.3", title: "Partie classique", subtitle: "Règles libres, même connexion locale entre appareils", locked: false),
        Option(icon: "person.3.fill", title: "Match par équipes personnalisé", subtitle: "Équipes sur-mesure entre amis, connexion locale", locked: false),
        Option(icon: "trophy.fill", title: "Classée", subtitle: "Bientôt disponible", locked: true),
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

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10 * scale) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                optionCard(option, scale: scale, index: index)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    Spacer(minLength: 0)
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

    private func optionCard(_ option: Option, scale: CGFloat, index: Int) -> some View {
        Button {
            guard !option.locked else {
                showLockedNotice = true
                return
            }
            onSelect(option.title)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            HStack(spacing: 12 * scale) {
                Image(systemName: option.icon)
                    .font(.system(size: 20 * scale, weight: .black))
                    .foregroundStyle(option.locked ? .white.opacity(0.35) : Color(hex: "9A3DF5"))
                    .frame(width: 40 * scale)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(option.title.uppercased())
                            .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(option.locked ? .white.opacity(0.4) : .white)
                        if option.locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9 * scale, weight: .black))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    Text(option.subtitle)
                        .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                if !option.locked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12 * scale)
            .frame(maxWidth: .infinity)
            .background(PaintedPanel(skew: index.isMultiple(of: 2) ? 4 : -4).fill(Color.menuPanel.opacity(option.locked ? 0.55 : 0.88)))
            .overlay(PaintedPanel(skew: index.isMultiple(of: 2) ? 4 : -4).stroke(option.locked ? .white.opacity(0.08) : Color(hex: "9A3DF5").opacity(0.5), lineWidth: 1.5))
            .opacity(option.locked ? 0.75 : 1)
        }
        .buttonStyle(PressableStyle())
        .disabled(option.locked)
    }
}

#Preview {
    PlayScreen(
        pigments: 9470, prisms: 355, onBack: {}, onSelectTab: { _ in }, onSettings: {},
        onPlay: {}, onTraining: {}, onCustomMatch: { _ in }
    )
}
