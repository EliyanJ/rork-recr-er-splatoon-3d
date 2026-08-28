import SwiftUI

// MARK: - Palette partagée "Splash"

extension Color {
    static let menuAccent = Color(hex: "FFC400")
    static let menuPanel = Color(hex: "121216")
}

/// Enables leading-dot syntax (e.g. `.foregroundStyle(.menuAccent)`) anywhere
/// a `ShapeStyle` is expected, not just where a concrete `Color` is expected.
extension ShapeStyle where Self == Color {
    static var menuAccent: Color { Color.menuAccent }
    static var menuPanel: Color { Color.menuPanel }
}

// MARK: - Échelle & marge responsive (identique à l'accueil)

/// Réduit polices/tailles/espacements quand la hauteur disponible est
/// restreinte (typique du paysage sur iPhone) — même formule que l'accueil,
/// partagée par tous les écrans du menu pour rester cohérente.
func menuScaleFactor(for height: CGFloat) -> CGFloat {
    min(1, max(0.68, height / 420))
}

/// Marge de respiration esthétique ajoutée par-dessus la zone sûre native du
/// système (qui gère déjà l'encoche/île dynamique/coins pour l'orientation
/// courante). Ne JAMAIS combiner avec `.ignoresSafeArea()` sur le contenu.
let menuBaseMargin: CGFloat = 14

// MARK: - Forme "panneau peint" (parallélogramme aux bords irréguliers)

/// Panneau légèrement incliné façon pochoir/peinture — direction artistique
/// commune à tous les écrans du menu.
struct PaintedPanel: Shape {
    var skew: CGFloat

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 6
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + skew + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + 1))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - skew * 0.4, y: rect.minY + r),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - skew, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - skew - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX - skew, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY - 1))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + skew * 0.4, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + skew, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + skew + r, y: rect.minY),
            control: CGPoint(x: rect.minX + skew, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Style de bouton avec feedback de pression

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Onglets de navigation basse (partagés par les 5 écrans)

enum MenuTab: String, CaseIterable, Identifiable {
    case home, play, armory, shop, missions, rank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Accueil"
        case .play: "Jouer"
        case .armory: "Équipement"
        case .shop: "Boutique"
        case .missions: "Missions"
        case .rank: "Classement"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .play: "play.fill"
        case .armory: "scope"
        case .shop: "bag.fill"
        case .missions: "target"
        case .rank: "chart.bar.fill"
        }
    }
}

/// Barre de navigation basse commune — icône + libellé court, protégée par la
/// même marge que le reste du contenu.
struct MenuTabBar: View {
    let active: MenuTab
    let scale: CGFloat
    let onSelect: (MenuTab) -> Void

    var body: some View {
        HStack(spacing: 4 * scale) {
            ForEach(MenuTab.allCases) { tab in
                Button {
                    onSelect(tab)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15 * scale, weight: .bold))
                        Text(tab.title)
                            .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(active == tab ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(active == tab ? Color.menuAccent : .clear)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(5)
        .background(Capsule().fill(.black.opacity(0.6)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .clipShape(Capsule())
    }
}

// MARK: - En-tête commun (retour, titre, monnaies, notifications, réglages)

struct MenuHeaderBar: View {
    let title: String
    let scale: CGFloat
    let onBack: () -> Void
    var pigments: Int? = nil
    var prisms: Int? = nil
    var onSettings: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8 * scale) {
            Button {
                onBack()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5 * scale) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12 * scale, weight: .black))
                    Text("ACCUEIL")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6 * scale)
                .background(Capsule().fill(.black.opacity(0.55)))
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            Text(title)
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let pigments {
                menuCurrencyPill(icon: "paintpalette.fill", tint: Color(hex: "FF2E8A"), value: pigments, scale: scale)
            }
            if let prisms {
                menuCurrencyPill(icon: "diamond.fill", tint: Color(hex: "2EE6D6"), value: prisms, scale: scale)
            }
            if let onSettings {
                Button {
                    onSettings()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 28 * scale, height: 28 * scale)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private func menuCurrencyPill(icon: String, tint: Color, value: Int, scale: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(tint)
            Text(value.formatted(.number.grouping(.automatic)))
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5 * scale)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Fond commun (arène + voile de lisibilité)

struct MenuScreenBackdrop: View {
    let size: CGSize

    var body: some View {
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
                colors: [.black.opacity(0.55), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Coquille commune des 5 écrans du menu

/// Assemble fond plein écran + en-tête + contenu + barre de navigation basse,
/// tous protégés par la marge de sécurité responsive — même schéma que
/// l'accueil : le fond ignore la zone sûre, le contenu la respecte.
struct MenuScreenScaffold<Content: View>: View {
    let title: String
    let activeTab: MenuTab
    let pigments: Int
    let prisms: Int
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void
    @ViewBuilder var content: (CGFloat) -> Content

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
                        title: title,
                        scale: scale,
                        onBack: onBack,
                        pigments: pigments,
                        prisms: prisms,
                        onSettings: onSettings
                    )

                    content(scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    MenuTabBar(active: activeTab, scale: scale, onSelect: onSelectTab)
                }
                .padding(menuBaseMargin)
            }
        }
    }
}
