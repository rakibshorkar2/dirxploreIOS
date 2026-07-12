import ActivityKit
import Foundation

struct TorrentActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var torrentName: String
        var progress: Double
        var downloadSpeed: String
        var eta: String
        var downloadedSize: String
        var totalSize: String
        var status: String
        var seeds: Int
        var peers: Int
        var uploadSpeed: String
        var isCompleted: Bool
    }

    var torrentId: String
}
