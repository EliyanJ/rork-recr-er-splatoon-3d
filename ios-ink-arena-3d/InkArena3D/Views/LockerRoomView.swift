import RealityKit
import SwiftUI

/// "Le Stade" — the locker room: skin, accessory, and accent color pickers.
/// Everything persists to the profile and is used in the next match.
struct LockerRoomView: View {
    let onBack: () -> Void

    @State private var profile = ProfileStore.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.1),
                    Color(red: 0.1, green: 0.06, blue: 0.16),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            spotlights

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
                        skinSection
                        accessorySection
                        accentSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var spotlights: some View {
        ZStack {
            Circle()
                .fill(profile.accentColor.opacity(0.3))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(y: -160)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Retour", systemImage: "chevron.left")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("LE STADE")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 90, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var skinSection: some View {
        section(title: "TENUE") {
            HStack(spacing: 12) {
                ForEach(ModelCatalog.PlayerSkin.allCases) { skin in
                    skinCard(skin)
                }
            }
        }
    }

    private func skinCard(_ skin: ModelCatalog.PlayerSkin) -> some View {
        let isSelected = profile.selectedSkin == skin
        return Button {
            profile.selectedSkin = skin
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isSelected ? .black : .white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(isSelected ? profile.accentColor : .white.opacity(0.12)))
                Text(skin.displayName)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(isSelected ? 0.14 : 0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? profile.accentColor : .white.opacity(0.14), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var accessorySection: some View {
        section(title: "ACCESSOIRE") {
            HStack(spacing: 10) {
                ForEach(PlayerAccessory.allCases) { accessory in
                    accessoryChip(accessory)
                }
            }
        }
    }

    private func accessoryChip(_ accessory: PlayerAccessory) -> some View {
        let isSelected = profile.selectedAccessory == accessory
        return Button {
            profile.selectedAccessory = accessory
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(accessory.displayName)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(isSelected ? profile.accentColor : .white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private var accentSection: some View {
        section(title: "COULEUR ACCENT") {
            HStack(spacing: 14) {
                ForEach(AccentPreset.allCases) { preset in
                    accentSwatch(preset)
                }
            }
        }
    }

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        let isSelected = profile.accentColorHex == preset.rawValue
        return Button {
            profile.accentColorHex = preset.rawValue
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Circle()
                .fill(preset.color)
                .frame(width: 40, height: 40)
                .overlay(
                    Circle().stroke(.white, lineWidth: isSelected ? 3 : 0)
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.25), lineWidth: 1)
                )
                .scaleEffect(isSelected ? 1.12 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            content()
        }
    }
}

#Preview {
    LockerRoomView(onBack: {})
}
