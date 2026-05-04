import 'dart:convert';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

/// Calls [CreateParticipantToken](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html)
/// using SigV4 and **long-lived IAM keys in the app** — demo only.
class IvsRealtimeTokenClient {
  /// Returns the opaque participant token string for [Stage.join] on native.
  Future<String> createParticipantToken({
    required String region,
    required String stageArn,
    required String accessKeyId,
    required String secretAccessKey,
    String? sessionToken,
    String? userId,
    int durationMinutes = 120,
    List<String> capabilities = const ['PUBLISH', 'SUBSCRIBE'],
  }) async {
    final creds = AWSCredentials(
      accessKeyId,
      secretAccessKey,
      sessionToken,
    );
    final signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(creds),
    );

    final host = 'ivsrealtime.$region.amazonaws.com';
    final payload = <String, Object?>{
      'stageArn': stageArn,
      'capabilities': capabilities,
      'duration': durationMinutes,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    };
    final body = utf8.encode(jsonEncode(payload));
    final uri = Uri(scheme: 'https', host: host, path: '/CreateParticipantToken');
    // Host is the ivsrealtime endpoint; SigV4 scope must use IAM service prefix `ivs`
    // (see AWS error: "Credential should be scoped to correct service: 'ivs'.").
    final scope = AWSCredentialScope(
      region: region,
      service: const AWSService('ivs'),
    );

    final request = AWSHttpRequest.post(
      uri,
      headers: {
        AWSHeaders.contentType: 'application/json',
        AWSHeaders.host: host,
      },
      body: body,
    );

    final signed = await signer.sign(
      request,
      credentialScope: scope,
    );
    final operation = signed.send();
    final resp = await operation.response;
    final text = await resp.decodeBody();
    if (resp.statusCode != 200) {
      throw IvsTokenException(
        'HTTP ${resp.statusCode}: $text',
      );
    }
    final json = jsonDecode(text) as Map<String, dynamic>;
    final pt = json['participantToken'] as Map<String, dynamic>?;
    final token = pt?['token'] as String?;
    if (token == null || token.isEmpty) {
      throw IvsTokenException('Missing participantToken.token in response: $text');
    }
    return token;
  }
}

class IvsTokenException implements Exception {
  IvsTokenException(this.message);
  final String message;
  @override
  String toString() => 'IvsTokenException: $message';
}
