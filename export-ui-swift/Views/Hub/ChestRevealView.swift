import SwiftUI

/// Écran de reveal d'un coffre : le coffre tremble, s'ouvre dans un flash
/// de particules, puis les récompenses se révèlent une par une avec leur
/// couleur de rareté. Déclenché depuis l'Accueil ou la fin de partie.
struct ChestRevealView: View {
    let payload: ChestRevealPayload
    let onDone: () -> Void

    @State private var phase: Int = 0
    @State private var shake = false
    @State private var burst = false
    @State private var revealedCount = 0

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.14).ignoresSafeArea()

            // Halo de rareté derrière le coffre.
            Circle()
                .fill(payload.chest.tint.opacity(burst ? 0.45 : 0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .scaleEffect(burst ? 1.3 : 0.9)
                .animation(.easeOut(duration: 0.5), value: burst)

            // Particules d'ouverture.
            if burst {
                ForEach(0..<14, id: \.self) { index in
                    Circle()
                        .fill(index % 2 == 0 ? payload.chest.tint : Team.orange.color)
                        .frame(width: CGFloat.random(in: 6...14))
                        .offset(
                            x: cos(Double(index) / 14 * 2 * .pi) * 130,
                            y: sin(Double(index) / 14 * 2 * .pi) * 130
                        )
                        .opacity(0.7)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            VStack(spacing: 22) {
                if phase == 0 {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 90, weight: .bold))
                        .foregroundStyle(payload.chest.tint)
                        .rotationEffect(.degrees(shake ? 4 : -4))
                        .animation(.easeInOut(duration: 0.09).repeatForever(autoreverses: true), value: shake)
                    Text(payload.chest.displayName.uppercased())
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Ouverture…")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    Text("VOUS AVEZ OBTENU")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))

                    VStack(spacing: 12) {
                        ForEach(Array(payload.rewards.enumerated()), id: \.element.id) { index, reward in
                            rewardCard(reward)
                                .opacity(revealedCount > index ? 1 : 0)
                                .scaleEffect(revealedCount > index ? 1 : 0.6)
                                .animation(
                                    .spring(response: 0.45, dampingFraction: 0.65),
                                    value: revealedCount
                                )
                        }
                    }

                    if revealedCount >= payload.rewards.count {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDone()
                        } label: {
                            Text("CONTINUER")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 46)
                                .padding(.vertical, 13)
                                .background(
                                    Capsule()
                                        .fill(Team.orange.color)
                                        .shadow(color: Team.orange.color.opacity(0.5), radius: 12, y: 4)
                                )
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, 30)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: phase)
        .onAppear(perform: playSequence)
    }

    private func playSequence() {
        shake = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            burst = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioService.shared.playSplat(volume: 0.8)
            try? await Task.sleep(for: .milliseconds(250))
            phase = 1
            for index in 1...payload.rewards.count {
                try? await Task.sleep(for: .milliseconds(450))
                revealedCount = index
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func rewardCard(_ reward: ChestReward) -> some View {
        HStack(spacing: 14) {
            Image(systemName: reward.iconSystemName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(reward.rarity.color)
                .frame(width: 52, height: 52)
                .background(Circle().fill(reward.rarity.color.opacity(0.15)))
                .overlay(Circle().stroke(reward.rarity.color.opacity(0.6), lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(reward.displayName)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(reward.rarity.displayName) · \(reward.subtitle)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(reward.rarity.color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(reward.rarity.color.opacity(0.45), lineWidth: 1.5)
        )
    }
}

#Preview {
    ChestRevealView(
        payload: ChestRevealPayload(
            chest: .gold,
            rewards: [
                ChestReward(kind: .pigments(120), rarity: .common),
                ChestReward(kind: .prisms(30), rarity: .epic),
            ]
        ),
        onDone: {}
    )
}
