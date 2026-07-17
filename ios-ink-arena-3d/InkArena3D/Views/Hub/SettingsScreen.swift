import SwiftUI

/// Écran "PARAMÈTRES" du menu — même habillage panneaux peints que les
/// autres écrans, mais avec de vrais onglets internes pour ne pas tout
/// entasser dans une seule liste : Audio / Contrôles / Affichage / Jeu.
/// Tous les réglages listés sont réels et persistés via `ProfileStore`
/// (aucune donnée factice ici — seuls les réglages qui pilotent vraiment
/// le jeu sont affichés).
struct SettingsScreen: View {
    let onClose: () -> Void

    private enum Tab: String, CaseIterable, Identifiable {
        case audio, controls, display, game

        var id: String { rawValue }

        var title: String {
            switch self {
            case .audio: "Audio"
            case .controls: "Contrôles"
            case .display: "Affichage"
            case .game: "Jeu"
            }
        }

        var icon: String {
            switch self {
            case .audio: "speaker.wave.2.fill"
            case .controls: "gamecontroller.fill"
            case .display: "display"
            case .game: "gearshape.2.fill"
            }
        }
    }

    @State private var tab: Tab = .audio
    @State private var profile = ProfileStore.shared

    @State private var master = ProfileStore.shared.masterVolume
    @State private var music = ProfileStore.shared.musicVolume
    @State private var sfx = ProfileStore.shared.sfxVolume
    @State private var sensitivity = ProfileStore.shared.cameraSensitivity
    @State private var quality = ProfileStore.shared.graphicsQuality
    @State private var autoQuality = ProfileStore.shared.autoGraphicsQuality
    @State private var fps = ProfileStore.shared.targetFPS
    @State private var showResetConfirm = false
    @State private var didResetHUD = false

    /// Real framerate choices, capped by what the display supports.
    private var fpsOptions: [Int] {
        let maxHz = UIScreen.main.maximumFramesPerSecond
        return [30, 60, 120].filter { $0 <= max(maxHz, 60) }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            GeometryReader { screenGeo in
                MenuScreenBackdrop(size: screenGeo.size)
            }
            .ignoresSafeArea()

            GeometryReader { geo in
                let scale = menuScaleFactor(for: geo.size.height)
                VStack(spacing: 10 * scale) {
                    header(scale: scale)
                    tabBar(scale: scale)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10 * scale) {
                            switch tab {
                            case .audio: audioTab(scale: scale)
                            case .controls: controlsTab(scale: scale)
                            case .display: displayTab(scale: scale)
                            case .game: gameTab(scale: scale)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(menuBaseMargin)
            }
        }
        .alert("Réinitialiser les boutons ?", isPresented: $showResetConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Réinitialiser", role: .destructive) {
                ProfileStore.shared.resetHUDLayout()
                didResetHUD = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { didResetHUD = false }
            }
        } message: {
            Text("Les boutons de jeu (viseur, tir, saut...) reprendront leur position par défaut à la prochaine partie.")
        }
    }

    // MARK: - En-tête

