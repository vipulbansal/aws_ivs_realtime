import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _channelName = 'aws_ivs_realtime/stage';
const _stageEventsChannelName = 'aws_ivs_realtime/stage_events';

/// Platform view type for [AndroidView] / [UiKitView] (must match native factories).
abstract final class AwsIvsRealtimePlatformView {
  static const String viewType = 'ivs_stage_view';
}

/// True when this plugin provides the native IVS Real-Time stage (Android / iOS).
bool get ivsNativeStageSupported =>
    Platform.isAndroid || Platform.isIOS;

/// Native IVS Real-Time stage controls (Android + iOS).
///
/// This class talks to the **Amazon IVS Broadcast** stage SDK over a method channel.
/// It does **not** call AWS IAM or mint tokens by itself. Obtain a **participant
/// token** first (typically from your backend); see [join].
class IvsRealtimePlatform {
  IvsRealtimePlatform()
      : _channel = const MethodChannel(_channelName),
        _stageEvents = const EventChannel(_stageEventsChannelName);

  final MethodChannel _channel;
  final EventChannel _stageEvents;

  /// Fired when the native stage session ends after having been connected (e.g. host ended
  /// the stream, or the server closed the session). Map includes at least `event` →
  /// `"disconnected"`. Some failures are surfaced here after SDK errors as well as the
  /// normal disconnected state.
  Stream<Map<String, dynamic>> get stageConnectionEvents =>
      _stageEvents.receiveBroadcastStream().map(_decodeStageEvent);

  /// Joins the stage with Amazon's **participant token**, or leaves if already connected.
  ///
  /// [token] must be the string from
  /// [CreateParticipantToken](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html)
  /// (`participantToken.token` in the JSON response). It is **not** an IAM access key
  /// ID, secret access key, or session token.
  ///
  /// [publish] controls whether this participant publishes camera + microphone
  /// (host-style) or is receive-only, subject to the capabilities encoded in the token.
  Future<void> join({required String token, required bool publish}) async {
    if (!ivsNativeStageSupported) {
      throw UnsupportedError(
        'IVS Real-Time native stage is only available on Android and iOS.',
      );
    }
    await _ensureMicrophonePermission();
    if (publish) {
      await _ensureCameraPermission();
    }
    try {
      await _channel.invokeMethod<void>('join', <String, Object?>{
        'token': token,
        'publish': publish,
      });
    } on PlatformException catch (e) {
      throw IvsStageException(e.message ?? e.code, e);
    }
  }

  Future<void> leave() async {
    if (!ivsNativeStageSupported) return;
    await _channel.invokeMethod<void>('leave');
  }

  Future<void> setPublish(bool enabled) async {
    if (!ivsNativeStageSupported) return;
    if (enabled) {
      await _ensureCameraPermission();
    }
    await _channel.invokeMethod<void>('setPublish', enabled);
  }

  /// Re-runs native [Stage.refreshStrategy] and rebinds the participant grid (e.g. after
  /// the platform view gets its first real layout).
  Future<void> refreshStageBindings() async {
    if (!ivsNativeStageSupported) return;
    try {
      await _channel.invokeMethod<void>('refreshStageBindings');
    } on PlatformException catch (_) {
      // Best-effort; join already succeeded.
    }
  }

  /// Mute/unmute what you publish to the stage (host only; no-op if not publishing).
  Future<void> setLocalStreamMuted({
    required bool micMuted,
    required bool cameraMuted,
  }) async {
    if (!ivsNativeStageSupported) return;
    try {
      await _channel.invokeMethod<void>(
        'setLocalStreamMuted',
        <String, Object?>{
          'micMuted': micMuted,
          'cameraMuted': cameraMuted,
        },
      );
    } on PlatformException catch (_) {}
  }
}

Future<void> _ensureMicrophonePermission() async {
  final status = await Permission.microphone.request();
  if (status.isGranted || status.isLimited) return;
  if (status.isPermanentlyDenied) {
    throw IvsStageException(
      'Microphone access was denied. Enable the microphone in Settings to join the stage.',
    );
  }
  throw IvsStageException(
    'Microphone permission is required to join the IVS Real-Time stage.',
  );
}

Future<void> _ensureCameraPermission() async {
  final status = await Permission.camera.request();
  if (status.isGranted || status.isLimited) return;
  if (status.isPermanentlyDenied) {
    throw IvsStageException(
      'Camera access was denied. Enable the camera in Settings to publish video.',
    );
  }
  throw IvsStageException(
    'Camera permission is required to publish video to the stage.',
  );
}

Map<String, dynamic> _decodeStageEvent(dynamic e) {
  if (e is Map) {
    return e.map((k, v) => MapEntry(k.toString(), v));
  }
  return <String, dynamic>{'event': e.toString()};
}

class IvsStageException implements Exception {
  IvsStageException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'IvsStageException: $message';
}
