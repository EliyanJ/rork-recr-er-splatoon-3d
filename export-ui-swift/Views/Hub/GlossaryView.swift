import SwiftUI

/// Comment jouer / Glossaire — fiches empilées filtrables : peinture,
/// furtivité, armes, gadgets et mécaniques de terrain.
struct GlossaryView: View {
    private enum Filter: String, CaseIterable {
        case all, paint, weapons, gadgets, terrain

        var title: String {
            switch self {
            case .all: "Tout"
            case .paint: "Peinture"
            case .weapons: "Armes"
            case .gadgets: "Gadgets"
            case .terrain: "Terrain"
            }
        }
    }

    private struct Entry: Identifiable {
        let id: String
        let filter: Filter
        let icon: String
        let title: String
        let text: String
    }

    @State private var filter: Filter = .all

    private var entries: [Entry] {
        var list: [Entry] = [
            Entry(
                id: "paint",
                filter: .paint,
                icon: "paintpalette.fill",
                title: "La Peinture",
                text: "Couvre le sol de ta couleur : tu avances plus vite dessus, l'ennemi est ralenti. L'équipe qui couvre le plus de terrain à la fin gagne."
            ),
            Entry(
                id: "dive",
                filter: .paint,
                icon: "water.waves",
                title: "La Nage (forme éponge)",
                text: "Plonge dans ta propre encre pour filer à toute vitesse, te camoufler et recharger ta jauge d'encre bien plus vite."
            ),
            Entry(
                id: "stealth",
                filter: .paint,
                icon: "eye.slash.fill",
                title: "Furtivité",
                text: "En nage dans ta couleur, tu deviens discret et tu recharges plus vite. Reste sur ton pigment pour surprendre l'adversaire."
            ),
        ]
        for weapon in WeaponType.allCases {
            list.append(Entry(
                id: "w_\(weapon.rawValue)",
                filter: .weapons,
                icon: weapon.iconSystemName,
                title: weapon.displayName,
                text: weapon.tagline + " Chaque arme a sa propre mobilité — le Lance-Seau est lent, les Double Pistolets très rapides."
            ))
        }
        for gadget in GadgetType.allCases {
            list.append(Entry(
                id: "g_\(gadget.rawValue)",
                filter: .gadgets,
                icon: gadget.iconSystemName,
                title: gadget.displayName,
                text: gadget.effectDescription + " Un seul gadget équipé à la fois — change-le dans l'Armurerie."
            ))
        }
        list.append(contentsOf: [
            Entry(
                id: "walls",
                filter: .terrain,
                icon: "square.stack.3d.up.fill",
                title: "Murs peignables & escalade",
                text: "Peins un mur avec ton équipe : une fois assez couvert, tu peux le grimper en poussant dessus. Raccourcis verticaux garantis."
            ),
            Entry(
                id: "zipline",
                filter: .terrain,
                icon: "cable.connector",
                title: "Tyroliennes",
                text: "Saute vers un point d'accroche pour traverser l'arène en hauteur — tu peux tirer pendant la glissade."
            ),
            Entry(
                id: "water",
                filter: .terrain,
                icon: "drop.degreesign.fill",
                title: "Eau",
                text: "Les canaux se traversent à pied (lent, exposé) ou en forme éponge (plus rapide). Un raccourci risqué, pas un mur."
            ),
        ])
        return list
    }

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.2).ignoresSafeArea()

            VStack(spacing: 12) {
                Text("COMMENT JOUER")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases, id: \.rawValue) { item in
                            Button {
                                filter = item
                            } label: {
                                Text(item.title.uppercased())
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(filter == item ? .black : .white.opacity(0.75))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(filter == item ? Team.orange.color : .white.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(entries.filter { filter == .all || $0.filter == filter }) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.icon)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Team.orange.color)
                                    .frame(width: 38, height: 38)
                                    .background(Circle().fill(.white.opacity(0.08)))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                        .font(.system(size: 14, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(entry.text)
                                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.65))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

#Preview {
    GlossaryView()
}
