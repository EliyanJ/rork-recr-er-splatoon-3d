import Foundation

/// Live per-fighter match statistics — feeds the in-match scoreboard and
/// the top-3 live leaderboard. Index 0 is always the player.
struct FighterStats: Identifiable {
    let id: Int
    let name: String
    let team: Team
    var kills: Int = 0
    var deaths: Int = 0
    var assists: Int = 0
    /// Ground tiles this fighter personally claimed for their team.
    var paintTiles: Int = 0
}
