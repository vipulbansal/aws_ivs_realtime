import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

/// Amazon **IVS Chat** control plane (`ivschat.<region>.amazonaws.com`), SigV4 service **`ivschat`**.
///
/// - [CreateRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateRoom.html)
/// - [DeleteRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_DeleteRoom.html)
/// - [CreateChatToken](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateChatToken.html)
///
/// WebSocket URL for clients: `wss://edge.ivschat.<region>.amazonaws.com` (see AWS Chat User Guide).
class IvsChatApi {
  Future<dynamic> _invoke({
    required String region,
    required AWSCredentials creds,
    required String path,
    required Map<String, Object?> body,
  }) async {
    final host = 'ivschat.$region.amazonaws.com';
    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(creds),
    );
    final scope = AWSCredentialScope(
      region: region,
      service: AWSService.ivschat,
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
    if (resp.statusCode == 204) {
      return null;
    }
    if (resp.statusCode != 200) {
      throw IvsChatApiException(resp.statusCode, text);
    }
    if (text.isEmpty) {
      return null;
    }
    return jsonDecode(text) as Map<String, dynamic>;
  }

  AWSCredentials _creds({
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
  }) =>
      AWSCredentials(accessKeyId, secretAccessKey, sessionToken);

  Future<Map<String, dynamic>> createRoom({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    required String name,
    int maximumMessageLength = 500,
    int maximumMessageRatePerSecond = 30,
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    final json = await _invoke(
      region: region,
      creds: creds,
      path: '/CreateRoom',
      body: {
        'name': name,
        'maximumMessageLength': maximumMessageLength,
        'maximumMessageRatePerSecond': maximumMessageRatePerSecond,
      },
    ) as Map<String, dynamic>;
    return json;
  }

  Future<void> deleteRoom({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    required String roomArn,
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    await _invoke(
      region: region,
      creds: creds,
      path: '/DeleteRoom',
      body: {'identifier': roomArn},
    );
  }

  /// Returns map with `token`, `tokenExpirationTime`, `sessionExpirationTime`.
  Future<Map<String, dynamic>> createChatToken({
    required String region,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    required String roomArn,
    required String userId,
    List<String> capabilities = const ['SEND_MESSAGE'],
    Map<String, String>? attributes,
    int sessionDurationInMinutes = 120,
  }) async {
    final creds = _creds(
      accessKeyId: accessKeyId,
      secretAccessKey: secretAccessKey,
      sessionToken: sessionToken,
    );
    final json = await _invoke(
      region: region,
      creds: creds,
      path: '/CreateChatToken',
      body: {
        'roomIdentifier': roomArn,
        'userId': userId,
        'capabilities': capabilities,
        'sessionDurationInMinutes': sessionDurationInMinutes,
        if (attributes != null && attributes.isNotEmpty) 'attributes': attributes,
      },
    ) as Map<String, dynamic>;
    return json;
  }
}

class IvsChatApiException implements Exception {
  IvsChatApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'IvsChatApiException: HTTP $statusCode $body';
}
