//
//  ContentView.swift
//  InkArena3D
//

import SwiftUI

/// Routes between the tabbed hub client (Accueil / Armurerie / Boutique /
/// Profil), the pre-match lobby, an active match, and the end-of-match
/// results with the meta progression sequence. No blocking onboarding screen
/// — the game collects no personal data and has no tracking SDK, so a
/// native, one-tap alert is enough to surface the terms once.
struct ContentView: View {
    private enum Screen {
        case launching
        case hub
        case lobby
        /// Partie personnalisée sub-mode (Duel local / Partie classique /
        /// Match par équipes personnalisé) — the label only, same connection flow.
        case localMatch(String)
        case training
        case playing
        case results(MatchResult, MatchMetaSummary)
    }

    @State private var screen: Screen = .launching
    @State private var matchID = UUID()
    @State private var showTermsAlert = false
    @State private var legalSheet: LegalDocument?

    var body: some View {
        ZStack {
            switch screen {
            case .launching:
                LaunchLoadingView {
                    transition(to: .hub)
                    if !ProfileStore.shared.hasAcceptedTerms {
                        showTermsAlert = true
                    }
                }
                .transition(.opacity)
            case .hub:
                SplashHomeView(
                    onPlay: { transition(to: .lobby) },
                    onTraining: { transition(to: .training) },
                    onCustomMatch: { title in transition(to: .localMatch(title)) }
                )
                .transition(.opacity)
            case .lobby:
                LobbyView(
                    onReady: { startMatch() },
                    onBack: { transition(to: .hub) }
                )
                .transition(.opacity)
            case .localMatch(let title):
                LocalMatchView(
                    onStart: { _, _ in startMatch() },
                    onBack: { transition(to: .hub) },
                    modeTitle: title
                )
                .transition(.opacity)
            case .training:
                GameView(
                    weapon: ProfileStore.shared.selectedWeapon,
                    training: true,
                    onMatchEnd: { _ in },
                    onQuit: { transition(to: .hub) }
                )
                .id(matchID)
                .transition(.opacity)
            case .playing:
                GameView(
                    weapon: ProfileStore.shared.selectedWeapon,
                    onMatchEnd: { result in
                        LocalMatchService.shared.stop()
                        ProfileStore.shared.recordMatch(result: result)
                        let summary = MetaStore.shared.applyMatch(
                            result: result,
                            weapon: ProfileStore.shared.selectedWeapon
                        )
                        withAnimation(.easeInOut(duration: 0.3)) {
                            screen = .results(result, summary)
                        }
                    },
                    onQuit: {
                        // Voluntary exit — no result to record, straight to the Hub.
                        LocalMatchService.shared.stop()
                        transition(to: .hub)
                    }
                )
                .id(matchID)
                .transition(.opacity)
            case .results(let result, let summary):
                ResultsView(
                    result: result,
                    summary: summary,
                    onReplay: { transition(to: .lobby) },
                    onMenu: { transition(to: .hub) }
                )
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .alert("Conditions d'utilisation", isPresented: $showTermsAlert) {
            Button("Conditions d'utilisation") { legalSheet = .terms }
            Button("Politique de confidentialité") { legalSheet = .privacy }
            Button("Accepter") {
                ProfileStore.shared.hasAcceptedTerms = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } message: {
            Text("En utilisant Splash, vous acceptez les Conditions d'utilisation et confirmez avoir lu la Politique de confidentialité.")
        }
        .sheet(item: $legalSheet) { document in
            LegalTextSheet(document: document)
        }
    }

    private func transition(to newScreen: Screen) {
        withAnimation(.easeInOut(duration: 0.25)) {
            screen = newScreen
        }
    }

    private func startMatch() {
        matchID = UUID()
        transition(to: .playing)
    }
}

#Preview {
    ContentView()
}
