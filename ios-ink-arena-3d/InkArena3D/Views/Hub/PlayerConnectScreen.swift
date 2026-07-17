import SwiftUI

/// Écran de transition "CONNEXION DES JOUEURS…" affiché entre le lobby et le
/// lancement du match : icône centrale, lore, indicateur rotatif, et 4
/// cartes joueurs factices qui passent de "En attente…" à "Prêt" avec une
/// animation en cascade, avant d'appeler `onDone`.
struct PlayerConnectScreen: View {
    let onDone: () -> Void

    private struct MockPlayer: Identifiable {
        let id = UUID()
        let name: String
        let team: Team
        let icon: String
        let isYou: Bool
    }

    @State private var players: [MockPlayer] = [
        MockPlayer(name: ProfileStore.shared.playerName, team: .orange, icon: "person.fill", isYou: true),
        MockPlayer(name: "Splatty-Bot", team: .orange, icon: "cpu.fill", isYou: false),
        MockPlayer(name: "Violette-Bot", team: .purple, icon: "cpu.fill", isYou: false),
        MockPlayer(name: "Kraken-Bot", team: .purple, icon: "cpu.fill", isYou: false),
    ]
    @State private var readyFlags: [Bool] = [false, false, false, false]
    @State private var spin = false
    @State private var pulse = false
    @State private var appeared = false

    private let tip = "Astuce : une bombe à peinture bien placée peut retourner un combat perdu — garde-la pour les moments critiques."

    var body: some View {
        ZStack {
            MenuScreenBackdrop(size: UIScreen.main.bounds.size)

            GeometryReader { geo in
                let scale = menuScaleFactor(for: geo.size.height)
                VStack(spacing: 12 * scale) {
                    Spacer(minLength: 4)

                    icon(scale: scale)

                    VStack(spacing: 3 * scale) {
                        Text("CONNEXION DES JOUEURS…")
                            .font(.system(size: 17 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("Chroma City synchronise les Inklings avant le coup d'envoi.")
                            .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 8) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Color.menuAccent)
                                .frame(width: 6 * scale, height: 6 * scale)
                                .opacity(spin ? 1 : 0.3)
                                .animation(
                                    .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                                    value: spin
                                )
                        }
                    }
                    .padding(.top, -4 * scale)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 9 * scale), GridItem(.flexible(), spacing: 9 * scale)], spacing: 9 * scale) {
                        ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                            playerCard(player, ready: readyFlags[index], scale: scale)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08), value: appeared)
                        }
                    }
                    .frame(maxWidth: 440 * scale)

                    Spacer(minLength: 4)

                    tipBanner(scale: scale)
                }
                .padding(.horizontal, menuBaseMargin)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaPadding(.vertical, 8)
        }
        .onAppear {
            appeared = true
            spin = true
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            scheduleReadySequence()
        }
    }

    /// Marks players ready one by one with a short staggered delay, then
    /// waits a beat before handing off to the caller.
    private func scheduleReadySequence() {
        for index in readyFlags.indices {
            let delay = 0.5 + Double(index) * 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    readyFlags[index] = true
                }
                if index == readyFlags.count - 1 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
        }
        let total = 0.5 + Double(readyFlags.count - 1) * 0.35 + 0.9
        DispatchQueue.main.asyncAfter(deadline: .now() + total) {
            onDone()
        }
    }

    private func icon(scale: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.menuAccent.opacity(0.18))
                .frame(width: 78 * scale, height: 78 * scale)
                .scaleEffect(pulse ? 1.12 : 1)
            Circle()
                .stroke(Color.menuAccent.opacity(0.6), lineWidth: 2)
                .frame(width: 63 * scale, height: 63 * scale)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 25 * scale, weight: .black))
                .foregroundStyle(.menuAccent)
        }
    }

    private func playerCard(_ player: MockPlayer, ready: Bool, scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ZStack {
                Circle().fill(player.team.color.opacity(0.85))
                Image(systemName: player.icon)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30 * scale, height: 30 * scale)
            .overlay(
                Circle().stroke(ready ? Color(hex: "35C46A").opacity(0.7) : .white.opacity(0.15), lineWidth: 1.5)
            )

            HStack(spacing: 4) {
                Text(player.name)
                    .font(.system(size: 11.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if player.isYou {
                    Text("TOI")
                        .font(.system(size: 7 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.menuAccent))
                }
            }

            Text(player.team == .orange ? "Équipe Orange" : "Équipe Violette")
                .font(.system(size: 8.5 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            HStack(spacing: 4) {
                if ready {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10.5 * scale, weight: .bold))
                }
                Text(ready ? "Prêt" : "En attente…")
                    .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ready ? Color(hex: "35C46A") : .white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8 * scale)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ready ? Color(hex: "35C46A").opacity(0.6) : .white.opacity(0.1), lineWidth: 1.5)
        )
    }

    private func tipBanner(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12 * scale, weight: .bold))
                .foregroundStyle(.menuAccent)
            Text(tip)
                .font(.system(size: 9.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8 * scale)
        .background(Capsule().fill(.black.opacity(0.5)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .frame(maxWidth: 420)
    }
}

#Preview {
    PlayerConnectScreen(onDone: {})
}
