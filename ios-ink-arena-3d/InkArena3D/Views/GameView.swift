import RealityKit
import SwiftUI

/// Hosts the RealityKit arena plus the touch controls and HUD overlays.
/// The loading overlay (lore + countdown) plays OVER the arena while it
/// builds in the background, so there is no frozen dead time anymore.
struct GameView: View {
    let onMatchEnd: (MatchResult) -> Void
    /// Fired when the player quits mid-match from Settings — no results
    /// screen, the caller routes straight back to the Hub.
    let onQuit: () -> Void

    @State private var controller: GameController
    @State private var showIntro = true

    init(
        weapon: WeaponType,
        training: Bool = false,
        onMatchEnd: @escaping (MatchResult) -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onMatchEnd = onMatchEnd
        self.onQuit = onQuit
        _controller = State(initialValue: GameController(weapon: weapon, training: training))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.08, blue: 0.2),
                    Color(red: 0.16, green: 0.1, blue: 0.32),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RealityView { content in
                content.camera = .virtual
                await controller.setup(content: content)
            }
            .ignoresSafeArea()

            // Controls and HUD only exist once the match is live.
            if controller.isMatchLive {
                ControlsOverlay(controller: controller)
                GameHUDView(controller: controller)
            }

            if showIntro {
                MatchIntroOverlay(isSceneReady: controller.isSceneReady) {
                    controller.beginMatch()
                    AudioService.shared.playMusic()
                    AudioService.shared.playAmbience()
                    withAnimation(.easeOut(duration: 0.5)) {
                        showIntro = false
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: controller.isMatchLive)
        .onAppear {
            controller.onMatchEnd = { result in
                onMatchEnd(result)
            }
            controller.onQuit = {
                onQuit()
            }
        }
        .onDisappear {
            AudioService.shared.stopMusic()
            AudioService.shared.stopAmbience()
            AudioService.shared.stopLobbyMusic()
        }
    }
}
