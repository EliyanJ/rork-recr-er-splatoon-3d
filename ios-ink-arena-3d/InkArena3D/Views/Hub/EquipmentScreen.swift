import SwiftUI

/// Écran "ÉQUIPEMENT" — mise en page arcade dense : rail de catégories à
/// gauche (Arme / Gadget / Skin), grille de tuiles au centre avec cadre de
/// rareté, pastille de niveau de maîtrise et bandeau « Équipé », fiche
/// chiffrée à droite. Toutes les valeurs affichées sont dérivées des
/// statistiques réelles des armes — aucune donnée inventée, aucun impact
/// gameplay.
struct EquipmentScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private enum SubTab: String, CaseIterable, Identifiable {
        case weapons, gadgets, skins

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weapons: "Arme"
            case .gadgets: "Gadget"
            case .skins: "Skin"
            }
        }

        var icon: String {
            switch self {
            case .weapons: "scope"
            case .gadgets: "burst.fill"
            case .skins: "paintbrush.fill"
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
            HStack(alignment: .top, spacing: 9 * scale) {
                categoryRail(scale: scale)
                    .frame(width: 58 * scale)

                VStack(spacing: 7 * scale) {
                    if subTab == .skins {
                        weaponFilterStrip(scale: scale)
                    }
                    itemGrid(scale: scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                detailPanel(scale: scale)
                    .frame(width: 168 * scale)
            }
        }
    }

    // MARK: - Rail de catégories (gauche)

    private func categoryRail(scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ForEach(SubTab.allCases) { item in
                Button {
                    subTab = item
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 3 * scale) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15 * scale, weight: .black))
                        Text(item.title.uppercased())
                            .font(.system(size: 8 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(subTab == item ? .black : .white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(subTab == item ? Color.menuAccent : Color.menuPanel.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(subTab == item ? .clear : .white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Filtre d'arme (onglet Skin)

    private func weaponFilterStrip(scale: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5 * scale) {
                ForEach(WeaponType.allCases) { weapon in
                    Button {
                        skinFilterWeapon = weapon
                        selectedSkin = nil
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Text(weapon.displayName.uppercased())
                            .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(skinFilterWeapon == weapon ? .black : .white.opacity(0.75))
                            .lineLimit(1)
                            .padding(.horizontal, 9 * scale)
                            .padding(.vertical, 5 * scale)
                            .background(Capsule().fill(skinFilterWeapon == weapon ? Color.menuAccent : .white.opacity(0.1)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .contentMargins(.horizontal, 2)
    }

    // MARK: - Grille centrale

    @ViewBuilder
    private func itemGrid(scale: CGFloat) -> some View {
        let columns = [GridItem(.adaptive(minimum: 74 * scale), spacing: 7 * scale)]
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 7 * scale) {
                switch subTab {
                case .weapons:
                    ForEach(WeaponType.allCases) { weapon in
                        weaponTile(weapon, scale: scale)
                    }
                    ForEach(0..<3, id: \.self) { index in
                        lockedTile(requirement: "Niv.\(8 + index * 5)", scale: scale)
                    }
                case .gadgets:
                    ForEach(GadgetType.allCases) { gadget in
                        gadgetTile(gadget, scale: scale)
                    }
                    ForEach(0..<4, id: \.self) { index in
                        lockedTile(requirement: "Niv.\(6 + index * 4)", scale: scale)
                    }
                case .skins:
                    ForEach(WeaponSkinCatalog.skins(for: skinFilterWeapon)) { skin in
                        skinTile(skin, scale: scale)
                    }
                }
            }
            .padding(.bottom, 4)
        }
    }

    /// Tuile d'arme : icône, nom, niveau de maîtrise réel et bandeau équipé.
    private func weaponTile(_ weapon: WeaponType, scale: CGFloat) -> some View {
        let rarity = displayRarity(weapon)
        let isEquipped = profile.selectedWeapon == weapon
        let level = meta.masteryLevel(for: weapon)
        let skinTint = meta.equippedSkinColorHex(for: weapon).map { Color(hex: $0) }

        return Button {
            selectedWeapon = weapon
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 3 * scale) {
                    Image(systemName: weapon.iconSystemName)
                        .font(.system(size: 22 * scale, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [skinTint ?? .white, (skinTint ?? rarity.color).opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: rarity.color.opacity(0.6), radius: 5)
                    Text(weapon.displayName)
                        .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)

                ArcadeLevelChip(level: level, scale: scale)
                    .padding(4 * scale)
            }
            .frame(height: 62 * scale)
            .background(
                ArcadeTileBackground(tint: rarity.color, isSelected: selectedWeapon == weapon)
            )
            .overlay(alignment: .bottom) {
                if isEquipped {
                    ArcadeEquippedBanner(scale: scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        }
        .buttonStyle(PressableStyle())
    }

    private func gadgetTile(_ gadget: GadgetType, scale: CGFloat) -> some View {
        let isEquipped = meta.equippedGadget == gadget
        return Button {
            selectedGadget = gadget
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3 * scale) {
                Image(systemName: gadget.iconSystemName)
                    .font(.system(size: 22 * scale, weight: .black))
                    .foregroundStyle(Team.orange.color)
                    .shadow(color: Team.orange.color.opacity(0.6), radius: 5)
                Text(gadget.displayName)
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .frame(height: 62 * scale)
            .background(ArcadeTileBackground(tint: Team.orange.color, isSelected: selectedGadget == gadget))
            .overlay(alignment: .bottom) {
                if isEquipped {
                    ArcadeEquippedBanner(scale: scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
        }
        .buttonStyle(PressableStyle())
    }

    private func skinTile(_ skin: WeaponSkin, scale: CGFloat) -> some View {
        let owned = meta.ownsSkin(skin)
        let isEquipped = meta.equippedSkin(for: skin.weapon)?.id == skin.id
        return Button {
            selectedSkin = skin
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 3 * scale) {
                    Image(systemName: skin.weapon.iconSystemName)
                        .font(.system(size: 22 * scale, weight: .black))
                        .foregroundStyle(Color(hex: skin.colorHex))
                        .shadow(color: Color(hex: skin.colorHex).opacity(0.7), radius: 5)
                    Text(skin.name)
                        .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 4)

                if !owned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9 * scale, weight: .black))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(5 * scale)
                }
            }
            .frame(height: 62 * scale)
            .background(
                ArcadeTileBackground(
                    tint: skin.rarity.color,
                    isSelected: selectedSkin?.id == skin.id,
                    isLocked: !owned
                )
            )
            .overlay(alignment: .bottom) {
                if isEquipped {
                    ArcadeEquippedBanner(scale: scale)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ArcadeKit.tileCorner))
            .opacity(owned ? 1 : 0.75)
        }
        .buttonStyle(PressableStyle())
    }

    /// Emplacement à débloquer — silhouette grise avec palier requis.
    private func lockedTile(requirement: String, scale: CGFloat) -> some View {
        ZStack {
            ArcadeTileBackground(tint: .gray, isLocked: true)
            Image(systemName: "questionmark")
                .font(.system(size: 22 * scale, weight: .black))
                .foregroundStyle(.white.opacity(0.1))
            ArcadeLockOverlay(requirement: requirement, scale: scale)
        }
        .frame(height: 62 * scale)
    }

    // MARK: - Fiche de détail (droite)

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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: "1A1B24").opacity(0.95), Color(hex: "0D0E14").opacity(0.95)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private func weaponDetail(scale: CGFloat) -> some View {
        let rarity = displayRarity(selectedWeapon)
        let skinTint = meta.equippedSkinColorHex(for: selectedWeapon).map { Color(hex: $0) }
        return VStack(spacing: 5 * scale) {
            // Vignette de l'arme.
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [rarity.color.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 34 * scale))
                Image(systemName: selectedWeapon.iconSystemName)
                    .font(.system(size: 30 * scale, weight: .black))
                    .foregroundStyle(
                        LinearGradient(colors: [skinTint ?? .white, (skinTint ?? rarity.color).opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
            }
            .frame(height: 52 * scale)

            Text(selectedWeapon.displayName.uppercased())
                .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(rarity.displayName.uppercased())
                .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(rarity.color)

            Divider().overlay(.white.opacity(0.15))

            // Statistiques chiffrées, dérivées des vraies valeurs de l'arme.
            VStack(spacing: 5 * scale) {
                statLine(icon: "burst.fill", label: "Efficacité", value: selectedWeapon.powerStat, tint: Color(hex: "FF6A4D"), scale: scale)
                statLine(icon: "timer", label: "Cadence", value: selectedWeapon.rateStat, tint: Color(hex: "FFC400"), scale: scale)
                statLine(icon: "drop.fill", label: "Réserve", value: selectedWeapon.inkCapacityStat, tint: Color(hex: "3DB8F5"), scale: scale)
                statLine(icon: "figure.run", label: "Mobilité", value: selectedWeapon.mobilityStat, tint: Color(hex: "35C46A"), scale: scale)
                statLine(icon: "scope", label: "Portée", value: selectedWeapon.rangeStat, tint: Color(hex: "9A3DF5"), scale: scale)
            }

            // Étiquettes de comportement, lues sur les vraies constantes.
            HStack(spacing: 4 * scale) {
                behaviourChip(selectedWeapon == .charger ? "Charge" : "Automatique", scale: scale)
                behaviourChip(String(format: "%.0f dgts", Double(selectedWeapon.damagePerHit)), scale: scale)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)

            equipButton(isEquipped: profile.selectedWeapon == selectedWeapon, scale: scale) {
                profile.selectedWeapon = selectedWeapon
            }
        }
    }

    private func statLine(icon: String, label: String, value: Double, tint: Color, scale: CGFloat) -> some View {
        VStack(spacing: 2 * scale) {
            ArcadeStatRow(icon: icon, label: label, value: Int((value * 100).rounded()), tint: tint, scale: scale)
            ArcadeStatBar(value: value, tint: tint, scale: scale)
        }
    }

    private func behaviourChip(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 8 * scale, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 3 * scale)
            .background(Capsule().fill(.white.opacity(0.1)))
    }

    private func gadgetDetail(scale: CGFloat) -> some View {
        VStack(spacing: 6 * scale) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Team.orange.color.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 34 * scale))
                Image(systemName: selectedGadget.iconSystemName)
                    .font(.system(size: 30 * scale, weight: .black))
                    .foregroundStyle(Team.orange.color)
            }
            .frame(height: 52 * scale)

            Text(selectedGadget.displayName.uppercased())
                .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)

            Divider().overlay(.white.opacity(0.15))

            Text(selectedGadget.effectDescription)
                .font(.system(size: 8.5 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.75)

            VStack(spacing: 5 * scale) {
                ArcadeStatRow(icon: "clock.fill", label: "Recharge", value: Int(selectedGadget.cooldown), tint: Color(hex: "FFC400"), scale: scale)
                ArcadeStatRow(icon: "drop.fill", label: "Coût encre", value: Int(selectedGadget.inkCost), tint: Color(hex: "3DB8F5"), scale: scale)
            }

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
            VStack(spacing: 6 * scale) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: skin.colorHex).opacity(0.5), .clear], center: .center, startRadius: 2, endRadius: 34 * scale))
                    Image(systemName: skin.weapon.iconSystemName)
                        .font(.system(size: 30 * scale, weight: .black))
                        .foregroundStyle(Color(hex: skin.colorHex))
                }
                .frame(height: 52 * scale)

                Text(skin.name.uppercased())
                    .font(.system(size: 12.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)

                Text(skin.rarity.displayName.uppercased())
                    .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(skin.rarity.color)

                Divider().overlay(.white.opacity(0.15))

                Text(owned ? "Variante cosmétique — aucun effet sur les statistiques." : "À débloquer en boutique ou dans les coffres.")
                    .font(.system(size: 8.5 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)

                equipButton(isEquipped: isEquipped, disabled: !owned, scale: scale) {
                    guard owned else { return }
                    meta.equipSkin(skin)
                }
            }
        } else {
            VStack(spacing: 6 * scale) {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 26 * scale, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
                Text("Choisis un skin dans la grille")
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func equipButton(isEquipped: Bool, disabled: Bool = false, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Text(disabled ? "VERROUILLÉ" : (isEquipped ? "ÉQUIPÉ ✓" : "ÉQUIPER"))
                .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8 * scale)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(disabled ? Color.gray.opacity(0.4) : (isEquipped ? ArcadeKit.cash : Team.orange.color))
                )
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }

    // MARK: - Classement cosmétique dérivé des statistiques réelles

    /// Palier d'affichage d'une arme, calculé à partir de sa puissance et de
    /// sa portée réelles — sert uniquement à colorer le cadre de la tuile.
    private func displayRarity(_ weapon: WeaponType) -> Rarity {
        let score = (weapon.powerStat + weapon.rangeStat) / 2
        switch score {
        case ..<0.4: return .common
        case ..<0.6: return .rare
        case ..<0.8: return .epic
        default: return .legendary
        }
    }
}

#Preview {
    EquipmentScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
