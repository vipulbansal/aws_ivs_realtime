# aws_ivs_realtime

Flutter plugin for **Amazon IVS Real-Time**: **low-latency multi-participant live video** (stage / “broadcast” grid) on **Android** and **iOS**, plus optional **Amazon IVS Chat** for **room-style text messages** alongside the stream.

What you get:

- **Real-time live streaming (Stages)** — native **participant grid** (host and viewers), camera/mic publish, mute, leave; bridged with a **MethodChannel** and **platform view** ([`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart), [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart)).
- **Control plane in Dart (optional)** — create/list/delete **stages**, mint **participant tokens**, create/delete **chat rooms**, mint **chat tokens** — either by implementing **one** backend-facing interface ([`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)) or by using the built-in **SigV4-on-device** implementation ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart)) for prototypes only.
- **IVS Chat WebSocket** — [`IvsChatSession`](lib/ivs_chat_session.dart) after you obtain a chat token.
- **Runtime permissions** — [`permission_handler`](https://pub.dev/packages/permission_handler) before join/publish.

### Live streaming only vs live + chat

- **Streaming only (no chat):** use [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart) + the **platform view** ([`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart)) and a **participant token** from [`mintParticipantToken`](lib/ivs_live_control_plane.dart) / your backend. **Do not** create [`IvsChatSession`](lib/ivs_chat_session.dart), **do not** call [`mintChatToken`](lib/ivs_live_control_plane.dart) / [`createChatRoom`](lib/ivs_live_control_plane.dart), and **do not** add chat UI widgets. The native stage **never** shows a chat pane by itself—there is **no** plugin-wide “chat on/off” flag; chat appears only if **your app** wires it up.
- **Streaming + chat:** additionally connect [`IvsChatSession`](lib/ivs_chat_session.dart) and build your own message list / composer.
- **[`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)** lists chat APIs alongside Real-Time APIs so one implementation can power both products; you may still call **only** the stage-related methods from your UI—unused chat methods stay unused (no extra change inside this package).
- The **`example/`** app demonstrates **both** together for convenience; a minimal integration can be **video only**.

### Source repository, pub.dev, and where to run the demo

| What | URL / path |
|------|------------|
| **GitHub (browse source)** | [https://github.com/vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime) |
| **Clone** | `git clone https://github.com/vipulbansal/aws_ivs_realtime.git` |
| **Issues** | [https://github.com/vipulbansal/aws_ivs_realtime/issues](https://github.com/vipulbansal/aws_ivs_realtime/issues) |
| **Runnable example app** | Folder **`example/`** in that repository — [open `example/` on GitHub](https://github.com/vipulbansal/aws_ivs_realtime/tree/main/example) |
| **Published package** | [https://pub.dev/packages/aws_ivs_realtime](https://pub.dev/packages/aws_ivs_realtime) |
| **Sample app (app-only, no backend)** | [**aws_ivs_realtime_usage**](https://github.com/vipulbansal/aws_ivs_realtime_usage) — standalone Flutter repo: use the package **from the app only** (no separate backend) as a **reference for integration** |

> **Reference — app-only sample:** [**vipulbansal/aws_ivs_realtime_usage**](https://github.com/vipulbansal/aws_ivs_realtime_usage) is a **standalone Flutter project** (not the in-repo `example/`) that shows how to wire **`aws_ivs_realtime` without a backend**—ideal if you depend on **pub.dev** and want a full app tree to copy from. Clone: [https://github.com/vipulbansal/aws_ivs_realtime_usage](https://github.com/vipulbansal/aws_ivs_realtime_usage).

---

## Two layers (do not confuse them)

| Layer | Purpose | Key type |
|-------|---------|----------|
| **Native stage** | Render tiles + send/receive real-time A/V | [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart) needs only the **IVS participant token** (opaque string from AWS **CreateParticipantToken**). **Never** pass IAM access key / secret here. |
| **Control plane (Dart)** | Create stages, list stages, mint participant/chat tokens, delete resources | Either **your backend** (implement [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart)) or **IAM credentials inside the app** via [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) (non-production pattern). |

---

## Backend integration: implement **`IvsLiveControlPlane`**

If your AWS keys and SigV4 signing live **only on your servers**, the Flutter side should **`implements IvsLiveControlPlane`**.

### What you must do (no ambiguity)

1. **Create a Dart class** that **`implements IvsLiveControlPlane`** (see [`lib/ivs_live_control_plane.dart`](lib/ivs_live_control_plane.dart) for exact signatures).
2. **Implement every method** in that abstract class. Each method corresponds **one-to-one** to an AWS operation listed below. Your implementation typically:
   - forwards the method arguments to **your** HTTP/gRPC/mobile-BFF API using **your** URLs and auth; then  
   - parses **your** API’s JSON into the Dart return type shown.
3. **Your server** performs the real AWS call (with an IAM **role** or temporary credentials). The app **never** receives long-lived IAM user keys in this model.
4. **Reference:** [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) in this repo is the **same interface** already implemented using SigV4 from the device — use its source as a behavioral reference for what each operation is supposed to accomplish (then replace networking with calls to your backend).

This README **does not** define your REST paths or JSON field names; only the **Dart contract** is fixed.

### Methods you must implement (full contract)

| You implement | AWS operation (your backend must honor this semantics) | Dart return type |
|-----------------|---------------------------------------------------------|------------------|
| `mintParticipantToken` | [CreateParticipantToken](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html) | `Future<String>` — **only** the participant token string (same value as `participantToken.token` in the AWS JSON). |
| `listStages` | [ListStages](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListStages.html) | `Future<List<Map<String, dynamic>>>` — one map per stage summary (same information you would map from AWS `stageList` items). |
| `createStage` | [CreateStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateStage.html) | `Future<Map<String, dynamic>>` — stage object / metadata as maps (equivalent to parsing AWS `stage` + related fields your UI needs). |
| `deleteStage` | [DeleteStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_DeleteStage.html) | `Future<void>` |
| `createChatRoom` | [CreateRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateRoom.html) (IVS Chat) | `Future<Map<String, dynamic>>` — room resource (same semantics as AWS `room` in the response). |
| `deleteChatRoom` | [DeleteRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_DeleteRoom.html) | `Future<void>` |
| `mintChatToken` | [CreateChatToken](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateChatToken.html) | `Future<Map<String, dynamic>>` — token payload your app passes into [`IvsChatSession`](lib/ivs_chat_session.dart) (same logical fields AWS returns for a chat token). |

**Typical live flow with a backend:** `createStage` (once) → share **stage ARN** → for each participant `mintParticipantToken` → [`IvsRealtimePlatform.join(token: ...)`](lib/ivs_realtime_platform.dart) with native grid widget → optional: `createChatRoom` / `mintChatToken` / [`IvsChatSession`](lib/ivs_chat_session.dart) for messages.

### After you implement it: how to **use** `IvsLiveControlPlane` in your app

Implementing the interface is only half the work. You also **instantiate** your class and **call its methods** from your widgets / controllers, then **feed the return values** into the **other** types from this package.

| Object | Type | Role |
|--------|------|------|
| `control` | **Your** `implements IvsLiveControlPlane` | Talks to **your** backend (or wraps it). Produces tokens and stage/chat metadata. |
| `stage` | [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart) | Talks to **native** Android/iOS IVS Real-Time (join / leave / mute / events). **Does not** use your interface by itself — **you** call both. |
| Grid widget | `AndroidView` / `UiKitView` | Renders video tiles; see the **Platform view** subsection (under **App-only** below). |

**1) Live video (Stages)** — what goes where

1. Build `final control = MyBackendControlPlane(/* your HTTP client, base URL, auth */);` and `final stage = IvsRealtimePlatform();` (often `State` fields).
2. **Discover or create a stage** (optional): `await control.listStages(region: region)` for UI lists, or `final created = await control.createStage(region: region, name: name)`. Your implementation’s map should include something you can treat as **stage ARN** (same information as AWS **CreateStage** / **ListStages** — commonly an `arn` field on the stage object).
3. **Mint a participant token** for the current user:  
   `final participantToken = await control.mintParticipantToken(region: region, stageArn: stageArn, userId: optionalUserId, durationMinutes: 120, capabilities: const ['PUBLISH', 'SUBSCRIBE']);`  
   The returned **`String` is the only value** that ever goes to native join.
4. **Show the grid** in the widget tree (platform view, non-zero size) — same snippet as in the **Platform view** subsection under **App-only** below.
5. **Attach to the stage:**  
   `await stage.join(token: participantToken, publish: isHostOrPublisher);`  
   Mic permission is always requested; camera when `publish` is true.
6. **While live:** use `stage.setPublish`, `stage.setLocalStreamMuted`, listen to [`stage.stageConnectionEvents`](lib/ivs_realtime_platform.dart) for disconnect / host-ended flows.
7. **When done:** `await stage.leave();` and, if you no longer need the AWS stage, `await control.deleteStage(region: region, stageArn: stageArn)`.

Your backend’s JSON shapes are **yours**; the Dart side only needs to **extract** `String` / `Map` / `List` values that match the **meanings** in the table above so you can pass them into `join`, UI models, and chat below.

**2) IVS Chat (optional)** — chaining `IvsLiveControlPlane` → [`IvsChatSession`](lib/ivs_chat_session.dart)

1. **Room:** `final room = await control.createChatRoom(region: region, name: roomDisplayName);` — take **`roomArn`** (or equivalent) from the map your backend returns (AWS **CreateRoom** exposes the room ARN).
2. **Session:** `final chat = IvsChatSession();`
3. **Connect:** `await chat.connect(region: region, resolveChatToken: () async { final m = await control.mintChatToken(region: region, roomArn: roomArn, userId: stableUserId, attributes: {...}); final t = m['token'] as String?; if (t == null || t.isEmpty) throw StateError('no chat token'); return t; });`  
   [`IvsChatSession.connect`](lib/ivs_chat_session.dart) calls `resolveChatToken` again on **reconnect**, so each call should hit your backend for a **fresh** token (short-lived), not reuse one cached string forever.
4. **UI:** listen to `chat.lines` (`Stream<IvsChatLine>`) for incoming messages; use `chat.sendMessage` when the socket is open.
5. **Teardown:** `await chat.dispose();` and optionally `await control.deleteChatRoom(region: region, roomArn: roomArn)`.

**3) Summary**

- **`IvsLiveControlPlane`** = *how your Flutter code gets AWS-shaped data from your servers*.  
- **`IvsRealtimePlatform` + platform view** = *how that data becomes live video on device*.  
- **`IvsChatSession`** = *how chat tokens from the same interface become a WebSocket message stream*.

---

## App-only (no backend): where IAM keys and ARNs go

**Preferred built-in type:** [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) with an [`IvsAwsCredentialResolver`](lib/ivs_live_control_plane.dart) — a **zero-argument function** that returns `(accessKeyId, secretAccessKey, sessionToken?)`.

Put credentials **only** in one of these places (pick one strategy and stick to it):

| Strategy | Where you put **access key ID**, **secret key**, optional **session token** | Where you put **AWS region** and **stage ARN** |
|----------|-----------------------------------------------------------------------------|--------------------------------------------------|
| **A. Build-time defines** | Inside the resolver, read `const String.fromEnvironment('AWS_ACCESS_KEY_ID')`, `'AWS_SECRET_ACCESS_KEY'`, optional `'AWS_SESSION_TOKEN'` | Same pattern: `String.fromEnvironment('AWS_REGION', defaultValue: 'us-east-1')`, `String.fromEnvironment('IVS_STAGE_ARN')` |
| **B. Runtime UI or secure storage** | Resolver reads `TextEditingController.text`, [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage), env via [`Platform.environment`](https://api.dart.dev/stable/dart-io/Platform/environment.html), etc. | Passed as **variables** into `mintParticipantToken(region: ..., stageArn: ...)` from your own state (text fields, remote config, etc.) |
| **C. Literals in source** | **Do not** commit keys in Dart string literals to a public repository. | Same |

**Run / build with compile-time defines** (strategy A), from your app directory:

```text
flutter run \
  --dart-define=AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY_ID \
  --dart-define=AWS_SECRET_ACCESS_KEY=YOUR_SECRET_ACCESS_KEY \
  --dart-define=AWS_REGION=us-east-1 \
  --dart-define=IVS_STAGE_ARN=arn:aws:ivs:us-east-1:123456789012:stage/yourStageId
```

Optional: **who this participant is** on the stage (otherwise AWS / tiles only see an anonymous participant):

```text
  --dart-define=IVS_PARTICIPANT_USER_ID=alice-12345
```

Optional temporary credentials:

```text
  --dart-define=AWS_SESSION_TOKEN=YOUR_SESSION_TOKEN
```

**Minimal usage after keys are available:**

```dart
import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';

final ivs = IvsRealtimePlatform();
final control = IvsAwsSigV4ControlPlane(
  resolveCredentials: () => (
    accessKeyId: const String.fromEnvironment('AWS_ACCESS_KEY_ID'),
    secretAccessKey: const String.fromEnvironment('AWS_SECRET_ACCESS_KEY'),
    sessionToken: _opt('AWS_SESSION_TOKEN'),
  ),
);

String? _opt(String k) {
  const v = String.fromEnvironment(k, defaultValue: '');
  return v.isEmpty ? null : v;
}

Future<void> joinWithSigV4() async {
  const region = String.fromEnvironment('AWS_REGION', defaultValue: 'us-east-1');
  const stageArn = String.fromEnvironment('IVS_STAGE_ARN');
  const participantUserId = String.fromEnvironment('IVS_PARTICIPANT_USER_ID', defaultValue: '');

  final token = await control.mintParticipantToken(
    region: region,
    stageArn: stageArn,
    // Sent to AWS CreateParticipantToken as `userId` — use your real signed-in id / handle.
    userId: participantUserId.isEmpty ? null : participantUserId,
  );
  await ivs.join(token: token, publish: true);
}
```

**Where the “name” comes from (app-only is the same idea as backend):**

- **Stage / live video:** the README snippet above did not show a name before because **`userId` is optional**. Pass **`userId:`** into [`mintParticipantToken`](lib/ivs_live_control_plane.dart) (from auth, profile, or `--dart-define=IVS_PARTICIPANT_USER_ID` as a stand-in). That value is what AWS associates with the participant for the Real-Time session; the native grid labels participants using IVS metadata—not a hardcoded “Flutter demo user” from this package.
- **IVS Chat sender labels:** set when you call **`control.mintChatToken(..., userId: ..., attributes: {'displayName': 'Alice Smith'})`**. Your UI reads [`IvsChatLine`](lib/ivs_chat_session.dart) events; other clients see the attributes / user id your app sent. There is no separate “name” field on [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart)—only the opaque **participant token**—so **identity for chat is always** via **`mintChatToken`** (or your backend’s equivalent).

**Important:** `mintParticipantToken` + `join` **do not** draw anything on screen by themselves. You **must** embed the native **participant grid** with a Flutter **platform view** or you will hear/encode media but **see no tiles / video**.

### Platform view: show the live grid (AndroidView / UiKitView)

Use the constant [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart) (`ivs_stage_view`). Match the plugin’s codec registration with **`StandardMessageCodec()`**. Give the view a **non-zero** size (`Expanded`, `SizedBox.expand`, etc.). **Backend and app-only flows both use this widget** — only the way you obtain the participant token differs.

```dart
import 'dart:io';

import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';
import 'package:flutter/cupertino.dart' show UiKitView;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Widget ivsParticipantGrid() {
  if (!ivsNativeStageSupported) {
    return const Center(child: Text('Stages are only on Android and iOS.'));
  }
  if (Platform.isAndroid) {
    return AndroidView(
      viewType: AwsIvsRealtimePlatformView.viewType,
      layoutDirection: TextDirection.ltr,
      creationParamsCodec: StandardMessageCodec(),
    );
  }
  return UiKitView(
    viewType: AwsIvsRealtimePlatformView.viewType,
    layoutDirection: TextDirection.ltr,
    creationParamsCodec: StandardMessageCodec(),
  );
}

// Typical layout: put the platform view in an Expanded, then call joinWithSigV4()
// (or join with a backend-minted token). If tiles stay blank after join, call
// ivs.refreshStageBindings() once from a post-frame callback — see DOCUMENTATION.md.
```

### Listing stages, showing them in Flutter UI, and joining an **existing** stage

The same [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) (or your [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) backend implementation) exposes **`listStages`**, **`createStage`**, **`deleteStage`**, chat helpers, etc. Typical **Dart-only** flow:

1. **`await control.listStages(region: region)`** → `List<Map<String, dynamic>>` (each map is an AWS **stage** summary; at minimum expect an **`arn`** and often a **`name`**).
2. **Render** that list with normal Flutter widgets (`ListView`, `ListTile`, `DataTable`, …) — this is where you choose titles, subtitles, pull-to-refresh, empty states, etc.
3. When the user picks a row, read **`stage['arn'] as String`** and call **`await control.mintParticipantToken(region: region, stageArn: arn, userId: …)`**, then **`await ivs.join(token: token, publish: …)`** with the platform view already in the tree.

Optional: **`await control.createStage(region: region, name: 'my-show-001', tags: {...})`** returns the created **stage** `Map` (includes **`arn`**); mint a token for that ARN to go live as host.

```dart
import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';

Future<void> refreshStageCatalog({
  required IvsAwsSigV4ControlPlane control,
  required String region,
  required void Function(List<Map<String, dynamic>> stages) onStages,
}) async {
  final stages = await control.listStages(region: region);
  onStages(stages);
}

Future<void> joinExistingStageFromRow({
  required IvsAwsSigV4ControlPlane control,
  required IvsRealtimePlatform ivs,
  required String region,
  required String stageArn,
  String? participantUserId,
  bool publish = false,
}) async {
  final token = await control.mintParticipantToken(
    region: region,
    stageArn: stageArn,
    userId: participantUserId,
  );
  await ivs.join(token: token, publish: publish);
}

// Example list wiring (simplified — use setState / provider / bloc in a real app):
Widget stagePicker({
  required List<Map<String, dynamic>> stages,
  required void Function(String arn) onPickArn,
}) {
  return ListView.builder(
    itemCount: stages.length,
    itemBuilder: (context, i) {
      final s = stages[i];
      final arn = s['arn'] as String?;
      final title = s['name'] as String? ?? arn ?? 'Stage';
      return ListTile(
        title: Text(title),
        subtitle: arn != null
            ? Text(arn, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        onTap: arn == null ? null : () => onPickArn(arn),
      );
    },
  );
}
```

If you use **tags** to mark which stages are “live” (as the repo **`example/`** does with [`IvsRealtimeStagesApi.tagStatus`](lib/ivs_realtime_stages_api.dart)), filter in Dart with **`stages.where(...)`** before building the list — the API returns **all** stages the credentials can see, not only live ones.

---

## Native stage: embed the grid and join (after you have a participant token)

This is the **same** for **backend** or **app-only** paths: once you have a **participant token** string, the native video UI always goes through the **platform view** above plus [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart).

1. **Host app:** Android **`minSdk = 28`** on your **app** module; iOS **14+**; permissions and `permission_handler` iOS preprocessor flags — see [Requirements](#requirements) and [Install](#install).
2. **Widget:** `AndroidView` (Android) or `UiKitView` (iOS) — same **Platform view** snippet as in the **App-only** section above (required for any participant token source).
3. **Join:** `await ivs.join(token: participantTokenString, publish: hostPublishesA/V);`
4. **Events / lifecycle:** subscribe to [`stageConnectionEvents`](lib/ivs_realtime_platform.dart); call [`leave`](lib/ivs_realtime_platform.dart) when done; optionally [`refreshStageBindings`](lib/ivs_realtime_platform.dart) after first frame if tiles misbind — details in [DOCUMENTATION.md](DOCUMENTATION.md).

---

## AWS keys vs participant token

| String | Pass to `join(token:)`? | Role |
|--------|-------------------------|------|
| **Participant token** | **Yes** | Output of **CreateParticipantToken**; consumed by native IVS SDK. |
| **Access key ID / secret / session token** | **No** | Only for **signing AWS HTTPS** in Dart ([`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart)) or on your server. |

---

## What you need to know first

| Step | Responsibility |
|------|----------------|
| 1. Stage exists | You (console, IaC, `createStage` via control plane, etc.). |
| 2. Participant token | `mintParticipantToken` on your [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) implementation **or** [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) / [`IvsRealtimeTokenClient`](lib/ivs_realtime_token_client.dart). |
| 3. Native UI + join | [`AwsIvsRealtimePlatformView.viewType`](lib/ivs_realtime_platform.dart) + [`IvsRealtimePlatform.join`](lib/ivs_realtime_platform.dart). |

---

## Where everything lives in the package

| Goal | API |
|------|-----|
| Native join / leave / mute / publish | [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart) |
| Native grid `viewType` | [`AwsIvsRealtimePlatformView`](lib/ivs_realtime_platform.dart) |
| **Backend-shaped control plane (you implement)** | [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) |
| **SigV4 on device (implements same interface)** | [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) |
| Low-level participant token HTTP + SigV4 | [`IvsRealtimeTokenClient`](lib/ivs_realtime_token_client.dart) |
| Stage REST helpers (keys passed per call) | [`IvsRealtimeStagesApi`](lib/ivs_realtime_stages_api.dart) |
| Chat REST helpers | [`IvsChatApi`](lib/ivs_chat_api.dart) |
| Chat WebSocket | [`IvsChatSession`](lib/ivs_chat_session.dart) |

---

## Requirements

| Platform | Minimum | Notes |
|----------|---------|--------|
| Android  | API 28  | `RECORD_AUDIO`, `CAMERA` when publishing |
| iOS      | 14.0    | `NSMicrophoneUsageDescription`, `NSCameraUsageDescription` |

Native SDKs: Android Maven `ivs-broadcast` stages AAR (**1.41.0** in this repo); iOS CocoaPods `AmazonIVSBroadcast/Stages` (**~> 1.36.0** in the podspec).

---

## Install

From [pub.dev](https://pub.dev/packages/aws_ivs_realtime):

```yaml
dependencies:
  aws_ivs_realtime: ^0.1.4
```

From Git:

```yaml
dependencies:
  aws_ivs_realtime:
    git:
      url: https://github.com/vipulbansal/aws_ivs_realtime.git
```

### Android — **your** `AndroidManifest.xml` (required)

The plugin’s own [`android/src/main/AndroidManifest.xml`](android/src/main/AndroidManifest.xml) does **not** declare network or A/V permissions. **Your application module** must include them so the merged app manifest allows IVS Real-Time and `permission_handler` prompts.

Inside **`android/app/src/main/AndroidManifest.xml`**, as direct children of `<manifest>` (before `<application>`), add at least:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

- **`INTERNET`** — AWS HTTPS, IVS signaling, IVS Chat WebSocket.  
- **`RECORD_AUDIO`** — join stage (subscribe/publish audio).  
- **`CAMERA`** — publish video when `join(..., publish: true)` / host camera.  
- **`MODIFY_AUDIO_SETTINGS`** — used in the reference example for audio routing; safe to keep for parity with [`example/android/app/src/main/AndroidManifest.xml`](example/android/app/src/main/AndroidManifest.xml).

Declaring these is **not** optional: the Dart side only **requests** runtime access via [`permission_handler`](https://pub.dev/packages/permission_handler); the OS still requires the `<uses-permission>` entries in **your** manifest.

### iOS — **your** `Info.plist` + `Podfile` (required)

Add (or merge) usage descriptions in **`ios/Runner/Info.plist`** — replace the strings with copy appropriate for your app:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera is used to publish your video to the IVS Real-Time stage when you go live.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone is used to publish and receive audio on the IVS Real-Time stage.</string>
```

In **`ios/Podfile`**, use at least **iOS 14** and, if CocoaPods requires it, `use_modular_headers!` (see [`example/ios/Podfile`](example/ios/Podfile)).

**`permission_handler` on iOS:** copy the `GCC_PREPROCESSOR_DEFINITIONS` block from `example/ios/Podfile` `post_install` (`PERMISSION_MICROPHONE=1`, `PERMISSION_CAMERA=1`) so microphone/camera code is compiled into `permission_handler_apple`; otherwise dialogs never appear.

---

## Customizing **buttons and layout** around the live stream (Flutter / Dart)

The **native participant grid** (video tiles inside [`AndroidView`](https://api.flutter.dev/flutter/widgets/AndroidView-class.html) / [`UiKitView`](https://api.flutter.dev/flutter/cupertino/UiKitView-class.html)) is drawn by the plugin’s **embedded** Android / iOS UI. You **do not** need to edit native XML or Swift to:

- Add **lobbies**, **toolbars**, **bottom sheets**, **navigation**, **theme colors**, typography, padding, or **any Flutter layout** around the platform view (`Stack`, `Scaffold`, `SafeArea`, `Row`/`Column`, etc.).
- Build **lists of stages**, **Join / Leave** buttons, host vs viewer toggles, or overlays (mute, end stream) — all in **Dart**, calling [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) / [`IvsAwsSigV4ControlPlane`](lib/ivs_live_control_plane.dart) + [`IvsRealtimePlatform`](lib/ivs_realtime_platform.dart) as in the **Listing stages…** snippet under **App-only** earlier in this README.

Treat the platform view like a **single embedded surface**: you control **everything outside and around it** with normal Flutter widgets. Changing **how each internal video tile** looks (pixel-level native skin) is outside typical app integration and is **not** required for custom product UI.

By default, each native tile is **video only** (no subscribe/mute/dB strip). Call [`IvsRealtimePlatform.setShowParticipantStateOverlay`](lib/ivs_realtime_platform.dart) with `true` before `join` if you want the previous demo-style labels on the tiles.

---

## Example app (run the demo from GitHub)

The **authoritative runnable project** lives in the **`example/`** directory of [https://github.com/vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime) ([`example/` tree](https://github.com/vipulbansal/aws_ivs_realtime/tree/main/example)). Use it to see **lobby → full-screen live → optional IVS Chat**, plus a switch between **SigV4 on device** and a **stub** [`IvsLiveControlPlane`](lib/ivs_live_control_plane.dart) implementation.

**App-only reference (no backend):** for a **separate** Flutter app that consumes the published package and does **not** use a backend, see [**aws_ivs_realtime_usage**](https://github.com/vipulbansal/aws_ivs_realtime_usage) on GitHub — [https://github.com/vipulbansal/aws_ivs_realtime_usage](https://github.com/vipulbansal/aws_ivs_realtime_usage). Listed as **Sample app (app-only, no backend)** in the table at the top of this README.

**Run locally** (after you clone `https://github.com/vipulbansal/aws_ivs_realtime.git`):

```bash
cd aws_ivs_realtime/example
flutter pub get
flutter run
```

Use a **physical device or emulator** that meets [Requirements](#requirements). For SigV4 from defines, pass the same `--dart-define=...` values documented under **App-only** in this README.

If you depend on the package from **pub.dev** only, your own app will not contain this `example/` tree — **clone the GitHub repository** whenever you want to run or copy from the demo.

---

## Documentation

Channels, SigV4 service scope (`ivs` vs `ivsrealtime`), troubleshooting: [DOCUMENTATION.md](DOCUMENTATION.md).

---

## Contributing

Issues and pull requests: [https://github.com/vipulbansal/aws_ivs_realtime](https://github.com/vipulbansal/aws_ivs_realtime) (same repository linked in **Source repository** at the top of this README).

---

## Publishing (maintainers)

`dart pub publish` from package root. Do not ship IAM credentials in app binaries or public repos.

---

## License

See [LICENSE](LICENSE).
