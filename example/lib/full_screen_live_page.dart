import 'dart:async';
import 'dart:io';

import 'package:aws_ivs_realtime/aws_ivs_realtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen **video + chat** (YouTube-style: video on top, messages + composer below).
///
/// Pushed from the lobby after **Go live** (host) or when opening a stream from the list (viewer).
class FullScreenLivePage extends StatefulWidget {
  const FullScreenLivePage({
    super.key,
    required this.region,
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
    required this.baseUserId,
    required this.stageArn,
    this.chatRoomArn,
    required this.streamTitle,
    required this.isHost,
    this.hostStageArnToDelete,
    this.hostChatRoomArnToDelete,
    this.controlPlane,
  });

  final String region;
  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;
  final String baseUserId;
  final String stageArn;
  final String? chatRoomArn;
  final String streamTitle;
  final bool isHost;

  /// When [isHost], ARNs to delete on **End stream for everyone**.
  final String? hostStageArnToDelete;
  final String? hostChatRoomArnToDelete;

  /// Optional: use your backend by implementing [IvsLiveControlPlane]. If null, SigV4 is used
  /// with [accessKeyId] / [secretAccessKey] / [sessionToken] from this page.
  final IvsLiveControlPlane? controlPlane;

  @override
  State<FullScreenLivePage> createState() => _FullScreenLivePageState();
}

class _FullScreenLivePageState extends State<FullScreenLivePage> {
  final _stage = IvsRealtimePlatform();
  late final IvsLiveControlPlane _ivs;

  final _msgInput = TextEditingController();
  final _chatScroll = ScrollController();

  IvsChatSession? _chat;
  StreamSubscription<IvsChatLine>? _chatSub;
  StreamSubscription<Map<String, dynamic>>? _stageConnSub;
  final List<IvsChatLine> _lines = [];

  bool _publish = true;
  bool _micMuted = false;
  bool _camMuted = false;
  bool _loading = true;
  String? _error;

  /// Avoid calling [IvsRealtimePlatform.leave] twice when both [_popAfterCleanup] and [dispose] run.
  bool _nativeStageLeft = false;

