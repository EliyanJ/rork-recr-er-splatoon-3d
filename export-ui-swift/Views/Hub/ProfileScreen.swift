import SwiftUI

/// Écran "PROFIL" restylé — même habillage panneaux peints que les 5 écrans
/// du menu. Identité, statistiques et historique restent connectés aux
/// données réelles déjà en place ; Collection/Succès/Clan sont factices
/// (backend plus tard), comme demandé pour les autres écrans.
struct ProfileScreen: View {
    let onBack: () -> Void
    let onSelectTab: (MenuTab) -> Void
    let onSettings: () -> Void

    private struct CollectionCategory: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let owned: Int
        let total: Int
    }

    private struct Achievement: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let date: String
    }

    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared
    @State private var showTitlePicker = false
    @State private var showAvatarPicker = false
    @State private var showNameEditor = false
    @State private var inspectedMatch: MatchRecord?
    @State private var nameDraft = ""

    private let collection: [CollectionCategory] = [
        CollectionCategory(icon: "shield.lefthalf.filled", title: "Équipements", owned: 7, total: 18),
        CollectionCategory(icon: "paintbrush.fill", title: "Skins", owned: 4, total: 12),
        CollectionCategory(icon: "face.smiling.fill", title: "Émotes", owned: 2, total: 9),
    ]

    private let achievements: [Achievement] = [
        Achievement(icon: "trophy.fill", title: "Première victoire décrochée", date: "12 juin"),
        Achievement(icon: "paintpalette.fill", title: "1 000 m² d'encre étalés", date: "18 juin"),
        Achievement(icon: "bolt.fill", title: "Série de 3 victoires d'affilée", date: "3 juil."),
    ]

    private var winRatio: String {
        guard profile.matchesPlayed > 0 else { return "—" }
        return String(format: "%.0f%%", Double(profile.wins) / Double(profile.matchesPlayed) * 100)
    }

    /// Meilleure série de victoires consécutives — calculée à partir de
    /// l'historique réel (les entrées les plus récentes sont en tête).
    private var bestStreak: Int {
        var best = 0
        var current = 0
        for record in meta.matchHistory.reversed() {
            if record.isWin {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var body: some View {
        MenuScreenScaffold(
            title: "PROFIL",
            activeTab: .home,
            pigments: meta.pigments,
            prisms: meta.prisms,
            onBack: onBack,
            onSelectTab: onSelectTab,
            onSettings: onSettings
        ) { scale in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10 * scale) {
                    identityCard(scale: scale)
                    statsRow(scale: scale)
                    historyCard(scale: scale)
                    collectionCard(scale: scale)
                    achievementsCard(scale: scale)
                    clanBanner(scale: scale)
                }
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $showTitlePicker) {
            titlePicker.presentationDetents([.medium])
        }
        .sheet(isPresented: $showAvatarPicker) {
            avatarPicker.presentationDetents([.medium])
        }
        .sheet(item: $inspectedMatch) { record in
            matchDetail(record).presentationDetents([.medium])
        }
        .alert("Modifier le pseudo", isPresented: $showNameEditor) {
            TextField("Pseudo", text: $nameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                profile.playerName = String(trimmed.prefix(14))
                profile.hasSetName = true
            }
        }
    }

    // MARK: Identité

    private func identityCard(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {
            Button {
                showAvatarPicker = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack {
                    Circle().fill(profile.accentColor.opacity(0.9))
                    Image(systemName: profile.avatarIcon)
                        .font(.system(size: 30 * scale, weight: .black))
                        .foregroundStyle(.white)
                }
                .frame(width: 68 * scale, height: 68 * scale)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(meta.accountLevel)")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(5)
                        .background(Circle().fill(.menuAccent))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .foregroundStyle(.white, Team.orange.color)
                        .background(Circle().fill(.white))
                        .offset(x: 2, y: -2)
                }
            }
            .buttonStyle(PressableStyle())

            HStack(spacing: 6) {
                Text(profile.playerName)
                    .font(.system(size: 18 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Button {
                    nameDraft = profile.playerName
                    showNameEditor = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 16 * scale, weight: .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }

            Button {
                showTitlePicker = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "rosette")
                        .font(.system(size: 9 * scale, weight: .black))
                    Text(meta.selectedTitle.name.uppercased())
                        .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8 * scale, weight: .black))
                }
                .foregroundStyle(.menuAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.black.opacity(0.5)))
                .overlay(Capsule().stroke(Color.menuAccent.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(Color.menuAccent)
                            .frame(width: max(6, geo.size.width * meta.accountLevelProgress))
                    }
                }
                .frame(height: 7 * scale)

                Text("Niveau \(meta.accountLevel) / \(MetaStore.maxLevel)")
                    .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(width: 180 * scale)
        }
        .padding(.vertical, 12 * scale)
        .frame(maxWidth: .infinity)
        .background(PaintedPanel(skew: 4).fill(Color.menuPanel.opacity(0.88)))
        .overlay(PaintedPanel(skew: 4).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: Stats

    private func statsRow(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            statItem(value: "\(profile.wins)", label: "Victoires", color: .menuAccent, scale: scale)
            statItem(value: "\(bestStreak)", label: "Meilleure série", color: Color(hex: "35C46A"), scale: scale)
            statItem(value: "\(meta.totalKills)", label: "Éliminations", color: Color(hex: "FF2E8A"), scale: scale)
            statItem(value: "\(profile.matchesPlayed)", label: "Parties jouées", color: .white, scale: scale)
        }
    }

    private func statItem(value: String, label: String, color: Color, scale: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16 * scale, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.system(size: 8 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9 * scale)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.07)))
    }

    // MARK: Historique

    private func historyCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Label("DERNIERS MATCHS", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            if meta.matchHistory.isEmpty {
                Text("Aucun match joué pour l'instant — lance ta première partie !")
                    .font(.system(size: 11 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 6)
            } else {
                ForEach(meta.matchHistory.prefix(4)) { record in
                    Button {
                        inspectedMatch = record
                    } label: {
                        HStack(spacing: 9 * scale) {
                            Image(systemName: record.isWin ? "trophy.fill" : (record.outcome == "draw" ? "equal.circle.fill" : "xmark.circle.fill"))
                                .font(.system(size: 12 * scale, weight: .bold))
                                .foregroundStyle(record.isWin ? .menuAccent : (record.outcome == "draw" ? .white : Team.purple.color))
                                .frame(width: 18 * scale)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.outcomeLabel + (record.isMVP ? " · MVP" : ""))
                                    .font(.system(size: 11.5 * scale, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(record.mapName)
                                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Text("+\(record.xpEarned) XP")
                                .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                                .foregroundStyle(.menuAccent)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6 * scale)
                        .padding(.horizontal, 9)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12 * scale)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    private func matchDetail(_ record: MatchRecord) -> some View {
        ZStack {
            Color.menuPanel.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("\(record.outcomeLabel.uppercased()) — \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(record.isWin ? .menuAccent : .white)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Map", record.mapName)
                    detailRow("Couverture", "\(record.orangePercent)% vous · \(record.purplePercent)% rivaux")
                    detailRow("Éliminations", "\(record.kills)")
                    detailRow("Morts", "\(record.deaths)")
                    detailRow("MVP", record.isMVP ? "Oui" : "Non")
                    detailRow("XP gagné", "+\(record.xpEarned)")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.07)))
            }
            .padding(22)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    // MARK: Collection (factice)

    private func collectionCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Label("COLLECTION", systemImage: "square.grid.2x2.fill")
                .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 7 * scale) {
                ForEach(collection) { category in
                    HStack(spacing: 9 * scale) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12 * scale, weight: .bold))
                            .foregroundStyle(.menuAccent)
                            .frame(width: 20 * scale)
                        Text(category.title)
                            .font(.system(size: 11 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 78 * scale, alignment: .leading)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color(hex: "35C46A"))
                                    .frame(width: proxy.size.width * (Double(category.owned) / Double(category.total)))
                            }
                        }
                        .frame(height: 6 * scale)
                        Text("\(category.owned)/\(category.total)")
                            .font(.system(size: 9.5 * scale, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(12 * scale)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    // MARK: Succès (factice)

    private func achievementsCard(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Label("SUCCÈS RÉCENTS", systemImage: "checkmark.seal.fill")
                .font(.system(size: 10.5 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            VStack(spacing: 6 * scale) {
                ForEach(achievements) { item in
                    HStack(spacing: 9 * scale) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13 * scale, weight: .bold))
                            .foregroundStyle(Color(hex: "35C46A"))
                        Text(item.title)
                            .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(item.date)
                            .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.vertical, 6 * scale)
                    .padding(.horizontal, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
                }
            }
        }
        .padding(12 * scale)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }

    // MARK: Clan (factice)

    private func clanBanner(scale: CGFloat) -> some View {
        HStack(spacing: 10 * scale) {
            Image(systemName: "flag.2.crossed.fill")
                .font(.system(size: 17 * scale, weight: .black))
                .foregroundStyle(Color(hex: "9A3DF5"))
            VStack(alignment: .leading, spacing: 1) {
                Text("Les Encreurs Fantômes")
                    .font(.system(size: 11.5 * scale, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("24 / 30 membres")
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
            Text("BIENTÔT")
                .font(.system(size: 9 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white.opacity(0.06)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10 * scale)
        .background(PaintedPanel(skew: -3).fill(Color.menuPanel.opacity(0.8)))
        .overlay(PaintedPanel(skew: -3).stroke(.white.opacity(0.1), lineWidth: 1))
        .opacity(0.85)
    }

    // MARK: Avatar / Titre pickers

    private var avatarPicker: some View {
        ZStack {
            Color.menuPanel.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("CHOISIR UN AVATAR")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 14)], spacing: 14) {
                    ForEach(AvatarIconCatalog.all, id: \.self) { icon in
                        let isSelected = profile.avatarIcon == icon
                        Button {
                            profile.avatarIcon = icon
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? profile.accentColor : .white.opacity(0.1))
                                    .frame(width: 60, height: 60)
                                Image(systemName: icon)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(isSelected ? .black : .white)
                            }
                            .overlay(Circle().stroke(isSelected ? profile.accentColor : .clear, lineWidth: 2.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    private var titlePicker: some View {
        ZStack {
            Color.menuPanel.ignoresSafeArea()
            VStack(spacing: 10) {
                Text("CHOISIR UN TITRE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(meta.ownedTitles) { title in
                            Button {
                                meta.selectTitle(title)
                                showTitlePicker = false
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack {
                                    Text(title.name)
                                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if meta.selectedTitle.id == title.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.menuAccent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

#Preview {
    ProfileScreen(onBack: {}, onSelectTab: { _ in }, onSettings: {})
}
