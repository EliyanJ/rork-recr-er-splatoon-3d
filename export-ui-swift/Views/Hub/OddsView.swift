import SwiftUI

/// Probabilités d'obtention — table exacte des taux de drop par rareté pour
/// chaque type de coffre. Obligatoire avant tout achat de coffre en argent
/// réel (App Store guideline 3.1.1) ; accessible depuis la Boutique.
struct OddsView: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("PROBABILITÉS D'OBTENTION")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 20)

                    Text("Chaque récompense d'un coffre est tirée selon les taux ci-dessous. Ces probabilités sont identiques que le coffre soit gagné en jouant ou acheté.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))

                    ForEach(ChestType.allCases) { chest in
                        chestCard(chest)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
    }

    private func chestCard(_ chest: ChestType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: chest.iconSystemName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(chest.tint)
                Text(chest.displayName.uppercased())
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(chest.rewardCount) récompenses")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }

            ForEach(chest.odds.filter { $0.percent > 0 }, id: \.rarity.rawValue) { entry in
                HStack(spacing: 10) {
                    Text(entry.rarity.displayName)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.rarity.color)
                        .frame(width: 90, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.1))
                            Capsule()
                                .fill(entry.rarity.color)
                                .frame(width: max(4, geo.size.width * Double(entry.percent) / 100))
                        }
                    }
                    .frame(height: 8)
                    Text("\(entry.percent)%")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(chest.tint.opacity(0.4), lineWidth: 1.5)
        )
    }
}

#Preview {
    OddsView()
}
