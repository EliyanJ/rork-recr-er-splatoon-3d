import CoreGraphics
import GameController
import simd

/// Polls a hardware keyboard and mouse (GameController framework) so the
/// game is fully playable from a desktop while testing in the simulator:
/// arrows/WASD move, M fires, G holds the grenade aim, space jumps,
/// C toggles the swim form, and physical mouse movement drives the aim.
@MainActor
final class DesktopInputMonitor {
    /// True while a hardware keyboard is attached (simulator or device).
    private(set) var isKeyboardConnected = false
    /// Normalized movement vector from the arrow/letter keys.
    private(set) var moveVector: SIMD2<Float> = .zero

    var onFireChanged: ((Bool) -> Void)?
    var onGrenadeChanged: ((Bool) -> Void)?
    var onJump: (() -> Void)?
    var onDiveToggle: (() -> Void)?
    var onAimDelta: ((CGFloat, CGFloat) -> Void)?

    private var fireDown = false
    private var grenadeDown = false
    private var jumpDown = false
    private var diveDown = false
    private var configuredMouse: ObjectIdentifier?

    /// Called once per frame from the game loop.
    func poll() {
        configureMouseIfNeeded()
        guard let input = GCKeyboard.coalesced?.keyboardInput else {
            isKeyboardConnected = false
            moveVector = .zero
            return
        }
        isKeyboardConnected = true

        func pressed(_ codes: [GCKeyCode]) -> Bool {
            codes.contains { input.button(forKeyCode: $0)?.isPressed == true }
        }

        var move = SIMD2<Float>(0, 0)
        if pressed([.upArrow, .keyW]) { move.y += 1 }
        if pressed([.downArrow, .keyS]) { move.y -= 1 }
        if pressed([.leftArrow, .keyA]) { move.x -= 1 }
        if pressed([.rightArrow, .keyD]) { move.x += 1 }
        moveVector = move == .zero ? .zero : simd_normalize(move)

        updateEdge(pressed([.keyM]), state: &fireDown) { [weak self] down in
            self?.onFireChanged?(down)
        }
        updateEdge(pressed([.keyG]), state: &grenadeDown) { [weak self] down in
            self?.onGrenadeChanged?(down)
        }
        updateEdge(pressed([.spacebar]), state: &jumpDown) { [weak self] down in
            if down { self?.onJump?() }
        }
        updateEdge(pressed([.keyC, .keyV]), state: &diveDown) { [weak self] down in
            if down { self?.onDiveToggle?() }
        }
    }

    private func updateEdge(_ isPressed: Bool, state: inout Bool, action: (Bool) -> Void) {
        guard isPressed != state else { return }
        state = isPressed
        action(isPressed)
    }

    /// Routes physical mouse movement into the aim. The cloud simulator
    /// forwards mouse drags as touches (handled by the on-screen aim zones),
    /// but a real hardware mouse on device streams deltas through GCMouse.
    private func configureMouseIfNeeded() {
        guard let mouse = GCMouse.current else { return }
        let identifier = ObjectIdentifier(mouse)
        guard configuredMouse != identifier else { return }
        configuredMouse = identifier
        mouse.mouseInput?.mouseMovedHandler = { [weak self] _, deltaX, deltaY in
            Task { @MainActor [weak self] in
                self?.onAimDelta?(CGFloat(deltaX), CGFloat(-deltaY))
            }
        }
    }
}
