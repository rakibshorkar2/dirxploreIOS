import Flutter
import UIKit
import UserNotifications
import OSLog

/// Uncaught ObjC exception handler — logs full info then crashes.
func objcExceptionHandler(_ exception: NSException) {
    os_log("[CRASH] NSException name: %{public}@", exception.name.rawValue)
    os_log("[CRASH] NSException reason: %{public}@", exception.reason ?? "(nil)")
    os_log("[CRASH] NSException userInfo: %{public}@", exception.userInfo ?? [:])
    for (i, symbol) in exception.callStackSymbols.enumerated() {
        os_log("[CRASH] NSException stack[%d]: %{public}@", i, symbol)
    }
}

/// Signal handler for fatal crashes (SIGABRT, SIGSEGV, SIGBUS, etc).
func signalHandler(_ signal: Int32) {
    let name: String
    switch signal {
    case SIGABRT: name = "SIGABRT"
    case SIGSEGV: name = "SIGSEGV"
    case SIGBUS:  name = "SIGBUS"
    case SIGFPE:  name = "SIGFPE"
    case SIGILL:  name = "SIGILL"
    case SIGPIPE: name = "SIGPIPE"
    default:      name = "SIGNAL(\(signal))"
    }
    os_log("[CRASH] Signal received: %{public}@", name)
    fatalError("Unhandled signal: \(name)")
}

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var magnetChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        os_log("[STARTUP] application didFinishLaunchingWithOptions")

        // Install uncaught exception & signal handlers
        NSSetUncaughtExceptionHandler(objcExceptionHandler)
        signal(SIGABRT, signalHandler)
        signal(SIGSEGV, signalHandler)
        signal(SIGBUS, signalHandler)
        signal(SIGFPE, signalHandler)
        signal(SIGILL, signalHandler)
        signal(SIGPIPE, signalHandler)
        os_log("[STARTUP] ObjC exception + signal handlers installed")

        GeneratedPluginRegistrant.register(with: self)
        os_log("[STARTUP] GeneratedPluginRegistrant registered")

        if let registrar = self.registrar(forPlugin: "DownloadPlugin") {
            os_log("[STARTUP] DownloadPlugin registrar obtained, registering...")
            DownloadPlugin.register(with: registrar)
            os_log("[STARTUP] DownloadPlugin registered (includes TorrentBridgeHandler + TorrentBackgroundManager)")
        } else {
            os_log("[STARTUP] WARNING: DownloadPlugin registrar is nil!")
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            os_log("[STARTUP] Notification authorization granted: %{public}@", String(granted))
        }

        if let controller = window?.rootViewController as? FlutterViewController {
            os_log("[STARTUP] FlutterViewController obtained from window")
            magnetChannel = FlutterMethodChannel(
                name: "com.dirxplorerakib.pro/magnet_receiver",
                binaryMessenger: controller.binaryMessenger
            )
            magnetChannel?.setMethodCallHandler { [weak self] (call, result) in
                switch call.method {
                case "checkPendingIntent":
                    if let url = self?.pendingMagnetUrl {
                        self?.magnetChannel?.invokeMethod("onMagnet", arguments: url)
                        self?.pendingMagnetUrl = nil
                    }
                    result(true)
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
            os_log("[STARTUP] Magnet channel initialized")
        } else {
            os_log("[STARTUP] WARNING: window.rootViewController is not FlutterViewController (type: %{public}@)",
                   String(describing: type(of: window?.rootViewController)))
        }

        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        os_log("[STARTUP] super.application didFinishLaunchingWithOptions returned: %{public}@", String(result))
        return result
    }

    private var pendingMagnetUrl: String?

    override func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if url.scheme == "magnet" {
            if let channel = magnetChannel {
                channel.invokeMethod("onMagnet", arguments: url.absoluteString)
            } else {
                pendingMagnetUrl = url.absoluteString
            }
            return true
        }
        if url.pathExtension.lowercased() == "torrent" {
            let path = url.path
            if let channel = magnetChannel {
                channel.invokeMethod("onTorrentFile", arguments: path)
            }
            return true
        }
        return super.application(app, open: url, options: options)
    }

    override func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}
