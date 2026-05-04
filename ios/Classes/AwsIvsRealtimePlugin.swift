import Flutter
import UIKit

private enum AwsIvsRealtimeChannels {
  static let stage = "aws_ivs_realtime/stage"
  static let stageEvents = "aws_ivs_realtime/stage_events"
  static let viewType = "ivs_stage_view"
}

private final class StageEventsStreamHandler: NSObject, FlutterStreamHandler {
  weak var controller: IvsStageController?

  init(controller: IvsStageController) {
    self.controller = controller
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    controller?.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    controller?.eventSink = nil
    return nil
  }
}

public class AwsIvsRealtimePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let controller = IvsStageController()

    let eventChannel = FlutterEventChannel(
      name: AwsIvsRealtimeChannels.stageEvents,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(StageEventsStreamHandler(controller: controller))

    let channel = FlutterMethodChannel(
      name: AwsIvsRealtimeChannels.stage,
      binaryMessenger: registrar.messenger()
    )
    registrar.register(
      IvsStageViewFactory(controller: controller),
      withId: AwsIvsRealtimeChannels.viewType
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "join":
        let args = call.arguments as? [String: Any]
        let token = args?["token"] as? String ?? ""
        let publish = Self.channelBool(args?["publish"], defaultVal: true)
        controller.setPublishEnabled(publish)
        controller.joinOrLeave(token: token, result: result)
      case "leave":
        controller.leave()
        result(nil)
      case "setPublish":
        let enabled = Self.channelBool(call.arguments, defaultVal: true)
        controller.setPublishEnabled(enabled)
        result(nil)
      case "refreshStageBindings":
        controller.refreshStageBindings()
        result(nil)
      case "setLocalStreamMuted":
        let m = call.arguments as? [String: Any]
        let mic = m?["micMuted"] as? Bool ?? false
        let cam = m?["cameraMuted"] as? Bool ?? false
        controller.setLocalStreamMuted(micMuted: mic, cameraMuted: cam)
        result(nil)
      case "setShowParticipantStateOverlay":
        let m = call.arguments as? [String: Any]
        let visible = Self.channelBool(m?["visible"], defaultVal: false)
        controller.setShowParticipantStateOverlay(visible)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.willTerminateNotification,
      object: nil,
      queue: .main
    ) { _ in
      controller.releaseStage()
    }
  }

  private static func channelBool(_ value: Any?, defaultVal: Bool) -> Bool {
    switch value {
    case let b as Bool:
      return b
    case let n as NSNumber:
      return n.intValue != 0
    case nil:
      return defaultVal
    default:
      return defaultVal
    }
  }
}
