/// Amazon **IVS Real-Time** (Stages) for Flutter (Android + iOS), plus optional Dart
/// helpers for the **control plane** (participant tokens, stages) and **IVS Chat**.
///
/// ## This package does not pick “backend” vs “frontend” for you
///
/// Adding `aws_ivs_realtime` to `pubspec.yaml` does **not** show a wizard or force a
/// mode. **You** choose how the app gets a **participant token**:
///
/// - **Production (recommended):** your **backend** calls AWS (e.g.
///   [CreateParticipantToken](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html))
///   using an IAM **role** on the server. The app calls **only your HTTPS API** and
///   receives the token string. Implement [IvsLiveControlPlane] and point each method
///   at your REST endpoints.
/// - **Demo / local only:** use [IvsAwsSigV4ControlPlane] or [IvsRealtimeTokenClient]
///   so Dart signs AWS requests using **IAM access key ID + secret access key** and
///   optional **session token** on the device. Do **not** ship long-lived IAM user
///   keys to end users.
///
/// The native stage ([IvsRealtimePlatform.join]) needs **only** the **participant
/// token** — never IAM access keys for the `token` parameter.
///
/// ## Which “keys” exist, and where they go
///
/// **Participant token** (opaque string from `CreateParticipantToken`):
/// - Pass to [IvsRealtimePlatform.join] as `token`.
/// - **Not** the same as an AWS access key or secret.
///
/// **IAM access key ID** + **secret access key** (+ optional **session token** for
/// temporary credentials):
/// - Used **only** if **your code** signs IVS control-plane HTTP requests from the
///   app ([IvsAwsSigV4ControlPlane], [IvsRealtimeTokenClient], or [IvsRealtimeStagesApi]
///   / [IvsChatApi] helpers).
/// - In a proper backend flow, these values exist **only on the server**; the mobile
///   app never sees them.
///
/// **IVS Chat** uses a separate **chat token** from
/// [CreateChatToken](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateChatToken.html)
/// — see [IvsLiveControlPlane.mintChatToken] and [IvsChatSession].
///
/// ## Where to read more
///
/// - Repository [README](https://github.com/vipulbansal/aws_ivs_realtime#readme)
///   (install, permissions, integration overview).
/// - [DOCUMENTATION.md](https://github.com/vipulbansal/aws_ivs_realtime/blob/main/DOCUMENTATION.md)
///   in the repo for channels, SigV4 service scope, and troubleshooting.
library;

export 'ivs_chat_api.dart';
export 'ivs_chat_session.dart';
export 'ivs_live_control_plane.dart';
export 'ivs_realtime_platform.dart';
export 'ivs_realtime_stages_api.dart';
export 'ivs_realtime_token_client.dart';