  @override
  void initState() {
    super.initState();
    _ivs = widget.controlPlane ??
        IvsAwsSigV4ControlPlane(
          resolveCredentials: () => (
            accessKeyId: widget.accessKeyId,
            secretAccessKey: widget.secretAccessKey,
            sessionToken: widget.sessionToken,
          ),
        );
    _publish = widget.isHost;
    _stageConnSub = _stage.stageConnectionEvents.listen((Map<String, dynamic> m) {
      if (!mounted || _nativeStageLeft) return;
      if (m['event'] == 'disconnected') {
        unawaited(_handleRemoteStageDisconnected());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    _stageConnSub?.cancel();
    _stageConnSub = null;
    _msgInput.dispose();
    _chatScroll.dispose();
    if (!_nativeStageLeft) {
      unawaited(_teardown(deleteHostResources: false));
    }
    super.dispose();
  }

  String _chatUserId() {
    final b = widget.baseUserId.trim();
    final suffix = widget.isHost ? '-host' : '-viewer';
    final core = b.isEmpty ? 'user-${DateTime.now().millisecondsSinceEpoch}' : b;
    final s = '$core$suffix';
    if (s.length <= 128) return s;
    return s.substring(0, 128);
  }

  Future<void> _handleRemoteStageDisconnected() async {
    if (!mounted || _nativeStageLeft) return;
    await _teardown(deleteHostResources: false);
    if (!mounted) return;
    Navigator.of(context).pop<String>('stage_ended');
  }

  Future<void> _bootstrap() async {
    if (!ivsNativeStageSupported) {
      setState(() {
        _loading = false;
        _error = 'Native IVS stage is supported on Android and iOS only.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final caps = widget.isHost
          ? const ['PUBLISH', 'SUBSCRIBE']
          : const ['SUBSCRIBE'];
      final token = await _ivs.mintParticipantToken(
        region: widget.region,
        stageArn: widget.stageArn,
        userId: _chatUserId(),
        capabilities: caps,
      );
      await _stage.setPublish(widget.isHost);
      // Let the PlatformView mount and lay out before join — otherwise the RecyclerView
      // is not attached and remote previews can stay black until media restarts.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 96));
      if (!mounted) return;
      await _stage.join(token: token, publish: widget.isHost);
      await _stage.refreshStageBindings();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _stage.refreshStageBindings();
      final room = widget.chatRoomArn;
      if (room != null && room.isNotEmpty) {
        await _connectChat(room);
      }
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        await WidgetsBinding.instance.endOfFrame;
        await _stage.refreshStageBindings();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _connectChat(String roomArn) async {
    await _disconnectChatOnly();
    final session = IvsChatSession();
    Future<String> mintToken() async {
      final json = await _ivs.mintChatToken(
        region: widget.region,
        roomArn: roomArn,
        userId: _chatUserId(),
        capabilities: const ['SEND_MESSAGE'],
        attributes: {
          'displayName': _displayNameForChat(),
        },
      );
      final t = json['token'] as String?;
      if (t == null || t.isEmpty) {
        throw StateError('CreateChatToken returned no token');
      }
      return t;
    }

    await session.connect(
      region: widget.region,
      resolveChatToken: mintToken,
    );
    if (!mounted) {
      await session.dispose();
      return;
    }
    _chat = session;
    _chatSub = session.lines.listen((line) {
      if (!mounted) return;
      setState(() {
        _lines.add(line);
        if (_lines.length > 300) {
          _lines.removeAt(0);
        }
      });
      _scrollChatToBottom();
    });
  }

  String _displayNameForChat() {
    final n = widget.baseUserId.trim();
    if (n.isEmpty) return widget.isHost ? 'Host' : 'Viewer';
    return n.length > 40 ? n.substring(0, 40) : n;
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _disconnectChatOnly() async {
    await _chatSub?.cancel();
    _chatSub = null;
    final c = _chat;
    _chat = null;
    if (c != null) {
      await c.dispose();
    }
  }

  /// Leaves native stage + chat. Optionally deletes host AWS resources.
  Future<void> _teardown({required bool deleteHostResources}) async {
    await _disconnectChatOnly();
    if (!_nativeStageLeft) {
      _nativeStageLeft = true;
      try {
        await _stage.leave();
      } catch (_) {}
    }
    if (deleteHostResources &&
        widget.isHost &&
        widget.hostChatRoomArnToDelete != null &&
        widget.hostStageArnToDelete != null) {
      try {
        await _ivs.deleteChatRoom(
          region: widget.region,
          roomArn: widget.hostChatRoomArnToDelete!,
        );
      } catch (_) {}
      try {
        await _ivs.deleteStage(
          region: widget.region,
          stageArn: widget.hostStageArnToDelete!,
        );
      } catch (_) {}
    }
  }

  Future<void> _popAfterCleanup({required bool deleteHostResources}) async {
    await _teardown(deleteHostResources: deleteHostResources);
    if (!mounted) return;
    Navigator.of(context).pop<String>(
      deleteHostResources ? 'host_deleted' : 'left',
    );
  }

  Future<void> _onPublishChanged(bool v) async {
    if (!v) {
      setState(() => _publish = false);
      await _stage.setPublish(false);
      setState(() {
        _micMuted = false;
        _camMuted = false;
      });
      await _stage.setLocalStreamMuted(micMuted: false, cameraMuted: false);
      return;
    }
    try {
      await _stage.setPublish(true);
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
  }

  Future<void> _toggleMicMuted() async {
    if (!_publish || _loading) return;
    final next = !_micMuted;
    setState(() => _micMuted = next);
    await _stage.setLocalStreamMuted(micMuted: next, cameraMuted: _camMuted);
  }

  Future<void> _toggleCamMuted() async {
    if (!_publish || _loading) return;
    final next = !_camMuted;
    setState(() => _camMuted = next);
    await _stage.setLocalStreamMuted(micMuted: _micMuted, cameraMuted: next);
  }

  Future<void> _sendMessage() async {
    final text = _msgInput.text;
    final chat = _chat;
    if (chat == null) return;
    final ok = await chat.sendMessage(text);
    if (!mounted) return;
    if (ok) {
      _msgInput.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message could not be sent. Reconnecting chat… try again in a moment.'),
        ),
      );
    }
  }

  Future<void> _confirmHostBack() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave live?'),
        content: const Text(
          'End stream for everyone deletes the IVS stage and chat room on AWS (stops billing).\n\n'
          'Leave only disconnects this phone; the stage keeps running until you use End stream '
          'from the lobby, or open this stream from the list again—you rejoin as host with full controls.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'leave'),
            child: const Text('Leave only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'end'),
            child: const Text('End for everyone'),
          ),
        ],
      ),
    );
    if (action == 'end') {
      await _popAfterCleanup(deleteHostResources: true);
    } else if (action == 'leave') {
      await _popAfterCleanup(deleteHostResources: false);
    }
  }

  Widget _ivsStagePlatformView() {
    if (Platform.isAndroid) {
      return AndroidView(
        viewType: AwsIvsRealtimePlatformView.viewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    if (Platform.isIOS) {
      return UiKitView(
        viewType: AwsIvsRealtimePlatformView.viewType,
        layoutDirection: TextDirection.ltr,
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    return const SizedBox.expand();
  }

  static const _sheetRadius = 20.0;
  static const _videoRadius = 20.0;

  bool _isOwnChatLine(IvsChatLine line) =>
      line.senderLabel.trim() == _displayNameForChat().trim();

  String _chatTimeShort(String? sendTime) {
    if (sendTime == null || sendTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(sendTime).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  Widget _buildHostControlOverlay() {
    if (!widget.isHost) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: _loading,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.92),
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
          child: SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Broadcast',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      FittedBox(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Publish',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            Transform.scale(
                              scale: 0.92,
                              child: Switch.adaptive(
                                value: _publish,
                                onChanged: _loading ? null : _onPublishChanged,
                                activeTrackColor: Colors.redAccent.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!_loading)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          _roundStudioIcon(
                            tooltip: _micMuted ? 'Unmute microphone' : 'Mute microphone',
                            onPressed: _publish ? _toggleMicMuted : null,
                            icon: _micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                            active: _publish && !_micMuted,
                          ),
                          const SizedBox(width: 10),
                          _roundStudioIcon(
                            tooltip: _camMuted ? 'Turn camera on' : 'Turn camera off',
                            onPressed: _publish ? _toggleCamMuted : null,
                            icon: _camMuted ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                            active: _publish && !_camMuted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _publish
                                  ? 'Mute only changes what viewers receive.'
                                  : 'Publish off — viewers see you in chat only.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                                height: 1.25,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundStudioIcon({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    required bool active,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: onPressed == null ? 0.06 : 0.12),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: active ? Colors.white : Colors.white38, size: 22),
      ),
    );
  }

  Widget _buildChatMessageBubble(BuildContext context, IvsChatLine m) {
    final own = _isOwnChatLine(m);
    final time = _chatTimeShort(m.sendTime);
    final maxW = MediaQuery.sizeOf(context).width * 0.88;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: own ? const Color(0xFF1A237E).withValues(alpha: 0.92) : const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(own ? 16 : 5),
                bottomRight: Radius.circular(own ? 5 : 16),
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.senderLabel,
                          style: TextStyle(
                            color: own ? const Color(0xFF9FA8DA) : const Color(0xFFB0BEC5),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    m.content,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatComposer() {
    final enabled = _chat != null;
    return Material(
      elevation: 12,
      color: const Color(0xFF181818),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _msgInput,
                minLines: 1,
                maxLines: 4,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                cursorColor: Colors.redAccent,
                decoration: InputDecoration(
                  hintText: 'Chat publicly…',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.38)),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2C),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => unawaited(_sendMessage()),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: enabled ? () => unawaited(_sendMessage()) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(14),
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.send_rounded, size: 22),
            ),
          ],
        ),
      ),
    );
  }

  /// Keeps the native platform view in the tree while joining so the native grid exists
  /// before IVS fires remote stream callbacks (avoids a permanent black preview).
  Widget _buildScaffoldBody(BuildContext context) {
    if (!ivsNativeStageSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Native IVS stage is supported on Android and iOS only.',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Avoid wrapping the video in SafeArea — on iOS that steals vertical space from the stage
    // before flex layout. Only the chat column applies bottom (and optional side) insets.
    final videoFlex = Platform.isIOS ? 8 : 7;
    final chatFlex = Platform.isIOS ? 2 : 3;

    return Column(
      children: [
        Expanded(
          flex: videoFlex,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(_videoRadius),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: _ivsStagePlatformView()),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.35),
                              Colors.transparent,
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.15),
                            ],
                            stops: const [0.0, 0.12, 0.65, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_loading)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.65),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.redAccent,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Connecting to live…',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  _buildHostControlOverlay(),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: chatFlex,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 18,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              color: Colors.white.withValues(alpha: 0.75), size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Live chat',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const Spacer(),
                          if (_lines.isNotEmpty)
                            Text(
                              '${_lines.length}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: widget.chatRoomArn == null || widget.chatRoomArn!.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.forum_outlined,
                                      size: 48,
                                      color: Colors.white.withValues(alpha: 0.22),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No chat room is linked to this stage.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.45),
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _chatScroll,
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                              itemCount: _lines.length,
                              itemBuilder: (ctx, i) =>
                                  _buildChatMessageBubble(context, _lines[i]),
                            ),
                    ),
                    if (widget.chatRoomArn != null && widget.chatRoomArn!.isNotEmpty)
                      _buildChatComposer(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (widget.isHost) {
          await _confirmHostBack();
        } else {
          await _popAfterCleanup(deleteHostResources: false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            widget.streamTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          ),
          centerTitle: false,
          backgroundColor: const Color(0xE6000000),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              if (widget.isHost) {
                await _confirmHostBack();
              } else {
                await _popAfterCleanup(deleteHostResources: false);
              }
            },
          ),
          actions: [
            if (widget.isHost)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: _loading
                      ? null
                      : () => _popAfterCleanup(deleteHostResources: true),
                  icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 20),
                  label: const Text('End', style: TextStyle(color: Colors.redAccent)),
                ),
              ),
          ],
        ),
        body: _buildScaffoldBody(context),
      ),
    );
  }
}