    private func header(scale: CGFloat) -> some View {
        HStack(spacing: 8 * scale) {
            Button {
                onClose()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 5 * scale) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12 * scale, weight: .black))
                    Text("RETOUR")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6 * scale)
                .background(Capsule().fill(.black.opacity(0.55)))
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())

            Text("PARAMÈTRES")
                .font(.system(size: 15 * scale, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer(minLength: 4)
        }
    }

    private func tabBar(scale: CGFloat) -> some View {
        HStack(spacing: 5 * scale) {
            ForEach(Tab.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = item }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14 * scale, weight: .bold))
                        Text(item.title.uppercased())
                            .font(.system(size: 8.5 * scale, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(tab == item ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8 * scale)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tab == item ? Color.menuAccent : .clear)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(5)
        .background(Capsule().fill(.black.opacity(0.55)))
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .clipShape(Capsule())
    }

    // MARK: - Onglet Audio

    private func audioTab(scale: CGFloat) -> some View {
        sectionPanel(scale: scale) {
            volumeSlider("Général", value: $master, scale: scale) { ProfileStore.shared.masterVolume = $0 }
            volumeSlider("Musique", value: $music, scale: scale) { ProfileStore.shared.musicVolume = $0 }
            volumeSlider("Effets sonores", value: $sfx, scale: scale) { ProfileStore.shared.sfxVolume = $0 }

            Divider().background(.white.opacity(0.1))

            Toggle(isOn: Binding(
                get: { profile.soundEnabled },
                set: { profile.soundEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("COUPER TOUS LES SONS")
                        .font(.system(size: 11 * scale, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Mute rapide, sans toucher aux niveaux ci-dessus.")
                        .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .tint(.menuAccent)
        }
    }

    private func volumeSlider(_ label: String, value: Binding<Double>, scale: CGFloat, onCommit: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if !editing { onCommit(value.wrappedValue) }
            })
            .tint(.menuAccent)
        }
    }

    // MARK: - Onglet Contrôles

    private func controlsTab(scale: CGFloat) -> some View {
        sectionPanel(scale: scale) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("SENSIBILITÉ DU VISEUR")
                        .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(String(format: "%.2f×", sensitivity))
                        .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
                Slider(value: $sensitivity, in: 0.5...1.6) { editing in
                    if !editing { ProfileStore.shared.cameraSensitivity = sensitivity }
                }
                .tint(.menuAccent)
                Text("Vitesse de rotation caméra/viseur quand tu glisses le doigt à l'écran.")
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Divider().background(.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("PERSPECTIVE DE CAMÉRA")
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Picker("Perspective", selection: Binding(
                    get: { profile.cameraMode },
                    set: { profile.cameraMode = $0 }
                )) {
                    ForEach(CameraMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.iconSystemName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: profile.cameraMode) { _, _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                Text("Vue à l'épaule ou en immersion totale — appliqué dès la prochaine partie.")
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Onglet Affichage

    private func displayTab(scale: CGFloat) -> some View {
        sectionPanel(scale: scale) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("IMAGES PAR SECONDE")
                        .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("cible réelle du moteur")
                        .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Picker("FPS", selection: $fps) {
                    ForEach(fpsOptions, id: \.self) { option in
                        Text("\(option)").tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: fps) { _, newValue in
                    ProfileStore.shared.targetFPS = newValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }

            Divider().background(.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $autoQuality) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AJUSTEMENT AUTOMATIQUE")
                            .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Choisit le niveau adapté à ton appareil, et l'ajuste encore si le jeu ramène en partie.")
                            .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .tint(.menuAccent)
                .onChange(of: autoQuality) { _, newValue in
                    ProfileStore.shared.autoGraphicsQuality = newValue
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                HStack {
                    Text("QUALITÉ GRAPHIQUE")
                        .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    if autoQuality {
                        Text("Auto (\(DevicePerformance.recommendedQuality.displayName))")
                            .font(.system(size: 9.5 * scale, weight: .heavy, design: .rounded))
                            .foregroundStyle(.menuAccent)
                    }
                }
                Picker("Qualité", selection: $quality) {
                    ForEach(GraphicsQuality.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(autoQuality)
                .opacity(autoQuality ? 0.45 : 1)
                .onChange(of: quality) { _, newValue in ProfileStore.shared.graphicsQuality = newValue }
                Text(quality.subtitle)
                    .font(.system(size: 9 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Onglet Jeu

    private func gameTab(scale: CGFloat) -> some View {
        sectionPanel(scale: scale) {
            VStack(alignment: .leading, spacing: 8 * scale) {
                Text("DISPOSITION DES BOUTONS")
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Les boutons de tir/saut/grenade se repositionnent à la volée pendant une partie, depuis le menu pause. Tu peux réinitialiser leur position ici à tout moment.")
                    .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))

                Button {
                    showResetConfirm = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Label(
                        didResetHUD ? "BOUTONS RÉINITIALISÉS ✓" : "RÉINITIALISER LES BOUTONS",
                        systemImage: didResetHUD ? "checkmark.circle.fill" : "arrow.counterclockwise"
                    )
                    .font(.system(size: 12 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(didResetHUD ? Color(hex: "35C46A").opacity(0.85) : Team.orange.color.opacity(0.85)))
                }
                .buttonStyle(PressableStyle())
                .disabled(didResetHUD)
            }

            Divider().background(.white.opacity(0.1))

            HStack {
                Text("VERSION")
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(appVersion)
                    .font(.system(size: 10.5 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Panneau commun

    private func sectionPanel(scale: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14 * scale) {
            content()
        }
        .padding(14 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.menuPanel.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

#Preview {
    SettingsScreen(onClose: {})
}
