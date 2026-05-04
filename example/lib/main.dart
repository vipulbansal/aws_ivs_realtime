import 'dart:async';

import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';
import 'package:flutter/material.dart';

import 'full_screen_live_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IvsDemoApp());
}

class IvsDemoApp extends StatelessWidget {
  const IvsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IVS Real-Time (demo)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const IvsDemoPage(),
    );
  }
}

class IvsDemoPage extends StatefulWidget {
  const IvsDemoPage({super.key});

  @override
  State<IvsDemoPage> createState() => _IvsDemoPageState();
}

class _IvsDemoPageState extends State<IvsDemoPage> {
  final _region = TextEditingController(
    text: const String.fromEnvironment('AWS_REGION', defaultValue: ''),
  );
  final _stageArn = TextEditingController(
    text: const String.fromEnvironment('AWS_STAGE_ARN', defaultValue: ''),
  );
  final _accessKey = TextEditingController(
    text: const String.fromEnvironment('AWS_ACCESS_KEY_ID', defaultValue: ''),
  );
  final _secretKey = TextEditingController(
    text: const String.fromEnvironment('AWS_SECRET_ACCESS_KEY', defaultValue: ''),
  );
  final _sessionToken = TextEditingController(
    text: const String.fromEnvironment('AWS_SESSION_TOKEN', defaultValue: ''),
  );
  final _userId = TextEditingController(text: 'flutter-demo');

  final _stage = IvsRealtimePlatform();

  /// SigV4 on-device (demo) or swap for your own [IvsLiveControlPlane] (backend).
  late final IvsLiveControlPlane _controlPlane;

  bool _publish = true;
  bool _busy = false;
  String? _lastToken;
  String? _status;

  /// Stages in this account/region with tag `demoStatus=live` (AWS-only catalog).
  List<Map<String, dynamic>> _liveStages = [];

  /// Stage ARN created during **Go live** in this session (so we can [DeleteStage]).
  String? _hostStageArn;

  /// IVS Chat room ARN for the current host session ([DeleteRoom] on end).
  String? _hostChatRoomArn;

