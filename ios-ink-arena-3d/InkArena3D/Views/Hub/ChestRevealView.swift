import SwiftUI

/// Écran d'ouverture de coffre — montée de tension (le coffre tremble de
/// plus en plus fort, le halo de rareté s'intensifie), explosion de peinture,
/// puis révélation des récompenses une par une sous forme de cartes à cadre
/// de rareté. Mise en page paysage : les cartes se placent côte à côte.
struct ChestRevealView: View {
    let payload: ChestRevealPayload
    let onDone: () -> Void

    @State private var phase: Int = 0
    @State private var shakeAmount: Double = 0
    @State private var burst = false
    @State private var revealedCount = 0
    @State private var haloPulse = false

    /// Rareté la plus élevée du lot — pilote la couleur de l'ambiance.
    private var topRarity: Rarity {
        payload.rewards.map(\.rarity).max() ?? .common
    }

    var body: some View {
        GeometryReader { geo in
            let scale = menuScaleFactor(for: geo.size.height)
            ZStack {
                background(scale: scale)

                if phase == 0 {
                    sealedChest(scale: scale)
                } else {
                    rewardsReveal(scale: scale)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: phase)
        .onAppear(perform: playSequence)
    }

    // MARK: - Fond et halo

    private func background(scale: CGFloat) -> some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.09).ignoresSafeArea()

            // Halo de rareté qui respire puis explose.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [payload.chest.tint.opacity(burst ? 0.55 : 0.28), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 220 * scale
                    )
                )
                .frame(width: 420 * scale, height: 420 * scale)
                .scaleEffect(burst ? 1.35 : (haloPulse ? 1.06 : 0.92))
                .animation(.easeOut(duration: 0.55), value: burst)
                .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: haloPulse)

            // Rayons de lumière derrière les récompenses.
            if phase == 1 {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [topRarity.color.opacity(0.22), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 16 * scale, height: 300 * scale)
                        .offset(y: -60 * scale)
                        .rotationEffect(.degrees(Double(index) / 12 * 360))
                }
                .transition(.opacity)
            }

            // Éclaboussures de peinture projetées à l'ouverture.
            if burst {
                ForEach(0..<18, id: \.self) { index in
                    let angle = Double(index) / 18 * 2 * .pi
                    let distance = (110.0 + Double(index % 4) * 34) * Double(scale)
                    Circle()
                        .fill(index % 3 == 0 ? payload.chest.tint : (index % 3 == 1 ? Team.orange.color : topRarity.color))
                        .frame(width: CGFloat.random(in: 7...17) * scale)
                        .offset(x: cos(angle) * distance, y: sin(angle) * distance)
                        .opacity(phase == 1 ? 0.35 : 0.8)
                        .blur(radius: phase == 1 ? 2 : 0)
                        .transition(.scale.combined(with: .opacity))
                }
                .animation(.easeOut(duration: 0.7), value: phase)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Phase 1 : le coffre scellé

    private func sealedChest(scale: CGFloat) -> some View {
        VStack(spacing: 14 * scale) {
            ZStack {
                // Socle lumineux.
                Ellipse()
                    .fill(payload.chest.tint.opacity(0.3))
                    .frame(width: 150 * scale, height: 26 * scale)
                    .blur(radius: 14)
                    .offset(y: 58 * scale)

                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 92 * scale, weight: .black))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [payload.chest.tint, payload.chest.tint.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: payload.chest.tint.opacity(0.7), radius: 22)
                    .rotationEffect(.degrees(shakeAmount))
                    .scaleEffect(burst ? 1.25 : 1)
                    .opacity(burst ? 0 : 1)
                    .animation(.easeOut(duration: 0.28), value: burst)
            }
            .frame(height: 130 * scale)

            Text(payload.chest.displayName.uppercased())
                .font(.system(size: 19 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: payload.chest.tint.opacity(0.8), radius: 10)

            Text("Ouverture…")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Phase 2 : les récompenses

    private func rewardsReveal(scale: CGFloat) -> some View {
        VStack(spacing: 14 * scale) {
            Text("TU AS OBTENU")
                .font(.system(size: 14 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .tracking(2)

            HStack(spacing: 10 * scale) {
                ForEach(Array(payload.rewards.enumerated()), id: \.element.id) { index, reward in
                    rewardCard(reward, scale: scale)
                        .opacity(revealedCount > index ? 1 : 0)
                        .scaleEffect(revealedCount > index ? 1 : 0.55)
                        .rotation3DEffect(
                            .degrees(revealedCount > index ? 0 : 70),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.62),
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
                        .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 44 * scale)
                        .padding(.vertical, 11 * scale)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [ArcadeKit.cash, ArcadeKit.cash.opacity(0.68)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1.5))
                        .shadow(color: ArcadeKit.cash.opacity(0.5), radius: 12, y: 4)
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 24 * scale)
    }

    private func rewardCard(_ reward: ChestReward, scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [reward.rarity.color.opacity(0.5), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 38 * scale
                        )
                    )
                Image(systemName: reward.iconSystemName)
                    .font(.system(size: 30 * scale, weight: .black))
                    .foregroundStyle(reward.rarity.color)
                    .shadow(color: reward.rarity.color.opacity(0.8), radius: 10)
            }
            .frame(height: 56 * scale)

            Text(reward.displayName)
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.65)

            Text(reward.rarity.displayName.uppercased())
                .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 8 * scale)
                .padding(.vertical, 2.5 * scale)
                .background(Capsule().fill(reward.rarity.color))

            Text(reward.subtitle)
                .font(.system(size: 8.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(10 * scale)
        .frame(width: 132 * scale)
        .background(ArcadeTileBackground(tint: reward.rarity.color, isSelected: reward.rarity == .legendary))
    }

    // MARK: - Séquence d'ouverture

    private func playSequence() {
        haloPulse = true
        Task {
            // Tremblement qui s'intensifie.
            for step in 0..<10 {
                withAnimation(.easeInOut(duration: 0.07)) {
                    shakeAmount = (step.isMultiple(of: 2) ? 1 : -1) * (2 + Double(step) * 0.9)
                }
                try? await Task.sleep(for: .milliseconds(75))
            }
            withAnimation(.easeOut(duration: 0.1)) { shakeAmount = 0 }

            burst = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioService.shared.playSplat(volume: 0.85)

            try? await Task.sleep(for: .milliseconds(320))
            phase = 1

            for index in 1...max(payload.rewards.count, 1) {
                try? await Task.sleep(for: .milliseconds(420))
                revealedCount = index
                UIImpactFeedbackGenerator(style: index == payload.rewards.count ? .medium : .light).impactOccurred()
            }
        }
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
