# aws_ivs_realtime

Flutter plugin for **Amazon IVS Real-Time (Stages)** on **Android** and **iOS**, with Dart helpers for:

- Native stage **MethodChannel** + **platform view** (`join` / `leave` / `setPublish` / mute)
- Optional **SigV4** control plane ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart)) or your **backend** by implementing [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)
- IVS **Chat** WebSocket session ([`IvsChatSession`](lib/ivs_chat_session.dart))
- Runtime **microphone/camera** requests via [`permission_handler`](https://pub.dev/packages/permission_handler)

**Repository:** [github.com/vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime) · **Issues:** [github.com/vipulbansal/aws_ivs_realtime/issues](https://github.com/vipulbansal/aws_ivs_realtime/issues)

---

## Does installing the package “turn on” backend or frontend AWS?

**No.** Adding this dependency does **not** register a backend, prompt for keys, or choose a mode. **Your Flutter code** must:

1. Obtain a **participant token** (almost always via **your HTTPS API** in production), then  
2. Call [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart) and embed the [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart) grid.

The **optional** Dart files in this package are **building blocks** you wire up (see [Where everything lives in the package](#where-everything-lives-in-the-package)). For a concrete wiring sample, run the **`example/`** app in this repository (SigV4 vs stub backend toggle).

**In-package documentation:** open [`package:aws_ivs_realtime/aws_ivs_realtime.dart`](https://pub.dev/documentation/aws_ivs_realtime/latest/aws_ivs_realtime/) on pub.dev after publish — the library doc summarizes backend vs device signing and which keys mean what.

---

## AWS keys vs participant token (plain English)

People mix these up; IVS Real-Time needs **both concepts**, but **not** the same string for everything.

| What people call it | What it really is | Do you pass it to `join(... token:)`? | When do you need it? |
|---------------------|---------------------|----------------------------------------|-------------------------|
| **Participant token** | Opaque string returned by AWS [**CreateParticipantToken**](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html) | **Yes** — this is the only `token` [`join`](lib/ivs_realtime_platform.dart) accepts | Always, for every user joining a stage |
| **AWS access key ID** | IAM user or long-term access key *id* (starts with `AKIA…` for a root-style IAM user key) | **No** | Only if **your app** signs AWS HTTP requests on-device ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart), [`IvsRealtimeTokenClient`](lib/ivs_realtime_token_client.dart)) — **not** recommended for production |
| **AWS secret access key** | Secret paired with that access key ID | **No** | Same as above — should live **only on your server** in production |
| **Session token** | Third string when using **temporary** credentials (STS, assumed role) | **No** | Same as above: optional third field with access key + secret when signing **from the device**; on the backend you usually use an **IAM role** and never surface these three fields to the phone |

**Rule of thumb for production:** the mobile app should only ever see **HTTPS + your own JSON** and a **participant token** string. **Access key ID / secret / session token** stay on the server (or in your CI), where they are used to call AWS and mint short-lived tokens.

**IVS Chat** is separate: you mint a **chat token** ([CreateChatToken](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateChatToken.html)) and pass that into [`IvsChatSession`](lib/ivs_chat_session.dart), not into stage `join`.

---

## What you need to know first

This package **does not** create an IVS stage or mint tokens by itself. It **joins a stage** once you have a **participant token**.

| Step | Who does it | Notes |
|------|----------------|--------|
| 1. Create / choose an IVS **stage** | Your product (console, IaC, or API) | You need the **stage ARN** to mint tokens. |
| 2. Mint a **participant token** | **Recommended:** your **backend** with IAM on the server | Returns the opaque token string to the app. |
| 2 alt. Mint token in **Flutter** (demo) | [`IvsRealtimeTokenClient`](lib/ivs_realtime_token_client.dart) or [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) | Uses **IAM access key + secret (+ optional session token)** in Dart — **local / demo only**. |
| 3. Show the **native grid** | `AndroidView` / `UiKitView` with [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart) | Must match native registration (`ivs_stage_view`). |
| 4. **Join** | [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart) | Pass **participant token** + `publish` flag. |

---

## Where everything lives in the package

| Goal | Type / API | Credentials involved |
|------|------------|-------------------------|
| Join / leave / mute / publish toggles | [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart) | **Only** participant token for `join` — **not** IAM keys |
| Embed native participant grid | [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart) | None |
| Your backend wraps AWS | Implement [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) | None in plugin; **your** server uses IAM role / keys |
| Sign AWS from Flutter (demo) | [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) + [`IvsAwsCredentialResolver`](lib/ivs_live_control_plane.dart) | Access key ID + secret + optional session token |
| Lower-level “just mint participant token” in Dart | [`IvsRealtimeTokenClient.createParticipantToken`](lib/ivs_realtime_token_client.dart) | Same as SigV4 path — IAM triple in Dart |
| List/create/delete stages from Dart (demo helpers) | [`IvsRealtimeStagesApi`](lib/ivs_realtime_stages_api.dart) | Same IAM triple passed into each call |
| IVS Chat REST helpers | [`IvsChatApi`](lib/ivs_chat_api.dart) | IAM triple for chat control plane |
| IVS Chat WebSocket | [`IvsChatSession`](lib/ivs_chat_session.dart) | **Chat token** from your backend or [`mintChatToken`](lib/ivs_live_control_plane.dart) |

---

## Requirements

| Platform | Minimum | Notes |
|----------|---------|--------|
| Android  | API 28  | `RECORD_AUDIO`, `CAMERA` when publishing |
| iOS      | 14.0    | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` |

Native SDKs: Android Maven `ivs-broadcast` stages AAR (**1.41.0** in this repo); iOS CocoaPods `AmazonIVSBroadcast/Stages` (**~> 1.36.0** in the podspec—align when CocoaPods publishes newer series).

---

## Install

From [pub.dev](https://pub.dev/packages/aws_ivs_realtime):

```yaml
dependencies:
  aws_ivs_realtime: ^0.1.1
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

---

## Control plane: backend (recommended) vs SigV4 on the device

### Option A — Backend API (production)

1. Your server uses an **IAM role** (or instance profile) to call **CreateParticipantToken**.  
2. Your app calls **only your HTTPS API**; the response includes the **participant token** string.  
3. Implement [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart): each method performs `http.get` / `post` to **your** URLs; no AWS keys in the app binary.

### Option B — SigV4 from the device (example / debugging only)

[`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) signs requests using **access key ID + secret access key + optional session token** from an [`IvsAwsCredentialResolver`](lib/ivs_live_control_plane.dart). The **`example/`** app exposes text fields and [`--dart-define`](https://dart.dev/tools/dart-compile#passing-dart-define-values) for local runs.

**Do not** ship IAM user keys in a store build or commit them to a public repo.

---

## Usage (minimal)

```dart
import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';

// 1) `participantToken` = string from CreateParticipantToken (from YOUR API in prod).

final stage = IvsRealtimePlatform();
await stage.join(token: participantToken, publish: isHost);

AndroidView(viewType: AwsIvsRealtimePlatformView.viewType, ...)
// iOS: UiKitView with the same viewType.
```

Listen to [`stageConnectionEvents`](lib/ivs_realtime_platform.dart) for host-ended / disconnected events.

### IVS Chat (optional)

Mint a **chat token** server-side or via [`IvsLiveControlPlane.mintChatToken`](lib/ivs_live_control_plane.dart), then use [`IvsChatSession`](lib/ivs_chat_session.dart). The **`example/`** app shows chat next to the stage.

---

## Example app

Under **`example/`**: lobby → full-screen live → chat, with a switch between **SigV4 on device** (keys in UI / defines) and a **stub backend** illustrating [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart).

---

## Documentation

Architecture, MethodChannel / EventChannel contracts, SigV4 **service scope** (`ivs` vs `ivsrealtime`), troubleshooting: [DOCUMENTATION.md](DOCUMENTATION.md).

---

## Contributing

Issues and pull requests: [vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime).

---

## Publishing (maintainers)

`dart pub publish` from package root. Do not ship IAM credentials in example or app code.

---

## License

See [LICENSE](LICENSE).
