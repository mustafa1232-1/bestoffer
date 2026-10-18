import AVFAudio
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  PKPushRegistryDelegate, CallkitIncomingAppDelegate
{
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    // PushKit wakes the app (even when terminated) for incoming in-app calls;
    // the token reaches Dart via DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP and is
    // registered with the backend as platform "ios_voip".
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PushKit

  func pushRegistry(
    _ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType
  ) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    // Apple requires every VoIP push to report a call to CallKit right away.
    // The backend payload (feed.call-push.js) already uses the plugin's keys:
    // id, nameCaller, handle, type, duration, extra{threadId, sessionId, ...}.
    var args: [String: Any?] = [:]
    for (key, value) in payload.dictionaryPayload {
      if let key = key as? String, key != "aps" { args[key] = value }
    }
    if (args["id"] as? String ?? "").isEmpty {
      args["id"] = UUID().uuidString
    }
    let data = flutter_callkit_incoming.Data(args: args)
    data.appName = "مسلكي"
    data.handleType = "generic"
    data.supportsVideo = false
    data.supportsHolding = false
    data.supportsDTMF = false
    data.supportsGrouping = false
    data.supportsUngrouping = false
    data.maximumCallGroups = 1
    data.audioSessionMode = "voiceChat"
    data.isShowMissedCallNotification = false
    if let extra = data.extra.mutableCopy() as? NSMutableDictionary {
      extra["declineUrl"] = AppDelegate.declineUrl()
      data.extra = extra
    }
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      data, fromPushKit: true
    ) {
      completion()
    }
  }

  // MARK: - CallKit actions

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    // Dart (ACTION_CALL_ACCEPT / activeCalls on cold start) opens the live
    // call screen and runs WebRTC.
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
    AppDelegate.sendDecline(extra: call.data.extra)
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  func providerDidReset() {}

  // MARK: - Decline while the Flutter engine is not running

  private static func declineUrl() -> String {
    let configured =
      (Bundle.main.object(forInfoDictionaryKey: "MaslakiApiBaseUrl") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let base = configured.isEmpty ? "https://bestoffer-production.up.railway.app" : configured
    return base.hasSuffix("/")
      ? "\(base)api/feed/chats/calls/decline"
      : "\(base)/api/feed/chats/calls/decline"
  }

  /// Posts the signed call token so the caller sees "declined" immediately.
  /// Idempotent with the Dart-side request when the app is alive.
  private static func sendDecline(extra: NSDictionary) {
    guard let token = extra["callActionToken"] as? String, !token.isEmpty else { return }
    let urlString = (extra["declineUrl"] as? String) ?? declineUrl()
    guard let url = URL(string: urlString), url.scheme == "https" else { return }
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
    var task: UIBackgroundTaskIdentifier = .invalid
    task = UIApplication.shared.beginBackgroundTask {
      UIApplication.shared.endBackgroundTask(task)
    }
    URLSession.shared.dataTask(with: request) { _, _, _ in
      UIApplication.shared.endBackgroundTask(task)
    }.resume()
  }
}
