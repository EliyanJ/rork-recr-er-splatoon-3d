import SwiftUI

/// Match intro overlay drawn OVER the live arena while it finishes building
/// in the background: scrolling lore plays over waiting music during the
/// real scene load (no more frozen screen), then a full-screen 5-4-3-2-1
/// countdown reveals the arena before the match actually starts.
struct MatchIntroOverlay: View {
    /// True once the 3D arena finished loading behind the overlay.
    let isSceneReady: Bool
    /// Called when the countdown ends — the match goes live.
    let onBegin: () -> Void

    private enum Phase {
        case connecting
        case countdown
    }

    @State private var phase: Phase = .connecting
    @State private var countdown = 5
    @State private var pulse = false
    @State private var stripeOffset: CGFloat = 0
    /// Minimum time the lore screen stays up, even on fast loads.
    @State private var minimumDelayDone = false

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            if phase == .countdown {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if phase == .connecting {
                connectingView
                    .transition(.opacity)
            } else {
                countdownView
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: phase)
        .onAppear {
            AudioService.shared.playLobbyMusic()
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                stripeOffset = 40
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.0))
            minimumDelayDone = true
            startCountdownIfReady()
        }
        .onChange(of: isSceneReady) { _, _ in
            startCountdownIfReady()
        }
    }

    /// The countdown only starts once the arena is REALLY loaded and the
    /// lore has been readable for a couple of seconds.
    private func startCountdownIfReady() {
        guard phase == .connecting, isSceneReady, minimumDelayDone else { return }
        phase = .countdown
        Task {
            for value in stride(from: 5, through: 1, by: -1) {
                countdown = value
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
            }
            AudioService.shared.stopLobbyMusic()
            onBegin()
        }
    }

    private var connectingView: some View {
        VStack(spacing: 22) {
            matchupBadge

            statusPanel

            paintProgressBar
        }
        .padding(.horizontal, 28)
    }

    /// Orange vs Purple team crest — echoes the versus framing of a real
    /// match instead of a generic spinner icon.
    private var matchupBadge: some View {
        HStack(spacing: 14) {
            teamCrest(.orange)
            Text("VS")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            teamCrest(.purple)
        }
    }

    private func teamCrest(_ team: Team) -> some View {
        ZStack {
            Circle()
                .fill(team.color.opacity(0.22))
                .frame(width: 62, height: 62)
                .blur(radius: 6)
            Circle()
                .fill(Color.menuPanel.opacity(0.85))
                .frame(width: 54, height: 54)
                .overlay(Circle().stroke(team.color.opacity(0.8), lineWidth: 2))
            Image(systemName: "drop.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(team.color)
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 10) {
            Text(isSceneReady ? "PRÉPARATION DE L'ARÈNE…" : "CONNEXION DES JOUEURS…")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 22)
        .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.82)))
        .overlay(PaintedPanel(skew: 4).stroke(.menuAccent.opacity(0.45), lineWidth: 1.5))
    }

    /// Painted, striped progress bar standing in for a real percentage — the
    /// scene load isn't measurable step-by-step, so the marching diagonal
    /// stripes read as "actively working" rather than a frozen bar.
    private var paintProgressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.4))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Team.orange.color, Color.menuAccent, Team.purple.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        diagonalStripes
                            .clipShape(Capsule())
                    )
            }
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1.5))
        }
        .frame(width: 220, height: 12)
    }

    private var diagonalStripes: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 14
            var x = -stripeWidth * 2 + stripeOffset
            while x < size.width + stripeWidth {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + stripeWidth, y: size.height))
                path.addLine(to: CGPoint(x: x + stripeWidth * 2, y: 0))
                path.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
                path.closeSubpath()
                context.fill(path, with: .color(.white.opacity(0.18)))
                x += stripeWidth * 2
            }
        }
    }

    private var countdownView: some View {
        VStack(spacing: 14) {
            Text("LE COMBAT COMMENCE DANS")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.4)))
                .overlay(Capsule().stroke(.menuAccent.opacity(0.5), lineWidth: 1.5))
            Text("\(countdown)")
                .font(.system(size: 130, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Team.orange.color, .pink, Team.purple.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .id(countdown)
                .onAppear {
                    pulse = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pulse = true }
                }
        }
    }
}

#Preview {
    MatchIntroOverlay(isSceneReady: true, onBegin: {})
}
