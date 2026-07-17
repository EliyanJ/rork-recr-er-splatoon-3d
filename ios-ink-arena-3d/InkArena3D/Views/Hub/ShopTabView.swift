import Combine
import SwiftUI

/// Boutique — rotation quotidienne (countdown avant renouvellement),
/// starter pack mis en avant, raccourci Carnet de Saison, recharge Prismes
/// et bouton Restaurer. Tout achat passe par un modal de confirmation
/// (jamais d'achat en un tap) ; les coffres exposent leurs probabilités.
struct ShopTabView: View {
    let onShowOdds: () -> Void
    let onOpenSeason: () -> Void

    @State private var meta = MetaStore.shared
    @State private var inspectedOffer: ShopOffer?
    @State private var showStarterPack = false
    @State private var prismPack: PrismPack?
    @State private var showRestoreNotice = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Simulated Prisms top-up tiers (StoreKit at publication).
    struct PrismPack: Identifiable {
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

    private var countdownText: String {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let remaining = max(0, Int(midnight.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", remaining / 3600, (remaining % 3600) / 60, remaining % 60)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    Text("BOUTIQUE")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Label(countdownText, systemImage: "clock.fill")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Team.orange.color)
                        .monospacedDigit()
                }

                // Starter pack — visuellement l'offre la plus mise en avant.
                if !meta.starterPackOwned {
                    starterPackCard
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(meta.dailyOffers) { offer in
                        offerCard(offer)
                    }
                }

                seasonPassCard

                VStack(alignment: .leading, spacing: 8) {
                    Text("RECHARGE PRISMES")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 8) {
                        ForEach(prismPacks) { pack in
                            prismPackCell(pack)
                        }
                    }
                    Text("Achats de démonstration — la facturation App Store sera branchée à la publication.")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Button {
                    showRestoreNotice = true
                } label: {
                    Text("Restaurer les achats")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().stroke(.white.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)

                Button(action: onShowOdds) {
                    Label("Voir les probabilités des coffres", systemImage: "percent")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Team.orange.color)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .onReceive(clock) { date in now = date }
        .sheet(item: $inspectedOffer) { offer in
            offerDetail(offer)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showStarterPack) {
            starterPackDetail
                .presentationDetents([.medium])
        }
        .alert("Prismes ajoutés !", isPresented: Binding(
            get: { prismPack != nil },
            set: { if !$0 { prismPack = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("+\(prismPack?.amount ?? 0) 💎 (achat de démonstration)")
        }
        .alert("Restaurer les achats", isPresented: $showRestoreNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tes achats sont stockés localement pour l'instant — rien à restaurer. La restauration App Store sera active à la publication.")
        }
    }

    // MARK: Starter pack

    private var starterPackCard: some View {
        Button {
            showStarterPack = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 4) {
                    Text("🌟 STARTER PACK")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("3 skins épiques + 500 Prismes")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("4,99 €")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.yellow))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Team.purple.color.opacity(0.7), Team.orange.color.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.yellow.opacity(0.7), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var starterPackDetail: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.yellow)
                Text("STARTER PACK")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
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
                        .background(Capsule().fill(.yellow))
                }
                .buttonStyle(.plain)

                Text("Achat de démonstration — accordé directement pour tester l'économie du jeu.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }

    // MARK: Rotation du jour

    private func offerCard(_ offer: ShopOffer) -> some View {
        let owned = meta.hasPurchased(offer)
        return Button {
            guard !owned else { return }
            inspectedOffer = offer
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: offer.iconSystemName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(offer.rarity.color)
                    .frame(height: 40)
                Text(offer.displayName)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(offer.subtitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                if owned {
                    Text("POSSÉDÉ ✓")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.vertical, 5)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: offer.currency == .pigments ? "paintpalette.fill" : "diamond.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(offer.price)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(offer.currency == .pigments ? Team.orange.color : Color(hex: "3DB8F5"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.4)))
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.07)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(offer.rarity.color.opacity(0.5), lineWidth: 1.5)
            )
            .opacity(owned ? 0.65 : 1)
        }
        .buttonStyle(.plain)
    }

    private func offerDetail(_ offer: ShopOffer) -> some View {
        let canAfford = offer.currency == .pigments
            ? meta.pigments >= offer.price
            : meta.prisms >= offer.price
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
                Text(offer.displayName)
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
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
                    .background(Capsule().fill(canAfford ? Team.orange.color : Color.gray.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)

                if !canAfford {
                    Text(offer.currency == .pigments
                         ? "Pas assez de Pigments — gagne-en en jouant !"
                         : "Pas assez de Prismes — recharge en bas de la Boutique.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }

    // MARK: Carnet de Saison + Prismes

    private var seasonPassCard: some View {
        Button(action: onOpenSeason) {
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Team.purple.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text("📖 CARNET DE SAISON — Cycle 1")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(meta.hasPremiumPass
                         ? "Piste premium active — palier \(meta.seasonTier)/\(MetaStore.seasonTierCount)"
                         : "Débloquer la piste premium (💎 \(MetaStore.premiumPassPrice))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Team.purple.color.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func prismPackCell(_ pack: PrismPack) -> some View {
        Button {
            meta.grantPrisms(pack.amount)
            prismPack = pack
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "3DB8F5"))
                Text("\(pack.amount)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(pack.priceLabel)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(hex: "3DB8F5").opacity(0.4), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        MenuBackground()
        ShopTabView(onShowOdds: {}, onOpenSeason: {})
    }
}
