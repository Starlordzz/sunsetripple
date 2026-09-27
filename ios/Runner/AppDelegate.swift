import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var updateInstallerChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    PlatformAudioPlugin.register(with: self.registrar(forPlugin: "PlatformAudioPlugin")!)
    BleL2capPlugin.register(with: self.registrar(forPlugin: "BleL2capPlugin")!)
    registerUpdateInstallerChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 更新链路在 iOS 上**只能**「打开下载页」。
  ///
  /// iOS 的沙箱不允许 App 自行安装 ipa（没有 Android 那种
  /// `ACTION_VIEW + application/vnd.android.package-archive` 的通路），
  /// 所以这里只实现 `openUrl`；Dart 侧也只在 Android 上才会调用
  /// `installApk` / `canRequestPackageInstalls`
  /// （见 lib/core/update/update_installer.dart 的 supportsInAppInstall）。
  ///
  /// 这两个 Android 专属方法在这里明确回 `unsupported`，而不是静默返回成功 ——
  /// 否则用户会以为「更新中」，实际什么也没发生。
  private func registerUpdateInstallerChannel() {
    guard let registrar = self.registrar(forPlugin: "UpdateInstallerPlugin") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "host.msknet.sunsetripple/update_installer",
      binaryMessenger: registrar.messenger()
    )
    updateInstallerChannel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openUrl":
        guard
          let arguments = call.arguments as? [String: Any],
          let raw = arguments["url"] as? String,
          let url = URL(string: raw),
          url.scheme?.lowercased() == "https"
        else {
          result(
            FlutterError(
              code: "invalid_argument",
              message: "只允许打开 https 链接",
              details: nil
            )
          )
          return
        }
        DispatchQueue.main.async {
          UIApplication.shared.open(url, options: [:]) { opened in
            if opened {
              result(true)
            } else {
              result(
                FlutterError(
                  code: "open_failed",
                  message: "系统拒绝打开该链接",
                  details: nil
                )
              )
            }
          }
        }

      case "canRequestPackageInstalls", "installApk":
        result(
          FlutterError(
            code: "unsupported",
            message: "iOS 不允许应用内安装，请在浏览器里完成安装",
            details: nil
          )
        )

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
