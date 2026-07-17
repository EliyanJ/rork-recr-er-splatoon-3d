import SwiftUI
import UIKit

/// Left virtual joystick, right-side aim drag area, jump button (above the
/// sponge/dive button), sponge/dive button, grenade button, fire button
/// (sponge sits just left of fire) and ink gauge.
struct ControlsOverlay: View {
    let controller: GameController

    @State private var knobOffset: CGSize = .zero
    @State private var lastDrag: CGSize = .zero
    @State private var diveKnobOffset: CGSize = .zero
    @State private var isDivePressed = false
    @State private var isFirePressed = false
    @State private var lastFireDrag: CGSize = .zero
    @State private var isGrenadePressed = false
    @State private var lastGrenadeDrag: CGSize = .zero
    /// True while holding the sponge/dive button AND the held finger has
    /// slid upward past `jumpChargeSlideThreshold` — the squid-surge jump is
    /// charging. Detected purely from the drag's own translation, with no
    /// cross-view geometry lookup, so it keeps working however the HUD
    /// buttons are repositioned.
    @State private var isDraggingOntoJump = false
    /// Offset of each control at the START of its current reposition drag —
    /// keeps the drag anchored so the button follows the finger 1:1 instead
    /// of compounding translations on every view refresh.
    @State private var repositionBase: [String: CGSize] = [:]

