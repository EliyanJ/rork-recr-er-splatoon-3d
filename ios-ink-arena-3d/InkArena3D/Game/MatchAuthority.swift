import Foundation

/// Host-side match authority (network overhaul, step 4).
///
/// In a local duel the HOST device is the single source of truth for every
/// shared match value: the team coverage counters (its grid aggregates both
/// its own paint and the guest's exact `paintOps`) and the match clock.
/// This type owns the broadcast cadence: it throttles and emits the
/// authoritative `coverage` + `clock` messages that the guest displays
/// instead of its own locally-drifting counters — which is what removes the
/// "two different percentages on two screens" divergence.
///
/// Kills are already authoritative by design (the victim's own device is the
/// only one that announces its death via the explicit `kill` message), so no
/// arbitration is needed here.
///
/// When online multiplayer arrives, this authority migrates from the host
/// device to the server — same messages, different owner.
@MainActor
final class MatchAuthority {
    /// Broadcast interval — 2 Hz is plenty for HUD counters and a clock.
    private let interval: Double
    private var timer: Double = 0
    private let send: (NetMessage) -> Void

    init(interval: Double = 0.5, send: @escaping (NetMessage) -> Void) {
        self.interval = interval
        self.send = send
    }

    /// Called once per frame from the host's game loop with the live
    /// authoritative values; emits at the throttled cadence. `modeScores`
    /// carries the mode-specific team totals (zone points / kills) so the
    /// guest HUD mirrors the host's objective score exactly.
    func tick(
        dt: Double,
        remaining: Double,
        orange: Int,
        purple: Int,
        total: Int,
        modeScores: (orange: Int, purple: Int)? = nil
    ) {
        timer -= dt
        guard timer <= 0 else { return }
        timer = interval
        send(.clock(NetClock(remaining: Float(remaining))))
        send(.coverage(
            orange: orange, purple: purple, total: total,
            modeOrange: modeScores?.orange, modePurple: modeScores?.purple
        ))
    }
}
