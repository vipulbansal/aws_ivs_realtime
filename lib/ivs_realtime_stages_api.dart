import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

/// IVS Real-Time control plane calls on `ivsrealtime.<region>.amazonaws.com`
/// with SigV4 scope service **`ivs`** (same as [CreateParticipantToken]).
///
/// See:
/// - [ListStages](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListStages.html)
/// - [CreateStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateStage.html)
/// - [DeleteStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_DeleteStage.html)
class IvsRealtimeStagesApi {
  /// Tag keys used by this demo app (filter + display).
  static const tagTitle = 'demoTitle';
  static const tagDescription = 'demoDescription';
  static const tagStatus = 'demoStatus';
  /// IVS Chat room ARN (`arn:aws:ivschat:...:room/...`) for [IvsChatApi] / WebSocket.
  static const tagChatRoomArn = 'demoChatRoomArn';
  static const statusLive = 'live';
  static const statusEnded = 'ended';

  Future<Map<String, dynamic>> _post({
    required String region,
    required AWSCredentials creds,
    required String path,
    required Map<String, Object?> body,
  }) async {
    final host = 'ivsrealtime.$region.amazonaws.com';
    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(creds),
    );
    final scope = AWSCredentialScope(
      region: region,
      service: const AWSService('ivs'),
    );
    final bodyBytes = utf8.encode(jsonEncode(body));
    final uri = Uri(scheme: 'https', host: host, path: path);
    final request = AWSHttpRequest.post(
      uri,
      headers: {
        AWSHeaders.contentType: 'application/json',
        AWSHeaders.host: host,
      },
      body: bodyBytes,
    );
    final signed = await signer.sign(request, credentialScope: scope);
    final resp = await signed.send().response;
    final text = await resp.decodeBody();
    if (resp.statusCode != 200) {
      throw IvsStagesApiException(resp.statusCode, text);
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  AWSCredentials _creds({
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
  }) =>
      AWSCredentials(accessKeyId, secretAccessKey, sessionToken);

  /// Lists stages (paginates up to [maxPages] with [maxResults] per call).
  Future<List<Map<String, dynamic>>> listStages({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    int maxResults = 50,
    int maxPages = 10,
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    final out = <Map<String, dynamic>>[];
    String? nextToken;
    for (var page = 0; page < maxPages; page++) {
      final body = <String, Object?>{
        'maxResults': maxResults,
        if (nextToken != null && nextToken.isNotEmpty) 'nextToken': nextToken,
      };
      final json = await _post(
        region: region,
        creds: creds,
        path: '/ListStages',
        body: body,
      );
      final stages = json['stages'] as List<dynamic>?;
      if (stages != null) {
        for (final s in stages) {
          if (s is Map<String, dynamic>) {
            out.add(s);
          } else if (s is Map) {
            out.add(Map<String, dynamic>.from(s));
          }
        }
      }
      nextToken = json['nextToken'] as String?;
      if (nextToken == null || nextToken.isEmpty) break;
    }
    return out;
  }

  /// Creates a stage with optional [name] (API pattern `[a-zA-Z0-9-_]*`) and [tags].
  /// Returns the `stage` map from the response (includes `arn`, `name`, `tags`).
  Future<Map<String, dynamic>> createStage({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    required String name,
    Map<String, String> tags = const {},
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    final json = await _post(
      region: region,
      creds: creds,
      path: '/CreateStage',
      body: {
        'name': name,
        'tags': tags,
      },
    );
    final stage = json['stage'];
    if (stage is! Map<String, dynamic>) {
      throw IvsStagesApiException(0, 'Missing stage in CreateStage response: $json');
    }
    return stage;
  }

  Future<void> deleteStage({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    required String arn,
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    await _post(
      region: region,
      creds: creds,
      path: '/DeleteStage',
      body: {'arn': arn},
    );
  }
}

class IvsStagesApiException implements Exception {
  IvsStagesApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'IvsStagesApiException: HTTP $statusCode $body';
}

/// Builds a valid CreateStage `name` and copies title/description into tags.
({String name, Map<String, String> tags}) buildStageNameAndTags({
  required String title,
  required String description,
}) {
  final slug = _stageNameFromTitle(title);
  final tags = <String, String>{
    IvsRealtimeStagesApi.tagTitle: title.trim().length > 256
        ? title.trim().substring(0, 256)
        : title.trim(),
    IvsRealtimeStagesApi.tagDescription: description.trim().length > 256
        ? description.trim().substring(0, 256)
        : description.trim(),
    IvsRealtimeStagesApi.tagStatus: IvsRealtimeStagesApi.statusLive,
  };
  return (name: slug, tags: tags);
}

String _stageNameFromTitle(String title) {
  final base = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\-_]'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .trim();
  final core = base.isEmpty ? 'live' : base;
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  var name = '$core-$suffix';
  if (name.length > 128) {
    name = name.substring(0, 128);
  }
  return name;
}

/// Parses tag map from stage JSON (may be null).
Map<String, String> parseStageTags(Map<String, dynamic> stage) {
  final t = stage['tags'];
  if (t is Map) {
    return t.map((k, v) => MapEntry('$k', '$v'));
  }
  return {};
}

String stageTitle(Map<String, dynamic> stage) {
  final tags = parseStageTags(stage);
  return tags[IvsRealtimeStagesApi.tagTitle]?.trim().isNotEmpty == true
      ? tags[IvsRealtimeStagesApi.tagTitle]!.trim()
      : (stage['name'] as String? ?? stage['arn'] as String? ?? 'Stage');
}

String stageDescription(Map<String, dynamic> stage) {
  final tags = parseStageTags(stage);
  return tags[IvsRealtimeStagesApi.tagDescription]?.trim() ?? '';
}

String? stageArn(Map<String, dynamic> stage) => stage['arn'] as String?;

String? chatRoomArnFromStage(Map<String, dynamic> stage) {
  final tags = parseStageTags(stage);
  final v = tags[IvsRealtimeStagesApi.tagChatRoomArn]?.trim();
  if (v == null || v.isEmpty) return null;
  return v;
}

bool stageIsLiveDemo(Map<String, dynamic> stage) {
  final tags = parseStageTags(stage);
  return tags[IvsRealtimeStagesApi.tagStatus] == IvsRealtimeStagesApi.statusLive;
}
