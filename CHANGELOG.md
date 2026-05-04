# Changelog

## 0.1.2

- README: **Dart-only** layout/chrome around the stage (no native XML/Swift required for buttons/lists); **listStages → Flutter list → join existing stage** code snippet; **GitHub + clone + example `flutter run`**; prominent source table.
- README: **streaming-only vs optional IVS Chat** — no plugin toggle; opt in by APIs/UI you use.
- README: explicit **Android** `<uses-permission>` and **iOS** `Info.plist` keys (plugin does not inject them); clarify manifest vs runtime `permission_handler` requests.
- README: real-time stage + optional IVS Chat positioning; full **`IvsLiveControlPlane`** method ↔ AWS ↔ return-type table; **after implementing the interface** — how to wire `control`, [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart), **platform view** (`AndroidView` / `UiKitView`), and optional [`IvsChatSession`](lib/ivs_chat_session.dart); app-only **`--dart-define`** / credential resolver; optional **`userId`** on `mintParticipantToken` and **`mintChatToken`** `userId` / `attributes` for real display names; `.gitignore` / `.pubignore` hygiene (when applicable).
- Dart: library documentation on `aws_ivs_realtime.dart`; expanded [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) and [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart) API docs.
- `pubspec.yaml`: verified **`publisher`** domain when publishing under a pub.dev verified publisher.

## 0.1.1

- README: participant token vs IAM keys, backend vs device SigV4, package API map, and “no install wizard” clarification.
- Dart: library documentation on `aws_ivs_realtime.dart`; expanded `IvsRealtimePlatform` / `join` API docs.

## 0.1.0

- Initial pub.dev–oriented release as a Flutter plugin (`aws_ivs_realtime`).
- Android and iOS native IVS Real-Time Stages (platform view + method channel).
- Dart: `IvsLiveControlPlane` with `IvsAwsSigV4ControlPlane` (frontend) and backend-oriented API surface.
- `permission_handler` preflight for microphone/camera before join/publish.
- Example app under `example/` mirroring the original demo.