    /// Upward drag distance (in points) past which holding the sponge/dive
    /// button starts charging the squid-surge jump. Negative because SwiftUI
    /// drag translations grow downward — "up" is a negative height delta.
    private let jumpChargeSlideThreshold: CGFloat = -46

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Color.clear
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(aimGesture)
            }
            .ignoresSafeArea()
            .allowsHitTesting(!controller.isHUDEditMode)

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 14) {
                        repositionable(.joystick) { joystick }
                    }
                    .padding(.leading, 18)
                    .padding(.bottom, 26)
                    Spacer()
                    HStack(alignment: .bottom, spacing: 20) {
                        VStack(spacing: 12) {
                            repositionable(.jump) { jumpButton }
                            repositionable(.dive) { diveJoystick }
                        }
                        inkGauge
                            .padding(.trailing, 2)
                        ZStack(alignment: .topTrailing) {
                            repositionable(.fire) { fireButton }
                            repositionable(.grenade) { grenadeButton }
                                .offset(x: 46, y: -96)
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 26)
                }
            }

            if controller.isHUDEditMode {
                hudEditOverlay
            }
        }
        .coordinateSpace(name: "hudControls")
        .allowsHitTesting(!controller.isMatchOver)
    }

    /// Wraps a control with its saved offset, and — while HUD edit mode is
    /// active — a translucent drag handle laid OVER the control that captures
    /// every touch, so repositioning always works even on controls that have
    /// their own gestures (joystick, fire button…).
    @ViewBuilder
    private func repositionable<Content: View>(
        _ id: HUDControlID,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let saved = ProfileStore.shared.hudOffsets[id.rawValue] ?? .zero
        content()
            .offset(x: saved.width, y: saved.height)
            .overlay {
                if controller.isHUDEditMode {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Team.orange.color.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Team.orange.color, lineWidth: 2)
                        )
                        .contentShape(Rectangle())
                        .offset(x: saved.width, y: saved.height)
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    // Anchor on the offset at drag start — `saved`
                                    // changes on every refresh mid-drag, so using it
                                    // directly would compound the translation.
                                    let base = repositionBase[id.rawValue]
                                        ?? (ProfileStore.shared.hudOffsets[id.rawValue] ?? .zero)
                                    if repositionBase[id.rawValue] == nil {
                                        repositionBase[id.rawValue] = base
                                    }
                                    var offsets = ProfileStore.shared.hudOffsets
                                    offsets[id.rawValue] = CGSize(
                                        width: base.width + value.translation.width,
                                        height: base.height + value.translation.height
                                    )
                                    ProfileStore.shared.hudOffsets = offsets
                                }
                                .onEnded { _ in
                                    repositionBase[id.rawValue] = nil
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                        )
                }
            }
    }

    /// Scrim + instructions shown while repositioning HUD buttons.
    private var hudEditOverlay: some View {
        VStack {
            HStack {
                Text("GLISSE LES BOUTONS POUR LES DÉPLACER")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.55)))
                Spacer()
                Button {
                    ProfileStore.shared.resetHUDLayout()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("RÉINITIALISER")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                Button {
                    // Restore the layout exactly as it was before this edit
                    // session started — a real cancel, not just "stop editing".
                    ProfileStore.shared.hudOffsets = controller.hudEditSnapshot ?? [:]
                    controller.hudEditSnapshot = nil
                    controller.isHUDEditMode = false
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                Button {
                    controller.hudEditSnapshot = nil
                    controller.isHUDEditMode = false
                } label: {
                    Text("TERMINÉ")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Team.orange.color))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            Spacer()
        }
        .allowsHitTesting(true)
    }

    private var aimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let deltaX = value.translation.width - lastDrag.width
                let deltaY = value.translation.height - lastDrag.height
                lastDrag = value.translation
                controller.addAimDelta(deltaX: deltaX, deltaY: deltaY)
            }
            .onEnded { _ in
                lastDrag = .zero
            }
    }

    private var joystick: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 128, height: 128)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 2))
            Circle()
                .fill(Team.orange.color.opacity(0.92))
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                .offset(knobOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var offset = CGSize(
                        width: value.translation.width,
                        height: value.translation.height
                    )
                    let length = sqrt(offset.width * offset.width + offset.height * offset.height)
                    let maxRadius: CGFloat = 46
                    if length > maxRadius {
                        offset.width *= maxRadius / length
                        offset.height *= maxRadius / length
                    }
                    knobOffset = offset
                    controller.joystick = SIMD2<Float>(
                        Float(offset.width / maxRadius),
                        Float(-offset.height / maxRadius)
                    )
                }
                .onEnded { _ in
                    knobOffset = .zero
                    controller.joystick = .zero
                }
        )
    }

    /// Sponge dive joystick — hold to swim and drag the same finger to steer.
    /// Sliding the held finger upward past `jumpChargeSlideThreshold` charges
    /// the squid-surge jump: the player stays in sponge form for ~0.5 s (shown
    /// live by the yellow ring filling in), then automatically pops out of
    /// the ink with a boosted jump.
    private var diveJoystick: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(controller.isDiving ? Team.orange.color.opacity(0.28) : .white.opacity(0.1))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle().stroke(
                            isDraggingOntoJump ? Color.yellow : (controller.isDiving ? Team.orange.color : .white.opacity(0.25)),
                            lineWidth: controller.isDiving ? 3 : 2
                        )
                    )
                    .shadow(
                        color: controller.isDiving ? Team.orange.color.opacity(0.55) : .clear,
                        radius: 10
                    )
                if isDraggingOntoJump {
                    Circle()
                        .trim(from: 0, to: CGFloat(controller.diveJumpChargeRatio))
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.05), value: controller.diveJumpChargeRatio)
                }
                VStack(spacing: 2) {
                    Image(systemName: isDraggingOntoJump ? "arrow.up.circle.fill" : "water.waves")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(controller.isDiving ? .black : Team.orange.color)
                    Text(isDraggingOntoJump ? "SAUT !" : "NAGE")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(controller.isDiving ? .black.opacity(0.75) : .white.opacity(0.7))
                }
                .frame(width: 52, height: 52)
                .background(
                    Circle().fill(controller.isDiving ? Team.orange.color : Color.white.opacity(0.14))
                )
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                .offset(diveKnobOffset)
            }
            .scaleEffect(isDivePressed ? 1.05 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: controller.isDiving)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isDivePressed)
            .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isDraggingOntoJump)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("hudControls"))
                    .onChanged { value in
                        if !isDivePressed {
                            isDivePressed = true
                            controller.setDiveHeld(true)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        var offset = CGSize(
                            width: value.translation.width,
                            height: value.translation.height
                        )
                        let length = sqrt(offset.width * offset.width + offset.height * offset.height)
                        let maxRadius: CGFloat = 34
                        if length > maxRadius {
                            offset.width *= maxRadius / length
                            offset.height *= maxRadius / length
                        }
                        diveKnobOffset = offset
                        controller.diveStick = SIMD2<Float>(
                            Float(offset.width / maxRadius),
                            Float(-offset.height / maxRadius)
                        )
                        // Squid-surge: sliding the held finger upward past the
                        // threshold (regardless of where the jump button
                        // actually sits on screen) starts the charge.
                        let slidingUp = value.translation.height < jumpChargeSlideThreshold
                        if slidingUp != isDraggingOntoJump {
                            isDraggingOntoJump = slidingUp
                            if slidingUp {
                                controller.beginDiveJumpCharge()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } else {
                                controller.cancelDiveJumpCharge()
                            }
                        }
                    }
                    .onEnded { _ in
                        isDivePressed = false
                        diveKnobOffset = .zero
                        controller.diveStick = .zero
                        controller.cancelDiveJumpCharge()
                        controller.setDiveHeld(false)
                        isDraggingOntoJump = false
                    }
            )
        }
    }

    /// Launches a jump — hop onto crates, decks and platforms.
    private var jumpButton: some View {
        Button {
            controller.jump()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(isDraggingOntoJump ? .black : .white)
                Text("SAUT")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(isDraggingOntoJump ? .black.opacity(0.7) : .white.opacity(0.7))
            }
            .frame(width: 68, height: 68)
            .background(Circle().fill(isDraggingOntoJump ? Color.yellow : Color.white.opacity(0.12)))
            .overlay(Circle().stroke(isDraggingOntoJump ? Color.yellow : .white.opacity(0.28), lineWidth: isDraggingOntoJump ? 3 : 2))
            .shadow(color: isDraggingOntoJump ? Color.yellow.opacity(0.6) : .clear, radius: 10)
            .scaleEffect(isDraggingOntoJump ? 1.12 : (controller.isAirborne ? 0.88 : 1))
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isDraggingOntoJump)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: controller.isAirborne)
        }
        .buttonStyle(.plain)
    }

    /// Gadget slot (4th loadout slot): the equipped gadget fires from this
    /// button. The paint bomb keeps the held free-aim flow (trajectory +
    /// landing zone, plant at your feet); instant gadgets (mur, détecteur,
    /// jet) trigger on press. Shows the cooldown as a ring.
    private var grenadeButton: some View {
        let gadget = controller.gadget
        let cooldownFraction = controller.grenadeCooldown / gadget.cooldown
        let hasInk = controller.inkLevel >= gadget.inkCost
        let isReady = controller.grenadeCooldown <= 0 && hasInk

        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.4))
                    .frame(width: 66, height: 66)
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                Circle()
                    .trim(from: 0, to: 1 - cooldownFraction)
                    .stroke(
                        isReady ? Team.orange.color : Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                Image(systemName: gadget == .paintBomb
                    ? (isGrenadePressed ? "scope" : "burst.fill")
                    : gadget.iconSystemName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(isReady ? Team.orange.color : .white.opacity(0.4))
            }
            .opacity(isReady ? 1 : 0.75)
            .scaleEffect(isGrenadePressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.15), value: isReady)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: isGrenadePressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isGrenadePressed {
                            isGrenadePressed = true
                            lastGrenadeDrag = .zero
                            controller.beginGrenadeAim()
                        }
                        let deltaX = value.translation.width - lastGrenadeDrag.width
                        let deltaY = value.translation.height - lastGrenadeDrag.height
                        lastGrenadeDrag = value.translation
                        controller.addAimDelta(deltaX: deltaX, deltaY: deltaY)
                    }
                    .onEnded { _ in
                        isGrenadePressed = false
                        lastGrenadeDrag = .zero
                        controller.releaseGrenadeAim()
                    }
            )
            Text(gadget == .paintBomb ? "glisser : viser · bas : poser" : gadget.displayName.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    /// Fire button with built-in free aim: while holding to fire, dragging
    /// the finger redirects the aim in real time — no need to release.
    /// Shows the charger's charge gauge as a ring while holding.
    private var fireButton: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Team.orange.color, Color(red: 0.85, green: 0.32, blue: 0)],
                            center: .center,
                            startRadius: 6,
                            endRadius: 50
                        )
                    )
                    .frame(width: 94, height: 94)
                    .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 3))
                    .shadow(color: Team.orange.color.opacity(0.5), radius: 10)
                Image(systemName: controller.weapon.iconSystemName)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                if controller.weapon == .charger, controller.chargeLevel > 0.01 {
                    Circle()
                        .trim(from: 0, to: CGFloat(controller.chargeLevel))
                        .stroke(
                            controller.chargeLevel >= 0.99 ? Color.white : Color.yellow,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(-90))
                }
            }
            .scaleEffect(isFirePressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.5), value: isFirePressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isFirePressed {
                            isFirePressed = true
                            lastFireDrag = .zero
                            controller.isFiring = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        let deltaX = value.translation.width - lastFireDrag.width
                        let deltaY = value.translation.height - lastFireDrag.height
                        lastFireDrag = value.translation
                        controller.addAimDelta(deltaX: deltaX, deltaY: deltaY)
                    }
                    .onEnded { _ in
                        isFirePressed = false
                        lastFireDrag = .zero
                        controller.isFiring = false
                    }
            )
            if let hint = fireHint {
                Text(hint)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// Contextual reminder of the hold/release mechanic per weapon.
    private var fireHint: String? {
        switch controller.weapon {
        case .charger: "tenir : charger"
        default: nil
        }
    }

    private var inkGauge: some View {
        let ratio = CGFloat(max(0, min(1, controller.inkLevel / GameConfig.maxInk)))
        return ZStack(alignment: .bottom) {
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 16, height: 110)
            Capsule()
                .fill(ratio < 0.15 ? Color.red : Team.orange.color)
                .frame(width: 16, height: max(8, 110 * ratio))
        }
        .padding(.bottom, 6)
    }
}
