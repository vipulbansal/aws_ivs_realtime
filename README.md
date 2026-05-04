# aws_ivs_realtime

Flutter plugin for **Amazon IVS Real-Time (Stages)** on **Android** and **iOS**, with Dart helpers for:

- Native stage **MethodChannel** + **platform view** (`join` / `leave` / `setPublish` / mute)
- Optional **SigV4** control plane ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart)) or your **backend** by implementing [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)
- IVS **Chat** WebSocket session ([`IvsChatSession`](lib/ivs_chat_session.dart))
- Runtime **microphone/camera** requests via [`permission_handler`](https://pub.dev/packages/permission_handler)

**Repository:** [github.com/vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime) · **Issues:** [github.com/vipulbansal/aws_ivs_realtime/issues](https://github.com/vipulbansal/aws_ivs_realtime/issues)

## Requirements

| Platform | Minimum | Notes |
|----------|---------|--------|
| Android  | API 28  | `RECORD_AUDIO`, `CAMERA` when publishing |
| iOS      | 14.0    | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` |

Native SDKs: Android Maven `ivs-broadcast` stages AAR (**1.41.0** in this repo); iOS CocoaPods `AmazonIVSBroadcast/Stages` (**~> 1.36.0** in the podspec—align when CocoaPods publishes newer series).

## Install

From [pub.dev](https://pub.dev/packages/aws_ivs_realtime) (when published):

```yaml
dependencies:
  aws_ivs_realtime: ^0.1.0
```

From Git:

```yaml
dependencies:
  aws_ivs_realtime:
    git:
      url: https://github.com/vipulbansal/aws_ivs_realtime.git
```

### Android

Merge permissions into your app `AndroidManifest.xml` (see `example/android/app/src/main/AndroidManifest.xml`).

### iOS

Set usage strings in `Info.plist` (see `example/ios/Runner/Info.plist`). In your `Podfile`, use at least **iOS 14** and, if CocoaPods requires it, `use_modular_headers!` (see `example/ios/Podfile`).

**`permission_handler` on iOS:** you must add preprocessor flags so microphone/camera code is compiled into `permission_handler_apple`; otherwise `Permission.microphone` / `Permission.camera` never show the system dialog. Copy the `GCC_PREPROCESSOR_DEFINITIONS` block from `example/ios/Podfile` `post_install` (`PERMISSION_MICROPHONE=1`, `PERMISSION_CAMERA=1`).

## Usage

```dart
import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';

final stage = IvsRealtimePlatform();
await stage.join(token: participantToken, publish: isHost);

// Platform view:
AndroidView(viewType: AwsIvsRealtimePlatformView.viewType, ...)
// or UiKitView on iOS with the same viewType.
```

See the **`example/`** app for a full lobby, full-screen live, and chat demo, including **SigV4 (client-side)** vs **backend** control plane wiring.

## Documentation

For architecture, channel contract, token flow, and troubleshooting, see [DOCUMENTATION.md](DOCUMENTATION.md).

## Contributing

Issues and pull requests are welcome in [vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime).

## Publishing (maintainers)

To publish this package on [pub.dev](https://pub.dev), set `homepage`, `repository`, and `issue_tracker` in `pubspec.yaml` (and the podspec `homepage` if needed) to real URLs, then from the package root run `dart pub publish`. Do not ship IAM credentials in example or app code.

## License

See [LICENSE](LICENSE).
