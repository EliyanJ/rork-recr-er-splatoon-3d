import Combine
import SwiftUI

/// Hub central : bandeau héros illustré (statique, plus de rendu 3D en
/// temps réel), carrousel d'actus du Cycle en cours, gros CTA JOUER, et les
/// deux tuiles Carnet de Saison / Coffres — layout "jeu vidéo" qui s'adapte
/// à la largeur réelle de l'écran.
struct HomeTabView: View {
    let onPlay: () -> Void
    let onOpenSeason: () -> Void
    let onOpenChest: () -> Void
    let onOpenMenu: () -> Void

    @State private var meta = MetaStore.shared
    @State private var pulse = false
    @State private var newsIndex = 0

    private let newsTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 380

            VStack(spacing: isCompact ? 8 : 14) {
                heroBanner
                    .frame(height: isCompact ? 78 : 104)

                newsCarousel

                Spacer(minLength: 4)

                playButton
                tilesRow
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onReceive(newsTimer) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                newsIndex = (newsIndex + 1) % NewsCatalog.items.count
            }
        }
    }

    // MARK: Bandeau héros (statique, sans 3D)

    private var heroBanner: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [Team.purple.color.opacity(0.55), Team.orange.color.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image("ink_arena_billboard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .opacity(0.9)
                .allowsHitTesting(false)

            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.35)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPLASH")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    Text("Niveau \(meta.accountLevel) — prêt au combat")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.leading, 16)
                Spacer(minLength: 0)
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.18), lineWidth: 1.5)
        )
    }

    // MARK: Carrousel d'actus

    private var newsCarousel: some View {
        VStack(spacing: 6) {
            TabView(selection: $newsIndex) {
                ForEach(Array(NewsCatalog.items.enumerated()), id: \.element.id) { index, item in
                    newsCard(item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 72)

            HStack(spacing: 5) {
                ForEach(0..<NewsCatalog.items.count, id: \.self) { index in
                    Circle()
                        .fill(index == newsIndex ? Team.orange.color : .white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private func newsCard(_ item: NewsItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(hex: item.tintHex))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: item.tintHex).opacity(0.5), lineWidth: 1.5)
        )
        .padding(.horizontal, 2)
    }

    // MARK: CTA Jouer

    private var playButton: some View {
        Button(action: onPlay) {
            Label("JOUER", systemImage: "play.fill")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    Capsule()
                        .fill(Team.orange.color)
                        .shadow(color: Team.orange.color.opacity(0.55), radius: 14, y: 4)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.03 : 1)
    }

    // MARK: Tuiles Carnet / Coffres

    private var tilesRow: some View {
        HStack(spacing: 12) {
            tile(
                title: "CARNET SAISON",
                subtitle: "Palier \(meta.seasonTier)/\(MetaStore.seasonTierCount)",
                icon: "book.fill",
                tint: Team.purple.color,
                badge: nil,
                action: onOpenSeason
            )
            tile(
                title: "COFFRES",
                subtitle: meta.totalChestsReady > 0 ? "Prêt à ouvrir !" : "Gagne des matchs",
                icon: "shippingbox.fill",
                tint: Color(hex: "F5C518"),
                badge: meta.totalChestsReady > 0 ? meta.totalChestsReady : nil,
                action: onOpenChest
            )
        }
    }

    private func tile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        badge: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(tint)
                    Spacer()
                    if let badge {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.red))
                    }
                }
                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.5)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(tint.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        MenuBackground()
        HomeTabView(onPlay: {}, onOpenSeason: {}, onOpenChest: {}, onOpenMenu: {})
    }
}
