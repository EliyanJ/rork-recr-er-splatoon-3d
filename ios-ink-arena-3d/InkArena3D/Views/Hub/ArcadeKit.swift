import SwiftUI

/// Composants partagés du "look arcade" des écrans de sélection (armes,
/// modes, arènes, boutique). Inspiré des jeux d'arcade mobiles : tuiles
/// denses à cadre coloré, badges d'angle, verrous avec palier de niveau,
/// bandeaux promo en biais. Conserve l'identité Splash (panneaux sombres,
/// accent jaune, peinture) — aucune donnée de gameplay n'est touchée.
enum ArcadeKit {
    /// Cadre commun des tuiles : rayon de coin unique pour tout le hub.
    static let tileCorner: CGFloat = 12
    /// Vert des boutons d'achat / de confirmation.
    static let cash = Color(hex: "3FBF4A")
    /// Rouge des pastilles de promo et des badges "Nouveau".
    static let hot = Color(hex: "E33232")
}

// MARK: - Fond de tuile à cadre de rareté

/// Tuile de sélection : dégradé sombre teinté par la couleur passée, cadre
/// épais quand elle est sélectionnée, voile gris quand elle est verrouillée.
struct ArcadeTileBackground: View {
    let tint: Color
    var isSelected: Bool = false
    var isLocked: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ArcadeKit.tileCorner)
                .fill(
                    LinearGradient(
                        colors: isLocked
                            ? [Color(hex: "1A1C24"), Color(hex: "101218")]
                            : [tint.opacity(0.42), Color(hex: "12131A").opacity(0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Reflet diagonal — donne le côté "carte brillante" arcade.
            RoundedRectangle(cornerRadius: ArcadeKit.tileCorner)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isLocked ? 0.02 : 0.16), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )

            RoundedRectangle(cornerRadius: ArcadeKit.tileCorner)
                .stroke(
                    isSelected ? Color.menuAccent : (isLocked ? .white.opacity(0.08) : tint.opacity(0.65)),
                    lineWidth: isSelected ? 2.5 : 1.5
                )
        }
        .shadow(color: isSelected ? Color.menuAccent.opacity(0.45) : .clear, radius: 8)
    }
}

// MARK: - Voile de verrouillage avec palier

/// Superposition grise d'une tuile verrouillée : cadenas + palier requis,
/// exactement le vocabulaire visuel des jeux d'arcade ("640 XP").
struct ArcadeLockOverlay: View {
    let requirement: String
    let scale: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ArcadeKit.tileCorner)
                .fill(.black.opacity(0.55))
            VStack(spacing: 3 * scale) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13 * scale, weight: .black))
                    .foregroundStyle(.white.opacity(0.75))
                Text(requirement)
                    .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Badges d'angle

/// Petit ruban d'angle ("NOUVEAU", "-70%", "ÉQUIPÉ").
struct ArcadeCornerBadge: View {
    let text: String
    let color: Color
    let scale: CGFloat
    var textColor: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 8 * scale, weight: .black, design: .rounded))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6 * scale)
            .padding(.vertical, 2.5 * scale)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
            )
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.35), lineWidth: 1))
    }
}

/// Bandeau vert "ÉQUIPÉ" traversant la tuile, façon carte d'inventaire.
struct ArcadeEquippedBanner: View {
    let scale: CGFloat

    var body: some View {
        Text("ÉQUIPÉ")
            .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3 * scale)
            .background(ArcadeKit.cash.opacity(0.92))
            .overlay(
                Rectangle().stroke(.white.opacity(0.4), lineWidth: 1)
            )
    }
}

// MARK: - Pastille de niveau / rang

/// Chevron de niveau affiché en coin de tuile (niveau de maîtrise d'arme).
struct ArcadeLevelChip: View {
    let level: Int
    let scale: CGFloat
    var tint: Color = .menuAccent

    var body: some View {
        Text("Niv.\(level)")
            .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 2 * scale)
            .background(Capsule().fill(tint))
    }
}

// MARK: - Ligne de statistique chiffrée

/// Ligne "icône · libellé ······ valeur" du panneau de détail d'arme.
struct ArcadeStatRow: View {
    let icon: String
    let label: String
    let value: Int
    let tint: Color
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 6 * scale) {
            Image(systemName: icon)
                .font(.system(size: 9.5 * scale, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 13 * scale)
            Text(label)
                .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text("\(value)")
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}

/// Barre de progression fine sous une statistique.
struct ArcadeStatBar: View {
    let value: Double
    let tint: Color
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.12))
            GeometryReader { proxy in
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4 * scale)
    }
}

// MARK: - Bouton d'achat "prix"

/// Gros bouton vert de prix, avec ancien prix barré optionnel.
struct ArcadePriceButton: View {
    let price: String
    let oldPrice: String?
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack(spacing: 1) {
                if let oldPrice {
                    Text(oldPrice)
                        .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .strikethrough(true, color: ArcadeKit.hot)
                        .lineLimit(1)
                }
                Text(price)
                    .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6 * scale)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: [ArcadeKit.cash, ArcadeKit.cash.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.4), lineWidth: 1))
            .shadow(color: ArcadeKit.cash.opacity(0.35), radius: 4, y: 2)
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Étiquette de promo pendante

/// Pastille ronde "-70%" accrochée au coin d'une colonne d'offre.
struct ArcadePromoTag: View {
    let percent: Int
    let scale: CGFloat

    var body: some View {
        VStack(spacing: -1) {
            Text("-\(percent)")
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
            Text("%")
                .font(.system(size: 7 * scale, weight: .black, design: .rounded))
        }
        .foregroundStyle(.black)
        .frame(width: 32 * scale, height: 32 * scale)
        .background(
            Circle().fill(
                LinearGradient(colors: [Color(hex: "FFD84D"), Color(hex: "F5A312")], startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))
        .rotationEffect(.degrees(-12))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
    }
}

// MARK: - En-tête de section en biais

/// Titre de colonne / section avec fond en biais façon pochoir.
struct ArcadeSectionTitle: View {
    let text: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5 * scale)
            .background(
                PaintedPanel(skew: 3).fill(
                    LinearGradient(colors: [color.opacity(0.9), color.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(PaintedPanel(skew: 3).stroke(.white.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Bandeau d'info du bas

/// Barre d'explication du bas d'écran ("i" + phrase de règle).
struct ArcadeInfoBar: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 9 * scale) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14 * scale, weight: .bold))
                .foregroundStyle(Color(hex: "3DB8F5"))
            Text(text)
                .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 7 * scale)
        .background(RoundedRectangle(cornerRadius: 11).fill(.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12), lineWidth: 1))
    }
}