  @override
  void initState() {
    super.initState();
    _controlPlane = IvsAwsSigV4ControlPlane(
      resolveCredentials: () => (
        accessKeyId: _accessKey.text.trim(),
        secretAccessKey: _secretKey.text.trim(),
        sessionToken: _session(),
      ),
    );
    // Clears every AWS stage tagged demoStatus=live (and linked chat rooms). Remove this block
    // when you no longer want automatic cleanup on each cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_purgeAllLiveDemoStagesOnBoot());
    });
  }

  @override
  void dispose() {
    unawaited(_stage.leave());
    _region.dispose();
    _stageArn.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _sessionToken.dispose();
    _userId.dispose();
    super.dispose();
  }

  String? _session() =>
      _sessionToken.text.trim().isEmpty ? null : _sessionToken.text.trim();

  /// Deletes all demo “live” stages on AWS (same filter as the lobby list) and optional chat rooms.
  Future<void> _purgeAllLiveDemoStagesOnBoot() async {
    setState(() {
      _busy = true;
      _status = 'Clearing demo live stages on AWS…';
    });
    await _stage.leave();
    var deletedStages = 0;
    var deletedRooms = 0;
    final failures = <String>[];
    try {
      final all = await _controlPlane.listStages(
        region: _region.text.trim(),
      );
      final live = all.where(stageIsLiveDemo).toList();
      for (final s in live) {
        final arn = stageArn(s);
        if (arn == null || arn.isEmpty) continue;
        final roomArn = chatRoomArnFromStage(s);
        if (roomArn != null && roomArn.isNotEmpty) {
          try {
            await _controlPlane.deleteChatRoom(
              region: _region.text.trim(),
              roomArn: roomArn,
            );
            deletedRooms++;
          } catch (e) {
            failures.add('chat: $e');
          }
        }
        try {
          await _controlPlane.deleteStage(
            region: _region.text.trim(),
            stageArn: arn,
          );
          deletedStages++;
        } catch (e) {
          failures.add('stage $arn: $e');
        }
      }
      _hostStageArn = null;
      _hostChatRoomArn = null;
      if (!mounted) return;
      final survivors = await _controlPlane.listStages(
        region: _region.text.trim(),
      );
      final stillLive = survivors.where(stageIsLiveDemo).toList();
      setState(() {
        _liveStages = stillLive;
        final errTail = failures.isEmpty
            ? ''
            : ' (${failures.length} error(s); first: ${failures.first})';
        _status = stillLive.isEmpty
            ? 'Cleared demo live catalog: removed $deletedStages stage(s) and $deletedRooms chat room(s).$errTail'
            : 'Removed $deletedStages stage(s); ${stillLive.length} tagged live remain.$errTail';
      });
    } on IvsStagesApiException catch (e) {
      if (mounted) setState(() => _status = 'Could not list stages to clear: $e');
    } catch (e) {
      if (mounted) setState(() => _status = 'Clear failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showLiveStreamEndedSnackbar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The live stream has ended.'),
          duration: Duration(seconds: 4),
        ),
      );
    });
  }

  Future<void> _refreshLiveList() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final all = await _controlPlane.listStages(
        region: _region.text.trim(),
      );
      final live = all.where(stageIsLiveDemo).toList();
      setState(() {
        _liveStages = live;
        _status = 'Found ${live.length} live stream(s) (tag ${IvsRealtimeStagesApi.tagStatus}=${IvsRealtimeStagesApi.statusLive}).';
      });
    } on IvsStagesApiException catch (e) {
      setState(() => _status = e.toString());
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showGoLiveDialog() async {
    final result = await showDialog<_GoLiveSubmit?>(
      context: context,
      builder: (ctx) => const _GoLiveDialog(),
    );
    if (!mounted || result == null) return;
    await _goLiveCreateStageAndJoin(title: result.title, description: result.description);
  }

  Future<void> _goLiveCreateStageAndJoin({
    required String title,
    required String description,
  }) async {
    if (!ivsNativeStageSupported) {
      setState(() => _status = 'Go live requires Android or iOS for the native IVS stage.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    String? newRoomArn;
    String? newStageArn;
    try {
      final built = buildStageNameAndTags(title: title, description: description);
      final room = await _controlPlane.createChatRoom(
        region: _region.text.trim(),
        name: built.name,
      );
      newRoomArn = room['arn'] as String?;
      if (newRoomArn == null || newRoomArn.isEmpty) {
        throw Exception('CreateRoom returned no arn');
      }
      final stageTags = Map<String, String>.from(built.tags)
        ..[IvsRealtimeStagesApi.tagChatRoomArn] = newRoomArn;
      final stage = await _controlPlane.createStage(
        region: _region.text.trim(),
        name: built.name,
        tags: stageTags,
      );
      newStageArn = stageArn(stage);
      if (newStageArn == null || newStageArn.isEmpty) {
        throw Exception('CreateStage succeeded but no ARN');
      }
      final createdStageArn = newStageArn;
      final createdRoomArn = newRoomArn;
      _stageArn.text = createdStageArn;
      _hostStageArn = createdStageArn;
      _hostChatRoomArn = createdRoomArn;

      await _refreshLiveList();
      setState(() => _status = 'Opening full-screen live…');
      if (!mounted) return;
      final pop = await Navigator.push<String>(
        context,
        MaterialPageRoute<String>(
          builder: (ctx) => FullScreenLivePage(
            region: _region.text.trim(),
            accessKeyId: _accessKey.text.trim(),
            secretAccessKey: _secretKey.text.trim(),
            sessionToken: _session(),
            baseUserId: _userId.text.trim(),
            stageArn: createdStageArn,
            chatRoomArn: createdRoomArn,
            streamTitle: title,
            isHost: true,
            hostStageArnToDelete: createdStageArn,
            hostChatRoomArnToDelete: createdRoomArn,
            controlPlane: _controlPlane,
          ),
        ),
      );
      if (!mounted) return;
      await _refreshLiveList();
      if (pop == 'host_deleted') {
        _hostStageArn = null;
        _hostChatRoomArn = null;
        setState(() => _status = 'Stream ended (stage + chat room deleted).');
      } else if (pop == 'stage_ended') {
        _showLiveStreamEndedSnackbar();
        setState(() => _status = 'Live session ended. List refreshed.');
      } else {
        setState(() => _status = 'Back from live. Stage may still be active if you chose Leave only.');
      }
    } on IvsStagesApiException catch (e) {
      await _rollbackGoLive(newStageArn, newRoomArn);
      setState(() => _status = e.toString());
    } on IvsChatApiException catch (e) {
      await _rollbackGoLive(newStageArn, newRoomArn);
      setState(() => _status = e.toString());
    } catch (e) {
      await _rollbackGoLive(newStageArn, newRoomArn);
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rollbackGoLive(String? stageArn, String? roomArn) async {
    _hostStageArn = null;
    _hostChatRoomArn = null;
    if (stageArn != null) {
      try {
        await _controlPlane.deleteStage(
          region: _region.text.trim(),
          stageArn: stageArn,
        );
      } catch (_) {}
    }
    if (roomArn != null) {
      try {
        await _controlPlane.deleteChatRoom(
          region: _region.text.trim(),
          roomArn: roomArn,
        );
      } catch (_) {}
    }
  }

  Future<void> _joinStreamFromList(Map<String, dynamic> stage) async {
    if (!ivsNativeStageSupported) {
      setState(() => _status = 'Use Android or iOS to join a live stage.');
      return;
    }
    final arn = stageArn(stage);
    if (arn == null || arn.isEmpty) return;

    _stageArn.text = arn;
    final tagChatArn = chatRoomArnFromStage(stage);
    final rejoinAsHost = _hostStageArn != null && arn == _hostStageArn;
    final effectiveChatArn = (tagChatArn != null && tagChatArn.isNotEmpty)
        ? tagChatArn
        : (rejoinAsHost ? _hostChatRoomArn : null);

    if (!mounted) return;
    final pop = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (ctx) => FullScreenLivePage(
          region: _region.text.trim(),
          accessKeyId: _accessKey.text.trim(),
          secretAccessKey: _secretKey.text.trim(),
          sessionToken: _session(),
          baseUserId: _userId.text.trim(),
          stageArn: arn,
          chatRoomArn: effectiveChatArn,
          streamTitle: stageTitle(stage),
          isHost: rejoinAsHost,
          hostStageArnToDelete: rejoinAsHost ? _hostStageArn : null,
          hostChatRoomArnToDelete: rejoinAsHost ? _hostChatRoomArn : null,
          controlPlane: _controlPlane,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshLiveList();
    if (pop == 'host_deleted') {
      _hostStageArn = null;
      _hostChatRoomArn = null;
      setState(() => _status = 'Stream ended (stage + chat room deleted).');
      return;
    }
    if (pop == 'stage_ended') {
      _showLiveStreamEndedSnackbar();
    }
    setState(() {
      if (pop == 'stage_ended') {
        _status = 'Live session ended. List refreshed.';
      } else if (rejoinAsHost) {
        _status = 'Disconnected from your live stage. It is still running on AWS until you tap '
            'End stream in the app bar, or open this stream again from the list to resume as host.';
      } else {
        _status = effectiveChatArn == null || effectiveChatArn.isEmpty
            ? 'Left viewer. (No ${IvsRealtimeStagesApi.tagChatRoomArn} tag on this stage — chat only when linked from Go live.)'
            : 'Left viewer.';
      }
    });
  }

  Future<void> _endHostStream() async {
    final arn = _hostStageArn;
    if (arn == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _stage.leave();
      final chatArn = _hostChatRoomArn;
      _hostChatRoomArn = null;
      if (chatArn != null) {
        await _controlPlane.deleteChatRoom(
          region: _region.text.trim(),
          roomArn: chatArn,
        );
      }
      await _controlPlane.deleteStage(
        region: _region.text.trim(),
        stageArn: arn,
      );
      _hostStageArn = null;
      setState(() => _status = 'Stage + chat room deleted; disconnected.');
      await _refreshLiveList();
    } on IvsStagesApiException catch (e) {
      setState(() => _status = e.toString());
    } on IvsChatApiException catch (e) {
      setState(() => _status = e.toString());
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mintToken() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final caps = _publish
          ? const ['PUBLISH', 'SUBSCRIBE']
          : const ['SUBSCRIBE'];
      final token = await _controlPlane.mintParticipantToken(
        region: _region.text.trim(),
        stageArn: _stageArn.text.trim(),
        userId: _userId.text.trim().isEmpty ? null : _userId.text.trim(),
        capabilities: caps,
      );
      setState(() {
        _lastToken = token;
        _status = 'Token OK (${token.length} chars). Tap Join / leave stage.';
      });
    } on IvsTokenException catch (e) {
      setState(() => _status = e.message);
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleStage() async {
    if (!ivsNativeStageSupported) {
      setState(() => _status = 'Use an Android or iOS device for the native stage.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final token = _lastToken;
      if (token == null || token.isEmpty) {
        setState(() => _status = 'Mint a token first.');
        return;
      }
      await _stage.join(token: token, publish: _publish);
      setState(() => _status = 'Native stage toggled (join/leave).');
    } on UnsupportedError catch (e) {
      setState(() => _status = '$e');
    } on IvsStageException catch (e) {
      setState(() => _status = e.message);
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (!ivsNativeStageSupported) return;
    await _stage.leave();
    setState(() => _status = 'Left stage (native).');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IVS Real-Time (demo)'),
        actions: [
          IconButton(
            tooltip: 'Refresh live list',
            onPressed: _busy ? null : _refreshLiveList,
            icon: const Icon(Icons.refresh),
          ),
          if (_hostStageArn != null)
            IconButton(
              tooltip: 'End stream (DeleteStage)',
              onPressed: _busy ? null : _endHostStream,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _showGoLiveDialog,
        icon: const Icon(Icons.videocam),
        label: const Text('Go live'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const Text(
              'Demo: IAM keys in the app. Video: ivs:ListStages, CreateStage, TagResource, DeleteStage, '
              'CreateParticipantToken. Chat: ivschat:CreateRoom, DeleteRoom, CreateChatToken. '
              'Stage tag ${IvsRealtimeStagesApi.tagChatRoomArn} links to the IVS Chat room.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              initiallyExpanded: false,
              title: const Text('AWS credentials & region'),
              children: [
                TextField(
                  controller: _region,
                  decoration: const InputDecoration(labelText: 'AWS region'),
                  textCapitalization: TextCapitalization.none,
                ),
                TextField(
                  controller: _accessKey,
                  decoration: const InputDecoration(labelText: 'Access key ID'),
                ),
                TextField(
                  controller: _secretKey,
                  decoration: const InputDecoration(labelText: 'Secret access key'),
                  obscureText: true,
                ),
                TextField(
                  controller: _sessionToken,
                  decoration: const InputDecoration(labelText: 'Session token (optional)'),
                ),
                TextField(
                  controller: _userId,
                  decoration: const InputDecoration(labelText: 'userId (optional)'),
                ),
                TextField(
                  controller: _stageArn,
                  decoration: const InputDecoration(
                    labelText: 'Stage ARN (manual / updated when you pick a list item)',
                  ),
                ),
                SwitchListTile(
                  title: const Text('Publish camera + mic (manual join)'),
                  value: _publish,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          if (!v) {
                            setState(() => _publish = false);
                            if (ivsNativeStageSupported) {
                              await _stage.setPublish(false);
                            }
                            return;
                          }
                          try {
                            if (ivsNativeStageSupported) {
                              await _stage.setPublish(true);
                            }
                            if (!mounted) return;
                            setState(() => _publish = true);
                          } on IvsStageException catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message)),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        },
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _mintToken,
                      child: const Text('Mint token (manual ARN)'),
                    ),
                    FilledButton.tonal(
                      onPressed: _busy ? null : _toggleStage,
                      child: const Text('Join / leave'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _leave,
                      child: const Text('Leave'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Live streams (${_liveStages.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            if (_liveStages.isEmpty)
              Text(
                'Tap refresh. After someone uses Go live, their stream appears here for others.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              )
            else
              ..._liveStages.map((s) {
                final arn = stageArn(s) ?? '';
                final shortArn = arn.length > 48 ? '${arn.substring(0, 48)}…' : arn;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.live_tv),
                    title: Text(stageTitle(s)),
                    subtitle: Text(
                      '${stageDescription(s)}\n$shortArn',
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _joinStreamFromList(s),
                  ),
                );
              }),
            if (_status != null) ...[
              const SizedBox(height: 12),
              SelectableText(_status!, style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Text(
              'Video + chat open on a full-screen page when you Go live or tap a stream.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result of the Go live dialog; `null` from [showDialog] means cancelled.
class _GoLiveSubmit {
  const _GoLiveSubmit({required this.title, required this.description});
  final String title;
  final String description;
}

class _GoLiveDialog extends StatefulWidget {
  const _GoLiveDialog();

  @override
  State<_GoLiveDialog> createState() => _GoLiveDialogState();
}

class _GoLiveDialogState extends State<_GoLiveDialog> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _desc = TextEditingController();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _title.text.trim();
    if (t.isEmpty) {
      setState(() => _titleError = 'Required');
      return;
    }
    Navigator.of(context).pop(
      _GoLiveSubmit(title: t, description: _desc.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go live'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Creates a new IVS stage with title/description in resource tags, '
              'then joins as publisher.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'My stream',
                errorText: _titleError,
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: 'Description',
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create & join'),
        ),
      ],
    );
  }
}
