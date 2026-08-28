import SwiftUI

/// Shared dark gradient + team-colored glow blobs used by every menu screen.
struct MenuBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.18),
                    Color(red: 0.13, green: 0.08, blue: 0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Team.orange.color.opacity(0.35))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: -260, y: -110)
            Circle()
                .fill(Team.purple.color.opacity(0.35))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 270, y: 120)
        }
    }
}
