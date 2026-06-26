import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

// ── WebSocket manager ─────────────────────────────────────────────────────────
// Owns a single chat WS connection. Handles reconnect with exponential backoff.
// Calls [onFallbackNeeded] after 3 failed connection attempts without ever
// succeeding — meaning the server doesn't speak WS on that endpoint.
class _ChatWsManager {
  final String wsUrl;
  final void Function(Map<String, dynamic>) onMessage;
  final VoidCallback onFallbackNeeded;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  bool _disposed = false;
  bool _isConnected = false;
  bool _everConnected = false;
  int _failCount = 0;
  // Guard so that both ready.catchError and stream.onDone don't double-fire.
  bool _handlingDisconnect = false;

  bool get isConnected => _isConnected;

  _ChatWsManager({
    required this.wsUrl,
    required this.onMessage,
    required this.onFallbackNeeded,
  });

  void connect() {
    if (_disposed) return;
    _handlingDisconnect = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _sub = _channel!.stream.listen(
        (raw) {
          if (_disposed) return;
          // First data proves the connection is alive.
          if (!_isConnected) {
            _isConnected = true;
            _everConnected = true;
            _failCount = 0;
          }
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            onMessage(data);
          } catch (_) {}
        },
        onError: (_) => _onDisconnect(),
        onDone: _onDisconnect,
        cancelOnError: false,
      );

