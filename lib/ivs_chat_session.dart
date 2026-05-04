import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// One WebSocket session to **Amazon IVS Chat** ([User Guide](https://docs.aws.amazon.com/ivs/latest/ChatUserGuide/getting-started-chat-send-receive.html)).
class IvsChatLine {
  IvsChatLine({
    required this.id,
    required this.senderLabel,
    required this.content,
    this.sendTime,
  });

  final String id;
  final String senderLabel;
  final String content;
  final String? sendTime;
}

/// IVS Chat over WebSocket with **automatic reconnect** while the session is active.
///
/// [resolveChatToken] must return a **new** token from `CreateChatToken` whenever called;
/// tokens are short-lived and each connection (including reconnects) should use a fresh one.
class IvsChatSession {
  IvsChatSession();

  WebSocket? _ws;
  StreamSubscription<dynamic>? _sub;
  final _lines = StreamController<IvsChatLine>.broadcast();

  Stream<IvsChatLine> get lines => _lines.stream;

  String? _region;
  Future<String> Function()? _resolveChatToken;
  bool _disposed = false;
  bool _started = false;

  Timer? _reconnectTimer;
  int _backoffMs = 1000;
  Future<void>? _openInFlight;

  /// Whether the socket is currently usable for [sendMessage].
  bool get isSocketOpen => _ws != null && _ws!.readyState == WebSocket.open;

  /// Starts (or restarts) the chat connection. Safe to call again after failures.
  ///
  /// [resolveChatToken] is invoked for the initial link and after every drop so
  /// each WebSocket handshake uses a valid IVS token.
  Future<void> connect({
    required String region,
    required Future<String> Function() resolveChatToken,
  }) async {
    _disposed = false;
    _started = true;
    _region = region;
    _resolveChatToken = resolveChatToken;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _backoffMs = 1000;
    await _openSocket(reason: 'initial');
  }

  Future<void> _openSocket({required String reason}) async {
    if (_disposed || !_started || _region == null || _resolveChatToken == null) {
      return;
    }
    if (_openInFlight != null) {
      await _openInFlight;
      return;
    }
    _openInFlight = _openSocketImpl(reason: reason);
    try {
      await _openInFlight;
    } finally {
      _openInFlight = null;
    }
  }

  Future<void> _openSocketImpl({required String reason}) async {
    try {
      await _tearDownSocketOnly();

      final token = await _resolveChatToken!();
      if (_disposed || !_started) return;

      final uri = Uri.parse('wss://edge.ivschat.${_region!}.amazonaws.com');
      final ws = await WebSocket.connect(
        uri.toString(),
        protocols: [token],
      );
      if (_disposed || !_started) {
        await ws.close();
        return;
      }

      _ws = ws;
      _backoffMs = 1000;

      _sub = ws.listen(
        (dynamic data) {
          if (data is! String) return;
          try {
            final m = jsonDecode(data) as Map<String, dynamic>;
            final content = m['Content'] as String?;
            if (content == null) return;
            final sender = m['Sender'] as Map<String, dynamic>?;
            Map<String, dynamic>? attrs;
            final rawAttrs = sender?['Attributes'];
            if (rawAttrs is Map<String, dynamic>) {
              attrs = rawAttrs;
            } else if (rawAttrs is Map) {
              attrs = Map<String, dynamic>.from(rawAttrs);
            }
            final who = attrs?['displayName'] as String? ??
                sender?['UserId'] as String? ??
                '?';
            final id = m['Id'] as String? ?? '${DateTime.now().millisecondsSinceEpoch}';
            final time = m['SendTime'] as String?;
            if (!_lines.isClosed) {
              _lines.add(IvsChatLine(
                id: id,
                senderLabel: who,
                content: content,
                sendTime: time,
              ));
            }
          } catch (_) {
            // Ignore non-chat frames.
          }
        },
        onError: (Object error, StackTrace stackTrace) =>
            _scheduleReconnect(trigger: 'onError'),
        onDone: () => _scheduleReconnect(trigger: 'onDone'),
        cancelOnError: false,
      );
    } catch (_) {
      if (!_disposed && _started) {
        _scheduleReconnect(trigger: 'openFailed');
      }
    }
  }

  void _scheduleReconnect({required String trigger}) {
    if (_disposed || !_started) return;
    _reconnectTimer?.cancel();
    final delay = Duration(milliseconds: _backoffMs);
    _backoffMs = math.min(_backoffMs * 2, 30000);
    _reconnectTimer = Timer(delay, () {
      if (_disposed || !_started) return;
      unawaited(_openSocket(reason: 'reconnect:$trigger'));
    });
  }

  Future<void> _tearDownSocketOnly() async {
    await _sub?.cancel();
    _sub = null;
    final w = _ws;
    _ws = null;
    if (w != null) {
      try {
        await w.close();
      } catch (_) {}
    }
  }

  /// Sends a chat message; waits for a live socket and retries briefly if needed.
  Future<bool> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (_disposed || !_started) return false;

    const maxAttempts = 4;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_disposed || !_started) return false;
      if (!isSocketOpen) {
        try {
          await _openSocket(reason: 'send:ensureOpen');
        } catch (_) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }
      }
      if (!isSocketOpen) {
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
        continue;
      }
      final payload = <String, Object?>{
        'Action': 'SEND_MESSAGE',
        'RequestId': DateTime.now().millisecondsSinceEpoch.toString(),
        'Content': trimmed,
      };
      try {
        _ws!.add(jsonEncode(payload));
        return true;
      } catch (_) {
        _scheduleReconnect(trigger: 'sendFailed');
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
    return false;
  }

  Future<void> close() async {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _tearDownSocketOnly();
  }

  Future<void> dispose() async {
    _disposed = true;
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _tearDownSocketOnly();
    if (!_lines.isClosed) {
      await _lines.close();
    }
  }
}
