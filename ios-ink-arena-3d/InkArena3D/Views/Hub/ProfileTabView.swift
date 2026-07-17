import SwiftUI

/// Profil — identité (pseudo, niveau, titre sélectionnable), statistiques
/// clés, historique des derniers matchs (détail en modal), badges/titres et
/// accès à la galerie de skins + au vestiaire 3D.
struct ProfileTabView: View {
    @State private var meta = MetaStore.shared
    @State private var profile = ProfileStore.shared
    @State private var showTitlePicker = false
    @State private var inspectedMatch: MatchRecord?
    @State private var showLockerRoom = false
    @State private var showNameEditor = false
    @State private var showAvatarPicker = false
    @State private var nameDraft = ""

    private var winRatio: String {
        guard profile.matchesPlayed > 0 else { return "—" }
        return String(format: "%.0f%%", Double(profile.wins) / Double(profile.matchesPlayed) * 100)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header
                statsRow
                historyCard
                badgesCard
                galleryLinks
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $showTitlePicker) {
            titlePicker.presentationDetents([.medium])
        }
        .sheet(item: $inspectedMatch) { record in
            matchDetail(record).presentationDetents([.medium])
        }
        .fullScreenCover(isPresented: $showLockerRoom) {
            LockerRoomView(onBack: { showLockerRoom = false })
        }
        .sheet(isPresented: $showAvatarPicker) {
            avatarPicker.presentationDetents([.medium])
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

    private var header: some View {
        VStack(spacing: 8) {
            Button {
                showAvatarPicker = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                ZStack {
                    Circle()
                        .fill(profile.accentColor.opacity(0.9))
                        .frame(width: 72, height: 72)
                    Image(systemName: profile.avatarIcon)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text("\(meta.accountLevel)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(6)
                        .background(Circle().fill(.yellow))
                }
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white, Team.orange.color)
                        .background(Circle().fill(.white))
                        .offset(x: 2, y: -2)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Text(profile.playerName)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Button {
                    nameDraft = profile.playerName
                    showNameEditor = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7), .white.opacity(0.15))
                }
                .buttonStyle(.plain)
            }

            Button {
                showTitlePicker = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5) {
                    Text(meta.selectedTitle.name)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .black))
                }
                .foregroundStyle(Team.orange.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.45)))
                .overlay(Capsule().stroke(Team.orange.color.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule()
                        .fill(Team.orange.color)
                        .frame(width: max(6, geo.size.width * meta.accountLevelProgress))
                }
            }
            .frame(width: 190, height: 7)
            Text("Niveau \(meta.accountLevel) / \(MetaStore.maxLevel)")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            statItem(value: "\(profile.wins)", label: "Victoires", color: Team.orange.color)
            statItem(value: winRatio, label: "Ratio", color: .white)
            statItem(value: "\(meta.totalKills)", label: "Élims", color: .pink)
            statItem(value: "\(profile.tilesPainted) m²", label: "Couverture", color: Team.purple.color)
        }
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)))
    }

    // MARK: Historique

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("DERNIERS MATCHS", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            if meta.matchHistory.isEmpty {
                Text("Aucun match joué pour l'instant — lance ta première partie !")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.vertical, 8)
            } else {
                ForEach(meta.matchHistory.prefix(6)) { record in
                    Button {
                        inspectedMatch = record
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: record.isWin ? "trophy.fill" : (record.outcome == "draw" ? "equal.circle.fill" : "xmark.circle.fill"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(record.isWin ? .yellow : (record.outcome == "draw" ? .white : Team.purple.color))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.outcomeLabel + (record.isMVP ? " · MVP 🏆" : ""))
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(record.mapName)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            Spacer()
                            Text("+\(record.xpEarned) XP")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(Team.orange.color)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
    }

    private func matchDetail(_ record: MatchRecord) -> some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("\(record.outcomeLabel.uppercased()) — \(record.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(record.isWin ? Team.orange.color : .white)

                VStack(alignment: .leading, spacing: 10) {
                    detailRow("Map", record.mapName)
                    detailRow("Couverture", "\(record.orangePercent)% vous · \(record.purplePercent)% rivaux")
                    detailRow("Éliminations", "\(record.kills)")
                    detailRow("Morts", "\(record.deaths)")
                    detailRow("MVP", record.isMVP ? "Oui 🏆" : "Non")
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

    // MARK: Badges / titres

    private var badgesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("TITRES DÉBLOQUÉS", systemImage: "rosette")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(TitleCatalog.all) { title in
                    let owned = meta.ownedTitles.contains(title)
                    HStack(spacing: 6) {
                        Image(systemName: owned ? "checkmark.seal.fill" : "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(owned ? .yellow : .white.opacity(0.3))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(title.name)
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .foregroundStyle(owned ? .white : .white.opacity(0.4))
                                .lineLimit(1)
                            Text(title.requirement)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(owned ? 0.09 : 0.04)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.06)))
    }

    // MARK: Avatar

    private var avatarPicker: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
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
                            .overlay(
                                Circle().stroke(isSelected ? profile.accentColor : .clear, lineWidth: 2.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
            }
        }
    }

    // MARK: Galerie

    private var galleryLinks: some View {
        Button {
            showLockerRoom = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(profile.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VESTIAIRE & GALERIE")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Tenues, accessoires et couleur d'accent en 3D")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(profile.accentColor.opacity(0.5), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var titlePicker: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()
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
                                            .foregroundStyle(Team.orange.color)
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
    ZStack {
        MenuBackground()
        ProfileTabView()
    }
}
