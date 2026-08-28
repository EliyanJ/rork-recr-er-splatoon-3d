import SwiftUI

/// Very first screen shown on every cold launch, right before the hub —
/// avoids a jarring instant jump straight into the app and gives the game a
/// proper "boot" moment. Uses the same arena background + logo as the hub
/// (no skull artwork — kept clean/minimal).
struct LaunchLoadingView: View {
    let onDone: () -> Void

    @State private var logoScale: CGFloat = 0.82
    @State private var logoOpacity: Double = 0
    @State private var barProgress: Double = 0
    @State private var displayedPercent: Int = 0
    @State private var tipIndex = 0
    @State private var showSettings = false
    @State private var showAccount = false

    private let tips = [
        "Utilise la hauteur à ton avantage !",
        "Recharge ton arme à couvert, jamais à découvert.",
        "Peindre le sol ralentit l'équipe adverse.",
        "Vise les surfaces larges pour couvrir plus de terrain.",
    ]

    var body: some View {
        GeometryReader { geo in
            let scale = menuScaleFactor(for: geo.size.height)

            ZStack {
                GeometryReader { screenGeo in
                    background(size: screenGeo.size)
                }
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar(scale: scale)

                    Spacer(minLength: 0)

                    logo(scale: scale)

                    Spacer(minLength: 0)

                    bottomPanel(scale: scale)
                }
                .padding(menuBaseMargin)

                VStack {
                    Spacer()
                    HStack {
                        Text("v1.0.0")
                            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text("© 2024 Inkling Studios")
                            .font(.system(size: 10 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        onlinePill(scale: scale)
                    }
                }
                .padding(menuBaseMargin)
            }
        }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.68)) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.easeInOut(duration: 1.15)) {
                barProgress = 1
            }
            for value in stride(from: 0, through: 100, by: 2) {
                displayedPercent = value
                try? await Task.sleep(for: .milliseconds(23))
            }
            try? await Task.sleep(for: .milliseconds(150))
            onDone()
        }
        .task {
            while true {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeInOut(duration: 0.3)) {
                    tipIndex = (tipIndex + 1) % tips.count
                }
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(onClose: { showSettings = false })
        }
        .fullScreenCover(isPresented: $showAccount) {
            ProfileScreen(
                onBack: { showAccount = false },
                onSelectTab: { _ in showAccount = false },
                onSettings: { showAccount = false; showSettings = true }
            )
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
            } else {
                MenuBackground()
                    .frame(width: size.width, height: size.height)
            }

            LinearGradient(
                colors: [.black.opacity(0.45), .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Barre du haut

    private func topBar(scale: CGFloat) -> some View {
        HStack {
            Spacer()

            pillButton(icon: "person.fill", title: "COMPTE", scale: scale) {
                showAccount = true
            }
            pillButton(icon: "gearshape.fill", title: "PARAMÈTRES", scale: scale) {
                showSettings = true
            }
        }
        .opacity(logoOpacity)
    }

    private func pillButton(icon: String, title: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 6 * scale) {
                Image(systemName: icon)
                    .font(.system(size: 11 * scale, weight: .bold))
                Text(title)
                    .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8 * scale)
            .background(Capsule().fill(.black.opacity(0.55)))
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    private func onlinePill(scale: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
            Text("EN LIGNE")
                .font(.system(size: 10 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Logo

    private func logo(scale: CGFloat) -> some View {
        VStack(spacing: 10 * scale) {
            Group {
                if UIImage(named: "splash_graffiti_logo") != nil {
                    Image("splash_graffiti_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 340 * scale)
                } else {
                    Text("SPLASH")
                        .font(.system(size: 50 * scale, weight: .black, design: .rounded))
                        .italic()
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 6) {
                Text("PEINS.")
                    .foregroundStyle(Color(hex: "FF6A00"))
                Text("COMBATS.")
                    .foregroundStyle(.white)
                Text("DOMINE.")
                    .foregroundStyle(Color(hex: "B24CFF"))
            }
            .font(.system(size: 13 * scale, weight: .black, design: .rounded))
        }
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }

    // MARK: - Bas (progression + astuce)

    private func bottomPanel(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            HStack {
                Text("CHARGEMENT…")
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(displayedPercent)%")
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FF6A00"), .pink, Color(hex: "B24CFF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, barGeo.size.width * barProgress))
                }
            }
            .frame(height: 8 * scale)

            HStack(spacing: 8 * scale) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(Color(hex: "FFC400"))
                Text("ASTUCE : \(tips[tipIndex])")
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(tipIndex)
                    .transition(.opacity)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12 * scale)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
        .opacity(logoOpacity)
        .padding(.bottom, 46)
    }
}

#Preview {
    LaunchLoadingView(onDone: {})
}
