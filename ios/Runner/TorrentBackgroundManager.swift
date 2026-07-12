import Flutter
import UIKit
import Foundation
import ActivityKit
import UserNotifications

/// Manages torrent Live Activities (Dynamic Island + Lock Screen) and background tasks.
/// Updates are throttled; completion posts a local notification.
@available(iOS 16.2, *)
class TorrentBackgroundManager: NSObject {
    static let shared = TorrentBackgroundManager()

    private var backgroundTaskID: UIBackgroundTaskIdentifier?
    private var liveActivities: [String: Activity<TorrentActivityAttributes>] = [:]
    private var lastUpdateTime: [String: Date] = [:]
    private let throttleSeconds: TimeInterval = 2.0

    private override init() {}

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let channel = FlutterMethodChannel(
            name: "com.dirxplorerakib.pro/torrent_background",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(TorrentBackgroundManager.shared, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startBackgroundTask":
            startBackgroundTask()
            result(nil)

        case "stopBackgroundTask":
            stopBackgroundTask()
            result(nil)

        case "updateLiveActivity":
            guard let args = call.arguments as? [String: Any] else { result(nil); return }
            updateLiveActivity(args: args)
            result(nil)

        case "endLiveActivity":
            guard let args = call.arguments as? [String: Any],
                  let tid = args["torrentId"] as? String else { result(nil); return }
            let completed = args["isCompleted"] as? Bool ?? true
            endLiveActivity(torrentId: tid,
                           progress: args["progress"] as? Double ?? 1.0,
                           status: args["status"] as? String ?? "Done",
                           isCompleted: completed)
            if completed {
                postCompletionNotification(name: args["fileName"] as? String ?? "Torrent")
            }
            result(nil)

        case "endAllLiveActivities":
            endAll()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Background Task (battery-efficient)

    func startBackgroundTask() {
        guard backgroundTaskID == nil else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask {
            self.stopBackgroundTask()
        }
    }

    func stopBackgroundTask() {
        guard let id = backgroundTaskID else { return }
        backgroundTaskID = nil
        UIApplication.shared.endBackgroundTask(id)
    }

    // MARK: - Live Activity Updates (throttled)

    private func updateLiveActivity(args: [String: Any]) {
        guard let tid = args["torrentId"] as? String else { return }

        let isCompleted = args["isCompleted"] as? Bool ?? false
        let progress = args["progress"] as? Double ?? 0
        let status = args["status"] as? String ?? "Downloading"

        if isCompleted {
            endLiveActivity(torrentId: tid, progress: progress, status: status, isCompleted: true)
            postCompletionNotification(name: args["fileName"] as? String ?? "Torrent")
            return
        }

        guard !isThrottled(torrentId: tid) else { return }
        lastUpdateTime[tid] = Date()

        let state = TorrentActivityAttributes.ContentState(
            torrentName: args["fileName"] as? String ?? "Torrent",
            progress: progress,
            downloadSpeed: args["speed"] as? String ?? "",
            eta: args["eta"] as? String ?? "",
            downloadedSize: args["downloadedSize"] as? String ?? "",
            totalSize: args["totalSize"] as? String ?? "",
            status: status,
            seeds: args["seeds"] as? Int ?? 0,
            peers: args["peers"] as? Int ?? 0,
            uploadSpeed: args["uploadSpeed"] as? String ?? "",
            isCompleted: false
        )

        if let existing = liveActivities[tid] {
            Task { await existing.update(using: state) }
        } else {
            let attrs = TorrentActivityAttributes(torrentId: tid)
            do {
                let content = ActivityContent(state: state, staleDate: nil)
                let activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
                liveActivities[tid] = activity
            } catch {
                debugPrint("Torrent LiveActivity start failed: \(error)")
            }
        }
    }

    private func endLiveActivity(torrentId: String, progress: Double,
                                 status: String, isCompleted: Bool) {
        guard let activity = liveActivities.removeValue(forKey: torrentId) else { return }
        lastUpdateTime.removeValue(forKey: torrentId)

        let finalState = TorrentActivityAttributes.ContentState(
            torrentName: "",
            progress: progress,
            downloadSpeed: "",
            eta: "",
            downloadedSize: "",
            totalSize: "",
            status: status,
            seeds: 0,
            peers: 0,
            uploadSpeed: "",
            isCompleted: isCompleted
        )
        Task {
            await activity.end(using: finalState, dismissalPolicy: isCompleted ? .default : .immediate)
        }
    }

    private func isThrottled(torrentId: String) -> Bool {
        guard let last = lastUpdateTime[torrentId] else { return false }
        return Date().timeIntervalSince(last) < throttleSeconds
    }

    // MARK: - Completion Notification

    private func postCompletionNotification(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Torrent Complete"
        content.body = name
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "torrent-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cleanup

    private func endAll() {
        for (id, activity) in liveActivities {
            lastUpdateTime.removeValue(forKey: id)
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        liveActivities.removeAll()
        stopBackgroundTask()
    }
}
