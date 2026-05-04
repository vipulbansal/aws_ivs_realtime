# aws_ivs_realtime

Flutter plugin for **Amazon IVS Real-Time (Stages)** on **Android** and **iOS**, with Dart helpers for:

- Native stage **MethodChannel** + **platform view** (`join` / `leave` / `setPublish` / mute)
- Optional **SigV4** control plane ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart)) or your **backend** by implementing [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)
- IVS **Chat** WebSocket session ([`IvsChatSession`](lib/ivs_chat_session.dart))
- Runtime **microphone/camera** requests via [`permission_handler`](https://pub.dev/packages/permission_handler)

## Requirements

| Platform | Minimum | Notes |
|----------|---------|--------|
| Android  | API 28  | `RECORD_AUDIO`, `CAMERA` when publishing |
| iOS      | 14.0    | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` |

Native SDKs: Android Maven `ivs-broadcast` stages AAR (**1.41.0** in this repo); iOS CocoaPods `AmazonIVSBroadcast/Stages` (**~> 1.36.0** in the podspec—align when CocoaPods publishes newer series).

## Install

```yaml
dependencies:
  aws_ivs_realtime: ^0.1.0
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

See the **`example/`** app for the full lobby + full-screen live + chat demo (same behavior as the original project), including **frontend (SigV4)** vs **backend** control plane wiring.

## GitHub repository name

- **Pub.dev package name** (in `pubspec.yaml`): **`aws_ivs_realtime`** — keep this; it is what consumers add in `dependencies:`.
- **GitHub repo name:** Using **`aws_ivs_realtime`** (same as the package) matches pub.dev and avoids sounding like a throwaway sample-only repo.
- **Local checkout folder** is expected to be named **`aws_ivs_realtime`** (same as the package); this does not change `pubspec.yaml` `name:`.

After you create the GitHub repo, replace **`YOUR_GITHUB_USERNAME`** in `pubspec.yaml` and `ios/aws_ivs_realtime.podspec` with your GitHub user or organization name.

## Publishing

With real `homepage` / `repository` / `issue_tracker` URLs (see above), from the package root:

```bash
dart pub publish
```

## License

See [LICENSE](LICENSE).
