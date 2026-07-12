import Flutter
import UIKit
import Foundation

/// Native iOS bridge for heavy torrent operations.
/// All disk I/O runs on a dedicated background queue.
class TorrentBridgeHandler: NSObject, FlutterStreamHandler {
    private static let bgQueue = DispatchQueue(
        label: "com.dirxplorerakib.pro.torrent-bg",
        qos: .utility
    )

    private var eventSink: FlutterEventSink?

    // MARK: - Registration

    static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: "com.dirxplorerakib.pro/torrent_engine",
            binaryMessenger: messenger
        )
        let handler = TorrentBridgeHandler()
        registrar.addMethodCallDelegate(handler, channel: methodChannel)

        let eventChannel = FlutterEventChannel(
            name: "com.dirxplorerakib.pro/torrent_engine_events",
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(handler)
    }

    // MARK: - MethodChannel

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getDeviceStorage":
            Self.bgQueue.async {
                let storage = self.queryDeviceStorage()
                DispatchQueue.main.async { result(storage) }
            }

        case "moveTorrentData":
            guard let args = call.arguments as? [String: Any],
                  let cur = args["currentPath"] as? String,
                  let new = args["newPath"] as? String else {
                result(FlutterError(code: "INVALID_ARGS",
                                    message: "Missing currentPath or newPath", details: nil))
                return
            }
            Self.bgQueue.async {
                if let err = self.moveFiles(from: cur, to: new) {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "MOVE_FAILED", message: err, details: nil))
                    }
                } else {
                    DispatchQueue.main.async { result(new) }
                }
            }

        case "deleteTorrentCache":
            Self.bgQueue.async {
                let ok = self.removeCacheFiles()
                DispatchQueue.main.async { result(ok) }
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - EventChannel (FlutterStreamHandler)

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: - Device Storage (background thread)

    private func queryDeviceStorage() -> [String: Double] {
        guard let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first else { return ["free": 0, "total": 0] }
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: path)
            let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            let total = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
            return ["free": free, "total": total]
        } catch {
            return ["free": 0, "total": 0]
        }
    }

    // MARK: - File Operations (background thread, never blocks UI)

    private func moveFiles(from currentPath: String, to newPath: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: currentPath, isDirectory: &isDir) else {
            return "Source does not exist"
        }
        do {
            if !fm.fileExists(atPath: newPath) {
                try fm.createDirectory(atPath: newPath, withIntermediateDirectories: true)
            }
            let contents = try fm.contentsOfDirectory(atPath: currentPath)
            for item in contents {
                let src = (currentPath as NSString).appendingPathComponent(item)
                let dst = (newPath as NSString).appendingPathComponent(item)
                if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
                try fm.moveItem(atPath: src, toPath: dst)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func removeCacheFiles() -> Bool {
        guard let cachePath = NSSearchPathForDirectoriesInDomains(
            .cachesDirectory, .userDomainMask, true
        ).first else { return false }
        let fm = FileManager.default
        do {
            let contents = try fm.contentsOfDirectory(atPath: cachePath)
            for item in contents {
                let path = (cachePath as NSString).appendingPathComponent(item)
                if item.lowercased().contains("libtorrent") ||
                   item.lowercased().contains("torrent") ||
                   item == "torrent_cache" {
                    try fm.removeItem(atPath: path)
                }
            }
            return true
        } catch {
            return false
        }
    }
}
