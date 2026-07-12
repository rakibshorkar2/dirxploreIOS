import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var magnetChannel: FlutterMethodChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let registrar = self.registrar(forPlugin: "DownloadPlugin") {
            DownloadPlugin.register(with: registrar)
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }

        if let controller = window?.rootViewController as? FlutterViewController {
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
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
