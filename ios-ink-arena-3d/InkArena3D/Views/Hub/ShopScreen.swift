import SwiftUI

/// Écran "BOUTIQUE" — mise en page marchande façon arcade : colonne de
/// cadeau quotidien à gauche, rangée de colonnes d'offres à droite avec
/// pastille de promo, ancien prix barré et gros bouton de prix vert.
/// L'économie réelle (MetaStore) est inchangée ; les achats en euros restent
/// des achats de démonstration jusqu'au branchement de la facturation.
struct ShopScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void
    let onShowOdds: () -> Void
    let onOpenSeason: () -> Void

    private enum Category: String, CaseIterable, Identifiable {
        case offers, chests, skins, season

        var id: String { rawValue }

        var title: String {
            switch self {
            case .offers: "Offres"
            case .chests: "Coffres"
            case .skins: "Skins"
            case .season: "Carnet"
            }
        }

        var icon: String {
            switch self {
            case .offers: "tag.fill"
            case .chests: "shippingbox.fill"
            case .skins: "paintbrush.fill"
            case .season: "book.fill"
            }
        }
    }

    /// Une colonne d'offre en euros (achat de démonstration).
    private struct PaidOffer: Identifiable {
        let id: String
        let title: String
        let pitch: String
        let promoPercent: Int
        let oldPrice: String
        let price: String
        let tint: Color
        let isFeatured: Bool
        let pigments: Int
        let prisms: Int
        let chests: [ChestType]
    }

    @State private var meta = MetaStore.shared
    @State private var category: Category = .offers
    @State private var inspectedOffer: ShopOffer?
    @State private var purchaseNotice: String?
    @AppStorage("shop.dailyGift.lastClaimDay") private var lastGiftDay: Int = -1

    private var todayOrdinal: Int {
        Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
    }

    private var giftAvailable: Bool { lastGiftDay != todayOrdinal }

    private var paidOffers: [PaidOffer] {
        var offers: [PaidOffer] = []
        if !meta.starterPackOwned {
            offers.append(
                PaidOffer(
                    id: "starter", title: "Kit du débutant",
                    pitch: "Tout ce qu'il faut pour démarrer fort",
                    promoPercent: 66, oldPrice: "14,99 €", price: "4,99 €",
                    tint: Color(hex: "9A3DF5"), isFeatured: true,
                    pigments: 0, prisms: 500, chests: []
                )
            )
        }
        offers.append(contentsOf: [
            PaidOffer(
                id: "boost", title: "Coffre + pigments",
                pitch: "Un coffre Or et de quoi acheter des skins",
                promoPercent: 40, oldPrice: "5,99 €", price: "3,49 €",
                tint: Color(hex: "FF7A1A"), isFeatured: false,
                pigments: 1500, prisms: 0, chests: [.gold]
            ),
            PaidOffer(
                id: "prism_small", title: "Poignée de prismes",
                pitch: "La recharge la plus simple",
                promoPercent: 0, oldPrice: "", price: "0,99 €",
                tint: Color(hex: "3DB8F5"), isFeatured: false,
                pigments: 0, prisms: 100, chests: []
            ),
            PaidOffer(
                id: "prism_mid", title: "Sac de prismes",
                pitch: "Le meilleur rapport quantité / prix",
                promoPercent: 25, oldPrice: "8,99 €", price: "4,99 €",
                tint: Color(hex: "3DB8F5"), isFeatured: false,
                pigments: 0, prisms: 550, chests: []
            ),
            PaidOffer(
                id: "prism_big", title: "Coffre de prismes",
                pitch: "Pour tout débloquer d'un coup",
                promoPercent: 50, oldPrice: "24,99 €", price: "9,99 €",
                tint: Color(hex: "F5C518"), isFeatured: false,
                pigments: 500, prisms: 1200, chests: [.legendary]
            ),
        ])
        return offers
    }

    private var filteredOffers: [ShopOffer] {
        meta.dailyOffers.filter { offer in
            switch category {
            case .chests:
                if case .chest = offer.payload { return true }
                return false
            case .skins:
                if case .weaponSkin = offer.payload { return true }
                if case .gear = offer.payload { return true }
                return false
            default:
                return false
            }
        }
    }

    var body: some View {
        MenuScreenScaffold(
            title: "BOUTIQUE",
            activeTab: .shop,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            HStack(alignment: .top, spacing: 9 * scale) {
                dailyGiftColumn(scale: scale)
                    .frame(width: 104 * scale)

                VStack(spacing: 7 * scale) {
                    categoryStrip(scale: scale)
                    categoryContent(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(item: $inspectedOffer) { offer in
            offerDetail(offer).presentationDetents([.medium])
        }
        .alert(
            "Achat effectué",
            isPresented: Binding(get: { purchaseNotice != nil }, set: { if !$0 { purchaseNotice = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseNotice ?? "")
        }
    }

    // MARK: - Cadeau quotidien (colonne de gauche)

    private func dailyGiftColumn(scale: CGFloat) -> some View {
        VStack(spacing: 7 * scale) {
            ArcadeSectionTitle(text: "Cadeau quotidien", color: Color(hex: "35C46A"), scale: scale)

            VStack(spacing: 7 * scale) {
                Text("Une récompense gratuite chaque jour")
                    .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: "35C46A").opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 40 * scale))
                    Image(systemName: giftAvailable ? "gift.fill" : "checkmark.seal.fill")
                        .font(.system(size: 34 * scale, weight: .black))
                        .foregroundStyle(giftAvailable ? Color(hex: "35C46A") : .white.opacity(0.35))
                        .shadow(color: giftAvailable ? Color(hex: "35C46A").opacity(0.6) : .clear, radius: 10)
                }
                .frame(height: 60 * scale)

                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundStyle(Team.orange.color)
                    Text("+120")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                Button {
                    guard giftAvailable else { return }
                    meta.grantPigments(120)
                    lastGiftDay = todayOrdinal
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text(giftAvailable ? "RÉCUPÉRER" : "REVIENS DEMAIN")
                        .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7 * scale)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(giftAvailable ? ArcadeKit.cash : Color.white.opacity(0.12))
                        )
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(!giftAvailable)
            }
            .padding(9 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ArcadeTileBackground(tint: Color(hex: "35C46A")))
        }
    }

    // MARK: - Catégories

    private func categoryStrip(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            ForEach(Category.allCases) { item in
                Button {
                    category = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5 * scale) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10 * scale, weight: .black))
                        Text(item.title.uppercased())
                            .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(category == item ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(category == item ? Color.menuAccent : Color.menuPanel.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(category == item ? .clear : .white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private func categoryContent(scale: CGFloat) -> some View {
        switch category {
        case .offers:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8 * scale) {
                    ForEach(paidOffers) { offer in
                        paidOfferColumn(offer, scale: scale)
                            .frame(width: 128 * scale)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .contentMargins(.horizontal, 2)

        case .chests, .skins:
            ScrollView(showsIndicators: false) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104 * scale), spacing: 7 * scale)],
                    spacing: 7 * scale
                ) {
                    ForEach(filteredOffers) { offer in
                        currencyOfferTile(offer, scale: scale)
                    }
                }
                if filteredOffers.isEmpty {
                    emptyNotice(scale: scale)
                }
            }

        case .season:
            ScrollView(showsIndicators: false) {
                seasonPassCard(scale: scale)
            }
        }
    }

    // MARK: - Colonne d'offre en euros

    private func paidOfferColumn(_ offer: PaidOffer, scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ArcadeSectionTitle(
                text: offer.title,
                color: offer.isFeatured ? Color(hex: "E33232") : offer.tint,
                scale: scale
            )

            VStack(spacing: 6 * scale) {
                Text(offer.pitch)
                    .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                // Contenu du pack.
                VStack(spacing: 5 * scale) {
                    if offer.prisms > 0 {
                        contentRow(icon: "diamond.fill", tint: Color(hex: "3DB8F5"), amount: offer.prisms, scale: scale)
                    }
                    if offer.pigments > 0 {
                        contentRow(icon: "paintpalette.fill", tint: Team.orange.color, amount: offer.pigments, scale: scale)
                    }
                    ForEach(offer.chests) { chest in
                        HStack(spacing: 5 * scale) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 14 * scale, weight: .black))
                                .foregroundStyle(chest.tint)
                            Text(chest.displayName)
                                .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                ArcadePriceButton(
                    price: offer.price,
                    oldPrice: offer.promoPercent > 0 ? offer.oldPrice : nil,
                    scale: scale
                ) {
                    purchase(offer)
                }
            }
            .padding(8 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ArcadeTileBackground(tint: offer.tint, isSelected: offer.isFeatured))
            .overlay(alignment: .topTrailing) {
                if offer.promoPercent > 0 {
                    ArcadePromoTag(percent: offer.promoPercent, scale: scale)
                        .offset(x: 8 * scale, y: -6 * scale)
                }
            }
        }
    }

    private func contentRow(icon: String, tint: Color, amount: Int, scale: CGFloat) -> some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: icon)
                .font(.system(size: 14 * scale, weight: .black))
                .foregroundStyle(tint)
            Text(amount.formatted(.number.grouping(.automatic)))
                .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func purchase(_ offer: PaidOffer) {
        if offer.id == "starter" {
            meta.buyStarterPack()
        } else {
            if offer.prisms > 0 { meta.grantPrisms(offer.prisms) }
            if offer.pigments > 0 { meta.grantPigments(offer.pigments) }
            for chest in offer.chests { meta.addChest(chest) }
        }
        purchaseNotice = "« \(offer.title) » ajouté à ton compte (achat de démonstration — la facturation App Store sera branchée à la publication)."
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Offres en monnaie du jeu

    private func currencyOfferTile(_ offer: ShopOffer, scale: CGFloat) -> some View {
        let owned = meta.hasPurchased(offer)
        return Button {
            guard !owned else { return }
            inspectedOffer = offer
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 5 * scale) {
                Image(systemName: offer.iconSystemName)
                    .font(.system(size: 24 * scale, weight: .black))
                    .foregroundStyle(offer.rarity.color)
                    .shadow(color: offer.rarity.color.opacity(0.6), radius: 6)
                    .frame(height: 30 * scale)

                Text(offer.displayName)
                    .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)

                Text(offer.rarity.displayName.uppercased())
                    .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(offer.rarity.color)

                if owned {
                    Text("POSSÉDÉ ✓")
                        .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(ArcadeKit.cash)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5 * scale)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: offer.currency == .pigments ? "paintpalette.fill" : "diamond.fill")
                            .font(.system(size: 9 * scale, weight: .bold))
                        Text("\(offer.price)")
                            .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(offer.currency == .pigments ? Team.orange.color.opacity(0.85) : Color(hex: "3DB8F5").opacity(0.85))
                    )
                }
            }
            .padding(8 * scale)
            .frame(maxWidth: .infinity)
            .background(ArcadeTileBackground(tint: offer.rarity.color, isLocked: owned))
            .opacity(owned ? 0.7 : 1)
        }
        .buttonStyle(PressableStyle())
    }

    private func emptyNotice(scale: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
            Text("Rien dans cette catégorie aujourd'hui — reviens demain !")
                .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Carnet de saison

    private func seasonPassCard(scale: CGFloat) -> some View {
        Button(action: onOpenSeason) {
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 20 * scale, weight: .black))
                        .foregroundStyle(Team.purple.color)
                    Text("CARNET DE SAISON 1")
                        .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * scale, weight: .black))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text(meta.hasPremiumPass
                     ? "Piste premium active — palier \(meta.seasonTier)/\(MetaStore.seasonTierCount)"
                     : "Débloquer la piste premium (💎 \(MetaStore.premiumPassPrice))")
                    .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                ArcadeStatBar(value: meta.seasonTierProgress, tint: Team.purple.color, scale: scale)
            }
            .padding(12 * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArcadeTileBackground(tint: Team.purple.color))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Détail d'une offre en monnaie du jeu

    private func offerDetail(_ offer: ShopOffer) -> some View {
        let canAfford = offer.currency == .pigments ? meta.pigments >= offer.price : meta.prisms >= offer.price
        let isChest: Bool
        if case .chest = offer.payload { isChest = true } else { isChest = false }
        return ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.11).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: offer.iconSystemName)
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(offer.rarity.color)
                    .padding(20)
                    .background(Circle().fill(offer.rarity.color.opacity(0.15)))
                    .overlay(Circle().stroke(offer.rarity.color.opacity(0.6), lineWidth: 2))
                Text(offer.displayName)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(offer.subtitle) · Rareté : \(offer.rarity.displayName)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(offer.rarity.color)
                if isChest {
                    Button {
                        inspectedOffer = nil
                        onShowOdds()
                    } label: {
                        Text("Voir les probabilités")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Team.orange.color)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if meta.buy(offer) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        inspectedOffer = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("ACHETER —")
                        Image(systemName: offer.currency == .pigments ? "paintpalette.fill" : "diamond.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("\(offer.price)")
                    }
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(canAfford ? ArcadeKit.cash : Color.gray.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)
            }
            .padding(24)
        }
    }
}

#Preview {
    ShopScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {}, onShowOdds: {}, onOpenSeason: {})
}
