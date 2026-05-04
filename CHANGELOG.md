# Changelog

## 0.1.1

- README: participant token vs IAM keys, backend vs device SigV4, package API map, and “no install wizard” clarification.
- Dart: library documentation on `aws_ivs_realtime.dart`; expanded `IvsRealtimePlatform` / `join` API docs.

## 0.1.0

- Initial pub.dev–oriented release as a Flutter plugin (`aws_ivs_realtime`).
- Android and iOS native IVS Real-Time Stages (platform view + method channel).
- Dart: `IvsLiveControlPlane` with `IvsAwsSigV4ControlPlane` (frontend) and backend-oriented API surface.
- `permission_handler` preflight for microphone/camera before join/publish.
- Example app under `example/` mirroring the original demo.
