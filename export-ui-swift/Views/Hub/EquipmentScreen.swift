import SwiftUI

/// Écran "ÉQUIPEMENT" — sous-onglets Armes / Gadgets / Skins, liste à gauche
/// et fiche détaillée à droite (stats, description, bouton équiper).
/// Réutilise les données réelles de MetaStore/ProfileStore.
/// Contrainte : tout le contenu tient sans scroll.
struct EquipmentScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private enum SubTab: String, CaseIterable {
        case weapons, gadgets, skins

        var title: String {
            switch self {
            case .weapons: "Armes"
            case .gadgets: "Gadgets"
            case .skins: "Skins"
            }
        }
    }

    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared
    @State private var subTab: SubTab = .weapons
    @State private var selectedWeapon: WeaponType = ProfileStore.shared.selectedWeapon
    @State private var selectedGadget: GadgetType = MetaStore.shared.equippedGadget
    @State private var skinFilterWeapon: WeaponType = ProfileStore.shared.selectedWeapon
    @State private var selectedSkin: WeaponSkin?

    var body: some View {
        MenuScreenScaffold(
            title: "ÉQUIPEMENT",
            activeTab: .armory,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            VStack(spacing: 8 * scale) {
                subTabPicker(scale: scale)

                HStack(alignment: .top, spacing: 10 * scale) {
                    itemList(scale: scale)
                        .frame(width: 118 * scale)

                    detailPanel(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func subTabPicker(scale: CGFloat) -> some View {
        HStack(spacing: 6 * scale) {
            ForEach(SubTab.allCases, id: \.rawValue) { item in
                Button {
                    subTab = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(item.title.uppercased())
                        .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(subTab == item ? .black : .white.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7 * scale)
                        .background(Capsule().fill(subTab == item ? Color.menuAccent : .white.opacity(0.1)))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder
    private func itemList(scale: CGFloat) -> some View {
        VStack(spacing: 5 * scale) {
            switch subTab {
            case .weapons:
                ForEach(WeaponType.allCases) { weapon in
                    listRow(
                        icon: weapon.iconSystemName,
                        title: weapon.displayName,
                        isSelected: selectedWeapon == weapon,
                        isEquipped: profile.selectedWeapon == weapon,
                        scale: scale
                    ) { selectedWeapon = weapon }
                }
            case .gadgets:
                ForEach(GadgetType.allCases) { gadget in
                    listRow(
                        icon: gadget.iconSystemName,
                        title: gadget.displayName,
                        isSelected: selectedGadget == gadget,
                        isEquipped: meta.equippedGadget == gadget,
                        scale: scale
                    ) { selectedGadget = gadget }
                }
            case .skins:
                Menu {
                    ForEach(WeaponType.allCases) { weapon in
                        Button(weapon.displayName) { skinFilterWeapon = weapon }
                    }
                } label: {
                    HStack {
                        Text(skinFilterWeapon.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Team.orange.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(WeaponSkinCatalog.skins(for: skinFilterWeapon)) { skin in
                    listRow(
                        icon: skin.weapon.iconSystemName,
                        title: skin.name,
                        isSelected: selectedSkin?.id == skin.id,
                        isEquipped: meta.equippedSkin(for: skin.weapon)?.id == skin.id,
                        tint: Color(hex: skin.colorHex),
                        scale: scale
                    ) { selectedSkin = skin }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func listRow(
        icon: String,
        title: String,
        isSelected: Bool,
        isEquipped: Bool,
        tint: Color = Team.orange.color,
        scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7 * scale) {
                Image(systemName: icon)
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 18 * scale)
                Text(title)
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if isEquipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .foregroundStyle(Team.orange.color)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6 * scale)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(isSelected ? 0.16 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? tint.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func detailPanel(scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            switch subTab {
            case .weapons: weaponDetail(scale: scale)
            case .gadgets: gadgetDetail(scale: scale)
            case .skins: skinDetail(scale: scale)
            }
        }
        .padding(10 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.05)))
    }

    private func weaponDetail(scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            Image(systemName: selectedWeapon.iconSystemName)
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(
                    LinearGradient(colors: [Team.orange.color, .white.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                )
            Text(selectedWeapon.displayName.uppercased())
                .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(selectedWeapon.tagline)
                .font(.system(size: 8.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            RadarChartView(
                axes: selectedWeapon.radarAxes,
                accent: Team.orange.color,
                centerIcon: selectedWeapon.iconSystemName
            )
            .frame(maxWidth: 220 * scale)
            .padding(.vertical, 2 * scale)

            Spacer(minLength: 0)

            equipButton(isEquipped: profile.selectedWeapon == selectedWeapon, scale: scale) {
                profile.selectedWeapon = selectedWeapon
            }
        }
    }

    private func gadgetDetail(scale: CGFloat) -> some View {
        VStack(spacing: 7 * scale) {
            Image(systemName: selectedGadget.iconSystemName)
                .font(.system(size: 26 * scale, weight: .bold))
                .foregroundStyle(Team.orange.color)
            Text(selectedGadget.displayName.uppercased())
                .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text(selectedGadget.effectDescription)
                .font(.system(size: 9 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                Label(String(format: "%.0f s", selectedGadget.cooldown), systemImage: "clock.fill")
                Label("\(Int(selectedGadget.inkCost)) encre", systemImage: "drop.fill")
            }
            .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
            .foregroundStyle(Team.orange.color)

            Spacer(minLength: 0)

            equipButton(isEquipped: meta.equippedGadget == selectedGadget, scale: scale) {
                meta.equipGadget(selectedGadget)
            }
        }
    }

    @ViewBuilder
    private func skinDetail(scale: CGFloat) -> some View {
        if let skin = selectedSkin {
            let owned = meta.ownsSkin(skin)
            let isEquipped = meta.equippedSkin(for: skin.weapon)?.id == skin.id
            VStack(spacing: 7 * scale) {
                Image(systemName: skin.weapon.iconSystemName)
                    .font(.system(size: 28 * scale, weight: .bold))
                    .foregroundStyle(Color(hex: skin.colorHex))
                Text(skin.name.uppercased())
                    .font(.system(size: 13 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(owned ? skin.rarity.displayName : "Boutique / coffres")
                    .font(.system(size: 9 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(owned ? skin.rarity.color : .white.opacity(0.5))

                Spacer(minLength: 0)

                equipButton(isEquipped: isEquipped, disabled: !owned, scale: scale) {
                    guard owned else { return }
                    meta.equipSkin(skin)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 24 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                Text("Choisis un skin dans la liste")
                    .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func equipButton(isEquipped: Bool, disabled: Bool = false, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Text(disabled ? "VERROUILLÉ" : (isEquipped ? "ÉQUIPÉ ✓" : "ÉQUIPER"))
                .font(.system(size: 12 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 8 * scale)
                .background(Capsule().fill(disabled ? Color.gray.opacity(0.4) : (isEquipped ? Color.green : Team.orange.color)))
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }
}

#Preview {
    EquipmentScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
