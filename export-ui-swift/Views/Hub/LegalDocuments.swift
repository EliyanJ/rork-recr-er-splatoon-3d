import SwiftUI

/// Identifies which legal text is being displayed (Terms of Use / Privacy
/// Policy). Kept lightweight — the game collects no personal data and has no
/// tracking SDK, so a blocking first-launch consent screen isn't required;
/// these documents stay accessible from Settings for transparency instead.
enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Conditions d'utilisation"
        case .privacy: "Politique de confidentialité"
        }
    }

    var body: String {
        switch self {
        case .terms:
            """
            Bienvenue dans Splash !

            1. Splash est un jeu de tir en arène fourni tel quel, à des fins de divertissement.

            2. Vous vous engagez à utiliser le jeu de manière loyale : pas de triche, pas d'exploitation de bugs, pas de comportement nuisible envers les autres joueurs.

            3. Votre progression (pseudo, trophées, pièces, personnalisation) est stockée localement sur votre appareil.

            4. Le contenu du jeu (personnages, arènes, sons) peut évoluer à tout moment via des mises à jour.

            5. L'éditeur ne peut être tenu responsable des pertes de progression liées à la suppression de l'application ou au changement d'appareil.

            En jouant, vous acceptez l'intégralité de ces conditions.
            """
        case .privacy:
            """
            Politique de confidentialité de Splash

            1. Données collectées : Splash ne collecte aucune donnée personnelle. Votre pseudo et votre progression restent stockés localement sur votre appareil.

            2. Aucun suivi publicitaire : le jeu n'intègre aucun SDK de tracking et n'affiche aucune publicité ciblée.

            3. Aucun partage : aucune donnée n'est transmise à des tiers.

            4. Suppression : désinstaller l'application supprime l'intégralité des données locales du jeu.

            Pour toute question, contactez le support depuis la fiche App Store du jeu.
            """
        }
    }
}

/// Scrollable in-app legal text presented as a sheet from Settings.
struct LegalTextSheet: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document.body)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}
