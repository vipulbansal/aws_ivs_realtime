import 'ivs_chat_api.dart';
import 'ivs_realtime_stages_api.dart';
import 'ivs_realtime_token_client.dart';

/// Snapshot of AWS IAM-style credentials for [IvsAwsSigV4ControlPlane].
///
/// For a backend-driven app, implement [IvsLiveControlPlane] instead and do not
/// ship long-lived keys in the client.
typedef IvsAwsCredentialSnapshot = ({
  String accessKeyId,
  String secretAccessKey,
  String? sessionToken,
});

typedef IvsAwsCredentialResolver = IvsAwsCredentialSnapshot Function();

/// All IVS Real-Time + IVS Chat **control plane** operations this demo needs.
///
/// - **Option A — Flutter / SigV4:** use [IvsAwsSigV4ControlPlane] with [IvsAwsCredentialResolver]
///   (current demo: keys from text fields).
/// - **Option B — Backend:** implement this interface with HTTPS calls to your API
///   (no IAM secrets in the app; return the same logical data AWS would).
abstract class IvsLiveControlPlane {
  /// [CreateParticipantToken](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateParticipantToken.html)
  Future<String> mintParticipantToken({
    required String region,
    required String stageArn,
    String? userId,
    int durationMinutes = 120,
    List<String> capabilities = const ['PUBLISH', 'SUBSCRIBE'],
  });

  /// [ListStages](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_ListStages.html)
  Future<List<Map<String, dynamic>>> listStages({
    required String region,
    int maxResults = 50,
    int maxPages = 10,
  });

  /// [CreateStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_CreateStage.html)
  Future<Map<String, dynamic>> createStage({
    required String region,
    required String name,
    Map<String, String> tags = const {},
  });

  /// [DeleteStage](https://docs.aws.amazon.com/ivs/latest/RealTimeAPIReference/API_DeleteStage.html)
  Future<void> deleteStage({
    required String region,
    required String stageArn,
  });

  /// [CreateRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateRoom.html)
  Future<Map<String, dynamic>> createChatRoom({
    required String region,
    required String name,
    int maximumMessageLength = 500,
    int maximumMessageRatePerSecond = 30,
  });

  /// [DeleteRoom](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_DeleteRoom.html)
  Future<void> deleteChatRoom({
    required String region,
    required String roomArn,
  });

  /// [CreateChatToken](https://docs.aws.amazon.com/ivs/latest/ChatAPIReference/API_CreateChatToken.html)
  Future<Map<String, dynamic>> mintChatToken({
    required String region,
    required String roomArn,
    required String userId,
    List<String> capabilities = const ['SEND_MESSAGE'],
    Map<String, String>? attributes,
    int sessionDurationInMinutes = 120,
  });
}

/// Default implementation: SigV4 from the device using [IvsAwsCredentialResolver].
///
/// **Not for production** if [resolver] returns long-lived IAM user keys.
class IvsAwsSigV4ControlPlane implements IvsLiveControlPlane {
  IvsAwsSigV4ControlPlane({required this.resolveCredentials});

  final IvsAwsCredentialResolver resolveCredentials;

  final _tokenClient = IvsRealtimeTokenClient();
  final _stagesApi = IvsRealtimeStagesApi();
  final _chatApi = IvsChatApi();

  @override
  Future<String> mintParticipantToken({
    required String region,
    required String stageArn,
    String? userId,
    int durationMinutes = 120,
    List<String> capabilities = const ['PUBLISH', 'SUBSCRIBE'],
  }) async {
    final c = resolveCredentials();
    return _tokenClient.createParticipantToken(
      region: region,
      stageArn: stageArn,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      userId: userId,
      durationMinutes: durationMinutes,
      capabilities: capabilities,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listStages({
    required String region,
    int maxResults = 50,
    int maxPages = 10,
  }) async {
    final c = resolveCredentials();
    return _stagesApi.listStages(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      maxResults: maxResults,
      maxPages: maxPages,
    );
  }

  @override
  Future<Map<String, dynamic>> createStage({
    required String region,
    required String name,
    Map<String, String> tags = const {},
  }) async {
    final c = resolveCredentials();
    return _stagesApi.createStage(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      name: name,
      tags: tags,
    );
  }

  @override
  Future<void> deleteStage({
    required String region,
    required String stageArn,
  }) async {
    final c = resolveCredentials();
    return _stagesApi.deleteStage(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      arn: stageArn,
    );
  }

  @override
  Future<Map<String, dynamic>> createChatRoom({
    required String region,
    required String name,
    int maximumMessageLength = 500,
    int maximumMessageRatePerSecond = 30,
  }) async {
    final c = resolveCredentials();
    return _chatApi.createRoom(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      name: name,
      maximumMessageLength: maximumMessageLength,
      maximumMessageRatePerSecond: maximumMessageRatePerSecond,
    );
  }

  @override
  Future<void> deleteChatRoom({
    required String region,
    required String roomArn,
  }) async {
    final c = resolveCredentials();
    return _chatApi.deleteRoom(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      roomArn: roomArn,
    );
  }

  @override
  Future<Map<String, dynamic>> mintChatToken({
    required String region,
    required String roomArn,
    required String userId,
    List<String> capabilities = const ['SEND_MESSAGE'],
    Map<String, String>? attributes,
    int sessionDurationInMinutes = 120,
  }) async {
    final c = resolveCredentials();
    return _chatApi.createChatToken(
      region: region,
      accessKeyId: c.accessKeyId,
      secretAccessKey: c.secretAccessKey,
      sessionToken: c.sessionToken,
      roomArn: roomArn,
      userId: userId,
      capabilities: capabilities,
      attributes: attributes,
      sessionDurationInMinutes: sessionDurationInMinutes,
    );
  }
}