      // ready completes after the HTTP→WS upgrade handshake.
      _channel!.ready.then((_) {
        if (_disposed) return;
        _isConnected = true;
        _everConnected = true;
        _failCount = 0;
      }).catchError((Object _) { _onDisconnect(); });

    } catch (_) {
      _onDisconnect();
    }
  }

  void _onDisconnect() {
    if (_disposed || _handlingDisconnect) return;
    _handlingDisconnect = true;
    _isConnected = false;
    _failCount++;

    // Never connected after 3 tries → server doesn't support WS → use polling.
    if (!_everConnected && _failCount >= 3) {
      onFallbackNeeded();
      return;
    }

    // Exponential backoff: 3 s, 6 s, 12 s, 24 s, 30 s (cap).
    final delaySec = min(3 * (1 << (_failCount - 1).clamp(0, 4)), 30);
    _reconnectTimer = Timer(Duration(seconds: delaySec), connect);
  }

  void send(Map<String, dynamic> data) {
    if (!_isConnected) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
class ChatsProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<dynamic> chats = [];
  Map<int, List<dynamic>> messages = {};
  Map<int, List<dynamic>> chatUsers = {};
  int? activeChatId;
  bool loading = true;
  List<dynamic> searchResults = [];
  final Map<int, int> lastSeenMsgId = {};
  String? errorMessage;

  // WS state
  _ChatWsManager? _wsManager;
  Timer? _fallbackPoller;

  // Typing: userId → last-seen timestamp. Cleared after 3 s of silence.
  final Map<int, DateTime> _typingTimestamps = {};
  Timer? _typingCleaner;

  bool get someoneIsTyping => _typingTimestamps.isNotEmpty;

  ChatsProvider(this._api, this._auth);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disconnectWs();
    _stopFallbackPoller();
    _typingCleaner?.cancel();
    super.dispose();
  }

  void clearError() {
    errorMessage = null;
  }

  // ── Seen-message persistence ─────────────────────────────────────────────────

  Future<void> loadSeenMsgIds() async {
    try {
      final uid = _auth.userId ?? 0;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_seen_$uid');
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        lastSeenMsgId.addAll(map.map((k, v) => MapEntry(int.parse(k), v as int)));
      }
    } catch (e) {
      errorMessage = 'Ошибка загрузки истории прочитанных: $e';
      notifyListeners();
    }
  }

  Future<void> saveSeenMsgIds() async {
    try {
      final uid = _auth.userId ?? 0;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'chat_seen_$uid',
        jsonEncode(lastSeenMsgId.map((k, v) => MapEntry('$k', v))),
      );
    } catch (e) {
      errorMessage = 'Ошибка сохранения: $e';
      notifyListeners();
    }
  }

  // ── Data loading ─────────────────────────────────────────────────────────────

  Future<void> loadChats() async {
    loading = true;
    notifyListeners();
    try {
      chats = await _api.getChats();
      // Load users + messages for all chats in parallel instead of sequentially.
      await Future.wait(chats.map((c) async {
        final id = c['id'] as int;
        await Future.wait([
          () async {
            try {
              chatUsers[id] = await _api.getChatUsers(id);
            } catch (e) {
              errorMessage = 'Ошибка загрузки участников чата: $e';
            }
          }(),
          () async {
            try {
              messages[id] = await _api.getMessages(id);
            } catch (e) {
              errorMessage = 'Ошибка загрузки сообщений: $e';
            }
          }(),
        ]);
      }));
    } catch (e) {
      errorMessage = 'Не удалось загрузить чаты: $e';
    }
    loading = false;
    notifyListeners();
  }

  // Used by the screen's background timer for unread-badge updates.
  // Skips the active chat when WS is handling it live.
  Future<void> pollMessages() async {
    try {
      for (final c in chats) {
        final id = c['id'] as int;
        // Skip the chat that WS is already streaming.
        if (id == activeChatId && (_wsManager?.isConnected ?? false)) continue;
        try {
          messages[id] = await _api.getMessages(id);
          notifyListeners();
        } catch (e) {
          errorMessage = 'Ошибка опроса сообщений: $e';
          notifyListeners();
        }
      }
    } catch (e) {
      errorMessage = 'Ошибка обновления чатов: $e';
      notifyListeners();
    }
  }

  // ── Messaging ─────────────────────────────────────────────────────────────────

  Future<void> sendMessage(String content) async {
    if (activeChatId == null) return;
    final chatId = activeChatId!;
    try {
      final response = await _api.sendMessage(chatId, content);
      // Optimistic local insert — the WS echo deduplicates by id.
      final msgId = (response['id'] as num?)?.toInt();
      if (msgId != null) {
        final msgs = List<dynamic>.from(messages[chatId] ?? []);
        if (!msgs.any((m) => (m['id'] as num?)?.toInt() == msgId)) {
          msgs.add(response);
          messages[chatId] = msgs;
          lastSeenMsgId[chatId] = msgId;
          saveSeenMsgIds();
          notifyListeners();
        }
      }
      // Fallback poll only when WS is not live.
      if (!(_wsManager?.isConnected ?? false)) {
        await pollMessages();
      }
    } catch (e) {
      errorMessage = 'Ошибка отправки сообщения: $e';
      notifyListeners();
    }
  }

  Future<String?> uploadAndSend(int chatId, String filePath, String fileName) async {
    try {
      final result = await _api.uploadFile(filePath, fileName);
      var url = result['url'] ?? result['file_url'] ?? result['path'] ?? '';
      if (url.isNotEmpty && !url.startsWith('http')) {
        url = '${_api.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
      }
      if (url.isNotEmpty) {
        await _api.sendMessage(chatId, url);
        if (!(_wsManager?.isConnected ?? false)) await pollMessages();
        return null;
      }
      return 'Не удалось получить URL файла';
    } catch (e) {
      return 'Ошибка загрузки: $e';
    }
  }

  // ── User search / DM ─────────────────────────────────────────────────────────

  Future<void> searchUsers(String q) async {
    if (q.trim().isEmpty) {
      searchResults = [];
      notifyListeners();
      return;
    }
    try {
      final all = await _api.getUsers();
      searchResults = all.where((u) =>
        u['id'] != _auth.userId &&
        ((u['email'] ?? '').toLowerCase().contains(q.toLowerCase()) ||
         (u['full_name'] ?? '').toLowerCase().contains(q.toLowerCase())),
      ).toList();
      notifyListeners();
    } catch (e) {
      errorMessage = 'Ошибка поиска пользователей: $e';
      notifyListeners();
    }
  }

  Future<bool> openDM(dynamic user) async {
    for (final c in chats) {
      final users = chatUsers[c['id']] ?? [];
      if (users.length == 2 &&
          users.any((u) => u['id'] == user['id']) &&
          users.any((u) => u['id'] == _auth.userId)) {
        searchResults = [];
        activeChatId = c['id'];
        _connectWs(c['id'] as int);
        notifyListeners();
        return true;
      }
    }
    try {
      final chat = await _api.createChat('Чат с ${user['email']}');
      await _api.addChatUser(chat['id'], user['id']);
      searchResults = [];
      await loadChats();
      activeChatId = chat['id'];
      _connectWs(chat['id'] as int);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Не удалось создать диалог: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteChat(int chatId) async {
    try {
      await _api.deleteChat(chatId);
      chats.removeWhere((c) => c['id'] == chatId);
      messages.remove(chatId);
      chatUsers.remove(chatId);
      lastSeenMsgId.remove(chatId);
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Не удалось удалить чат: $e';
      notifyListeners();
      return false;
    }
  }

  // ── Active-chat management ────────────────────────────────────────────────────

  void setActiveChatId(int? id) {
    if (activeChatId == id) return;
    if (id == null) {
      _disconnectWs();
      _stopFallbackPoller();
    }
    activeChatId = id;
    if (id != null) _connectWs(id);
    notifyListeners();
  }

  void markSeen(int chatId) {
    final msgs = messages[chatId] ?? [];
    if (msgs.isNotEmpty) {
      lastSeenMsgId[chatId] = msgs.last['id'] as int;
    }
    notifyListeners();
    saveSeenMsgIds();
  }

  // ── WebSocket internals ───────────────────────────────────────────────────────

  void _connectWs(int chatId) {
    _disconnectWs();
    _stopFallbackPoller();
    _typingTimestamps.clear();

    final token = _api.token;
    if (token == null) return;

    _wsManager = _ChatWsManager(
      wsUrl: '${_api.wsBaseUrl}/ws/chat/$chatId?token=$token',
      onMessage: (data) => _handleWsMessage(chatId, data),
      onFallbackNeeded: () => _startFallbackPoller(chatId),
    );
    _wsManager!.connect();
  }

  void _disconnectWs() {
    _wsManager?.dispose();
    _wsManager = null;
  }

  void _handleWsMessage(int chatId, Map<String, dynamic> data) {
    final type = data['type'] as String?;

    if (type == 'message') {
      final msgId = (data['id'] as num?)?.toInt();
      if (msgId == null) return;
      final msgs = List<dynamic>.from(messages[chatId] ?? []);
      if (!msgs.any((m) => (m['id'] as num?)?.toInt() == msgId)) {
        msgs.add(data);
        messages[chatId] = msgs;
        if (activeChatId == chatId) {
          lastSeenMsgId[chatId] = msgId;
          saveSeenMsgIds();
        }
        notifyListeners();
      }
    } else if (type == 'typing') {
      final userId = (data['user_id'] as num?)?.toInt();
      if (userId != null && userId != _auth.userId) {
        _typingTimestamps[userId] = DateTime.now();
        _resetTypingCleaner();
        notifyListeners();
      }
    }
  }

  void _resetTypingCleaner() {
    _typingCleaner?.cancel();
    _typingCleaner = Timer(const Duration(seconds: 4), () {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 3));
      _typingTimestamps.removeWhere((_, ts) => ts.isBefore(cutoff));
      notifyListeners();
    });
  }

  // ── Typing ────────────────────────────────────────────────────────────────────

  void sendTyping() {
    _wsManager?.send({'type': 'typing'});
  }

  // ── Fallback polling ──────────────────────────────────────────────────────────

  void _startFallbackPoller(int chatId) {
    _fallbackPoller?.cancel();
    _fallbackPoller = Timer.periodic(const Duration(seconds: 10), (_) {
      if (activeChatId == chatId) pollMessages();
    });
  }

  void _stopFallbackPoller() {
    _fallbackPoller?.cancel();
    _fallbackPoller = null;
  }

  // ── Computed getters ──────────────────────────────────────────────────────────

  List<dynamic> get sortedChats {
    final sorted = List<dynamic>.from(chats);
    sorted.sort((a, b) {
      final aMsgs = messages[a['id'] as int] ?? [];
      final bMsgs = messages[b['id'] as int] ?? [];
      if (aMsgs.isEmpty && bMsgs.isEmpty) return 0;
      if (aMsgs.isEmpty) return 1;
      if (bMsgs.isEmpty) return -1;
      try {
        final aTime = DateTime.parse(aMsgs.last['created_at']);
        final bTime = DateTime.parse(bMsgs.last['created_at']);
        return bTime.compareTo(aTime);
      } catch (_) { return 0; }
    });
    return sorted;
  }

  String chatTitle(dynamic chat) {
    final users = chatUsers[chat['id']] ?? [];
    final other = users.where((u) => u['id'] != _auth.userId).toList();
    if (other.isNotEmpty) {
      return other.first['full_name'] ?? other.first['email']?.split('@').first ?? 'Chat';
    }
    final name = chat['name'] ?? '';
    return name.startsWith('Чат с ') ? name.substring(6) : name;
  }

  String lastPreview(int id) {
    final msgs = messages[id] ?? [];
    if (msgs.isEmpty) return 'Нет сообщений';
    final content = msgs.last['content'] ?? '';
    return content.length > 45 ? '${content.substring(0, 45)}...' : content;
  }

  String chatTime(int id) {
    final msgs = messages[id] ?? [];
    if (msgs.isEmpty) return '';
    try {
      final d = DateTime.parse(msgs.last['created_at']);
      final now = DateTime.now();
      if (now.difference(d).inMinutes < 1) return 'сейчас';
      if (now.difference(d).inHours < 24) return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      if (now.difference(d).inDays == 1) return 'вчера';
      return '${d.day}.${d.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  bool hasUnread(int id) {
    final msgs = messages[id] ?? [];
    if (msgs.isEmpty) return false;
    final last = msgs.last;
    if (last['user_id'] == _auth.userId) return false;
    final lastSeenId = lastSeenMsgId[id];
    if (lastSeenId == null) return true;
    return (last['id'] as int) > lastSeenId;
  }
}
