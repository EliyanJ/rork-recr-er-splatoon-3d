import SwiftUI

/// Écran "BOUTIQUE" — bandeau promo (starter pack), catégories à gauche
/// (Coffres / Skins / Carnet / Prismes) qui filtrent les offres du jour à
/// droite, packs de monnaies. Réutilise l'économie factice déjà en place
/// (MetaStore) — seule la mise en page change.
struct ShopScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void
    let onShowOdds: () -> Void
    let onOpenSeason: () -> Void

    private enum Category: String, CaseIterable {
        case chests, skins, season, prisms

        var title: String {
            switch self {
            case .chests: "Coffres"
            case .skins: "Skins"
            case .season: "Carnet"
            case .prisms: "Prismes"
            }
        }

        var icon: String {
            switch self {
            case .chests: "shippingbox.fill"
            case .skins: "paintbrush.fill"
            case .season: "book.fill"
            case .prisms: "diamond.fill"
            }
        }
    }

    @State private var meta = MetaStore.shared
    @State private var category: Category = .chests
    @State private var inspectedOffer: ShopOffer?
    @State private var showStarterPack = false
    @State private var prismPack: PrismPack?

    private struct PrismPack: Identifiable {
        let id: Int
        let amount: Int
        let priceLabel: String
    }

    private let prismPacks: [PrismPack] = [
        PrismPack(id: 0, amount: 100, priceLabel: "0,99 €"),
        PrismPack(id: 1, amount: 550, priceLabel: "4,99 €"),
        PrismPack(id: 2, amount: 1200, priceLabel: "9,99 €"),
        PrismPack(id: 3, amount: 2500, priceLabel: "19,99 €"),
    ]

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
            VStack(spacing: 10 * scale) {
                if !meta.starterPackOwned {
                    promoBanner(scale: scale)
                }

                HStack(alignment: .top, spacing: 10 * scale) {
                    categoryRail(scale: scale)
                        .frame(width: 74 * scale)

                    categoryContent(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(item: $inspectedOffer) { offer in offerDetail(offer).presentationDetents([.medium]) }
        .sheet(isPresented: $showStarterPack) { starterPackDetail.presentationDetents([.medium]) }
        .alert("Prismes ajoutés !", isPresented: Binding(get: { prismPack != nil }, set: { if !$0 { prismPack = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("+\(prismPack?.amount ?? 0) 💎 (achat de démonstration)")
        }
    }

    // MARK: Bandeau promo

    private func promoBanner(scale: CGFloat) -> some View {
        Button {
            showStarterPack = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundStyle(.menuAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("STARTER PACK")
                        .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("3 skins épiques + 500 💎")
                        .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 4)
                Text("4,99 €")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6 * scale)
                    .background(Capsule().fill(.menuAccent))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10 * scale)
            .frame(maxWidth: .infinity)
            .background(
                PaintedPanel(skew: 4).fill(
                    LinearGradient(colors: [Team.purple.color.opacity(0.55), Team.orange.color.opacity(0.5)], startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(PaintedPanel(skew: 4).stroke(.menuAccent.opacity(0.7), lineWidth: 2))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Catégories

    private func categoryRail(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            ForEach(Category.allCases, id: \.rawValue) { item in
                Button {
                    category = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15 * scale, weight: .bold))
                        Text(item.title.uppercased())
                            .font(.system(size: 7.5 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(category == item ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9 * scale)
                    .background(RoundedRectangle(cornerRadius: 12).fill(category == item ? Color.menuAccent : .white.opacity(0.08)))
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func categoryContent(scale: CGFloat) -> some View {
        ScrollView(showsIndicators: false) {
            switch category {
            case .chests, .skins:
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(filteredOffers) { offer in
                        offerCard(offer, scale: scale)
                    }
                }
                if filteredOffers.isEmpty {
                    emptyNotice(scale: scale)
                }
            case .season:
                seasonPassCard(scale: scale)
            case .prisms:
                VStack(spacing: 8 * scale) {
                    ForEach(prismPacks) { pack in
                        prismPackRow(pack, scale: scale)
                    }
                    Text("Achats de démonstration — la facturation App Store sera branchée à la publication.")
                        .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func emptyNotice(scale: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
            Text("Rien dans cette catégorie aujourd'hui — reviens demain !")
                .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func offerCard(_ offer: ShopOffer, scale: CGFloat) -> some View {
        let owned = meta.hasPurchased(offer)
        return Button {
            guard !owned else { return }
            inspectedOffer = offer
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 6 * scale) {
                Image(systemName: offer.iconSystemName)
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundStyle(offer.rarity.color)
                    .frame(height: 30 * scale)
                Text(offer.displayName)
                    .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if owned {
                    Text("POSSÉDÉ ✓")
                        .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: offer.currency == .pigments ? "paintpalette.fill" : "diamond.fill")
                            .font(.system(size: 9 * scale, weight: .bold))
                        Text("\(offer.price)")
                            .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(offer.currency == .pigments ? Team.orange.color : Color(hex: "3DB8F5"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4 * scale)
                    .background(Capsule().fill(.black.opacity(0.4)))
                }
            }
            .padding(.vertical, 10 * scale)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(offer.rarity.color.opacity(0.5), lineWidth: 1.5))
            .opacity(owned ? 0.65 : 1)
        }
        .buttonStyle(PressableStyle())
    }

    private func seasonPassCard(scale: CGFloat) -> some View {
        Button(action: onOpenSeason) {
            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 20 * scale, weight: .bold))
                        .foregroundStyle(Team.purple.color)
                    Text("CARNET DE SAISON 1")
                        .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text(meta.hasPremiumPass
                     ? "Piste premium active — palier \(meta.seasonTier)/\(MetaStore.seasonTierCount)"
                     : "Débloquer la piste premium (💎 \(MetaStore.premiumPassPrice))")
                    .font(.system(size: 10.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    GeometryReader { proxy in
                        Capsule().fill(Team.purple.color)
                            .frame(width: proxy.size.width * meta.seasonTierProgress)
                    }
                }
                .frame(height: 6 * scale)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Team.purple.color.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }

    private func prismPackRow(_ pack: PrismPack, scale: CGFloat) -> some View {
        Button {
            meta.grantPrisms(pack.amount)
            prismPack = pack
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 16 * scale, weight: .bold))
                    .foregroundStyle(Color(hex: "3DB8F5"))
                Text("\(pack.amount)")
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Text(pack.priceLabel)
                    .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5 * scale)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9 * scale)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "3DB8F5").opacity(0.4), lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Détails

    private var starterPackDetail: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 44, weight: .bold)).foregroundStyle(.menuAccent)
                Text("STARTER PACK").font(.system(size: 22, weight: .black, design: .rounded)).foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 8) {
                    Label("500 Prismes 💎", systemImage: "diamond.fill")
                    Label("3 skins d'armes épiques (Néon Circuit)", systemImage: "paintbrush.fill")
                    Label("Réservé aux nouveaux joueurs — une seule fois", systemImage: "person.fill.checkmark")
                }
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                Button {
                    meta.buyStarterPack()
                    showStarterPack = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Text("ACHETER — 4,99 €")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 13)
                        .background(Capsule().fill(.menuAccent))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }

    private func offerDetail(_ offer: ShopOffer) -> some View {
        let canAfford = offer.currency == .pigments ? meta.pigments >= offer.price : meta.prisms >= offer.price
        let isChest: Bool
        if case .chest = offer.payload { isChest = true } else { isChest = false }
        return ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: offer.iconSystemName)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(offer.rarity.color)
                    .padding(20)
                    .background(Circle().fill(.white.opacity(0.08)))
                Text(offer.displayName).font(.system(size: 19, weight: .black, design: .rounded)).foregroundStyle(.white)
                Text("\(offer.subtitle) · Rareté : \(offer.rarity.displayName)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(offer.rarity.color)
                if isChest {
                    Button {
                        inspectedOffer = nil
                        onShowOdds()
                    } label: {
                        Text("Voir les probabilités").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Team.orange.color).underline()
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
                        Image(systemName: offer.currency == .pigments ? "paintpalette.fill" : "diamond.fill").font(.system(size: 13, weight: .bold))
                        Text("\(offer.price)")
                    }
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(canAfford ? Team.orange.color : Color.gray.opacity(0.5)))
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
