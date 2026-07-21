import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_service.dart';
import '../utils/message_attachment.dart';
import '../utils/errors.dart';
import 'auth_provider.dart';

class _ChatWsManager {
  final String? Function() urlBuilder;
  final void Function(Map<String, dynamic>) onMessage;
  final VoidCallback onFallbackNeeded;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;

  bool _disposed = false;
  bool _isConnected = false;
  bool _everConnected = false;
  int _failCount = 0;
  bool _handlingDisconnect = false;

  bool get isConnected => _isConnected;

  _ChatWsManager({
    required this.urlBuilder,
    required this.onMessage,
    required this.onFallbackNeeded,
  });

  void connect() {
    if (_disposed) return;
    _handlingDisconnect = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    try { _channel?.sink.close(); } catch (_) {}

    final wsUrl = urlBuilder();
    if (wsUrl == null) {
      _reconnectTimer = Timer(const Duration(seconds: 3), connect);
      return;
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      _sub = _channel!.stream.listen(
        (raw) {
          if (_disposed) return;
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

    if (!_everConnected && _failCount >= 3) {
      onFallbackNeeded();
      return;
    }

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

class ChatsProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  /// Пинг от PushService при пуше о новом сообщении: chat_id пришедшего
  /// сообщения. ChatsProvider слушает и мгновенно подтягивает счётчики
  /// непрочитанных, не дожидаясь очередного тика поллера.
  static final ValueNotifier<int?> pushChatPing = ValueNotifier<int?>(null);

  List<dynamic> chats = [];
  Map<int, List<dynamic>> messages = {};
  Map<int, List<dynamic>> chatUsers = {};
  int? activeChatId;
  bool loading = true;
  bool isScreenVisible = true;
  List<dynamic> searchResults = [];
  final Map<int, int> lastSeenMsgId = {};
  String? errorMessage;

  _ChatWsManager? _wsManager;
  Timer? _fallbackPoller;

  final Map<int, DateTime> _typingTimestamps = {};
  Timer? _typingCleaner;

  bool get someoneIsTyping => _typingTimestamps.isNotEmpty;

  /// Запрос открыть конкретный чат извне (тап по пуш-уведомлению о
  /// сообщении). MainShell параллельно переключает вкладку на «Чаты».
  static final ValueNotifier<int?> requestOpenChat = ValueNotifier<int?>(null);

  ChatsProvider(this._api, this._auth) {
    pushChatPing.addListener(_onPushPing);
    requestOpenChat.addListener(_onOpenChatRequest);
  }

  void _onPushPing() {
    final chatId = pushChatPing.value;
    if (chatId == null) return;
    pushChatPing.value = null;
    refreshChatSummaries();
    if (chatId == activeChatId) pollMessages();
  }

  void _onOpenChatRequest() {
    final chatId = requestOpenChat.value;
    if (chatId == null) return;
    requestOpenChat.value = null;
    setActiveChatId(chatId);
    markSeen(chatId);
  }

  @override
  void dispose() {
    pushChatPing.removeListener(_onPushPing);
    requestOpenChat.removeListener(_onOpenChatRequest);
    _disconnectWs();
    _stopFallbackPoller();
    _typingCleaner?.cancel();
    super.dispose();
  }

  void clearError() {
    errorMessage = null;
  }

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
      logError('ChatsProvider.loadSeenMsgIds', e);
      errorMessage = 'err_load_read_history';
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
      logError('ChatsProvider.save', e);
      errorMessage = 'err_save';
      notifyListeners();
    }
  }

  /// Список чатов + предпросмотр последнего сообщения и unread_count
  /// приходят одним лёгким запросом. Полную историю сообщений грузим только
  /// когда пользователь реально открывает чат (см. ensureMessagesLoaded) —
  /// раньше здесь тянулась вся история КАЖДОГО чата на старте и на каждом
  /// поллинге, что было главным источником лишнего трафика/лагов.
  Future<void> loadChats() async {
    loading = true;
    notifyListeners();
    try {
      chats = await _api.getChats();
      await Future.wait(chats.map((c) async {
        final id = (c['id'] as num).toInt();
        try {
          chatUsers[id] = await _api.getChatUsers(id);
        } catch (e) {
          logError('ChatsProvider.loadChatUsers', e);
          errorMessage = 'err_load_chat_members';
        }
      }));
      if (activeChatId != null) await ensureMessagesLoaded(activeChatId!);
    } catch (e) {
      logError('ChatsProvider.loadChats', e);
      errorMessage = 'err_load_chats';
    }
    loading = false;
    notifyListeners();
  }

  /// Подтягивает свежую историю чата при открытии. ВСЕГДА перезапрашивает
  /// (не только при первом заходе): WS живёт только пока чат активен, так
  /// что пока чат закрыт, ничего не обновляет его кэш — без принудительного
  /// рефетча при повторном открытии показывались бы старые сообщения.
  Future<void> ensureMessagesLoaded(int id) async {
    try {
      final fresh = await _api.getMessages(id);
      messages[id] = fresh;
      notifyListeners();
    } catch (e) {
      logError('ChatsProvider.ensureMessagesLoaded', e);
    }
  }

  /// Лёгкий поллинг: список чатов с unread_count и превью последнего
  /// сообщения, без полных тел сообщений. Не завязан на видимость вкладки —
  /// бейдж и превью должны обновляться, даже пока пользователь смотрит
  /// другой таб.
  Future<void> refreshChatSummaries() async {
    try {
      final fresh = await _api.getChats();
      final byId = {for (final c in fresh) (c['id'] as num).toInt(): c};
      bool changed = false;
      for (var i = 0; i < chats.length; i++) {
        final id = (chats[i]['id'] as num).toInt();
        final f = byId[id];
        if (f == null) continue;
        final curLastId = (chats[i]['last_message']?['id'] as num?)?.toInt();
        final freshLastId = (f['last_message']?['id'] as num?)?.toInt();
        if (chats[i]['unread_count'] != f['unread_count'] || curLastId != freshLastId) {
          chats[i] = f;
          changed = true;
        }
      }
      final knownIds = chats.map((c) => (c['id'] as num).toInt()).toSet();
      final newOnes = fresh.where((c) => !knownIds.contains((c['id'] as num).toInt()));
      if (newOnes.isNotEmpty) {
        chats = [...chats, ...newOnes];
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  /// Фолбэк-поллинг активного чата, когда WS не подключён. Остальные чаты
  /// (список/превью) обновляет refreshChatSummaries — без полной истории.
  Future<void> pollMessages() async {
    final id = activeChatId;
    if (id == null) return;
    if (_wsManager?.isConnected ?? false) return;
    try {
      final fresh = await _api.getMessages(id);
      if (_messagesDiffer(messages[id], fresh)) {
        messages[id] = fresh;
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _messagesDiffer(List<dynamic>? a, List<dynamic> b) {
    if (a == null) return b.isNotEmpty;
    if (a.length != b.length) return true;
    if (a.isEmpty) return false;
    final aLast = (a.last['id'] as num?)?.toInt();
    final bLast = (b.last['id'] as num?)?.toInt();
    return aLast != bLast;
  }

  Future<void> sendMessage(String content) async {
    if (activeChatId == null) return;
    final chatId = activeChatId!;
    try {
      final response = await _api.sendMessage(chatId, content);
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
      if (!(_wsManager?.isConnected ?? false)) {
        await pollMessages();
      }
    } catch (e) {
      logError('ChatsProvider.sendMessage', e);
      errorMessage = 'err_send_message';
      notifyListeners();
    }
  }

  /// Идёт ли сейчас загрузка вложения. UI блокирует кнопку "+" на время
  /// загрузки — иначе пользователь не видит прогресса и жмёт повторно,
  /// уходят два одинаковых сообщения.
  bool uploading = false;

  Future<String?> uploadAndSend(int chatId, String filePath, String fileName) async {
    if (uploading) return null;
    uploading = true;
    notifyListeners();
    try {
      final result = await _api.uploadFile(filePath, fileName);
      var url = result['url'] ?? result['file_url'] ?? result['path'] ?? '';
      if (url.isNotEmpty) {
        url = _api.toRelativeUploadUrl(url);
      }
      if (url.isNotEmpty) {
        final response = await _api.sendMessage(chatId, url);
        final msgId = (response['id'] as num?)?.toInt();
        if (msgId != null) {
          final msgs = List<dynamic>.from(messages[chatId] ?? []);
          if (!msgs.any((m) => (m['id'] as num?)?.toInt() == msgId)) {
            msgs.add(response);
            messages[chatId] = msgs;
            lastSeenMsgId[chatId] = msgId;
            saveSeenMsgIds();
          }
        }
        if (!(_wsManager?.isConnected ?? false)) await pollMessages();
        return null;
      }
      return 'err_file_url';
    } catch (e) {
      logError('ChatsProvider.uploadAndSend', e);
      return 'err_upload';
    } finally {
      uploading = false;
      notifyListeners();
    }
  }

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
      logError('ChatsProvider.searchUsers', e);
      errorMessage = 'err_search_users';
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
        _connectWs((c['id'] as num).toInt());
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
      _connectWs((chat['id'] as num).toInt());
      notifyListeners();
      return true;
    } catch (e) {
      logError('ChatsProvider.createChat', e);
      errorMessage = 'err_create_chat';
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
      logError('ChatsProvider.deleteChat', e);
      errorMessage = 'err_delete_chat';
      notifyListeners();
      return false;
    }
  }

  void setActiveChatId(int? id) {
    if (activeChatId == id) return;
    if (id == null) {
      _disconnectWs();
      _stopFallbackPoller();
    }
    activeChatId = id;
    if (id != null) {
      _connectWs(id);
      ensureMessagesLoaded(id);
    }
    notifyListeners();
  }

  void markSeen(int chatId) {
    final msgs = messages[chatId] ?? [];
    if (msgs.isNotEmpty) {
      final id = (msgs.last['id'] as num?)?.toInt();
      if (id != null) lastSeenMsgId[chatId] = id;
    }
    final idx = chats.indexWhere((c) => (c['id'] as num).toInt() == chatId);
    if (idx != -1 && (chats[idx]['unread_count'] ?? 0) != 0) {
      chats[idx] = {...chats[idx] as Map, 'unread_count': 0};
    }
    notifyListeners();
    saveSeenMsgIds();
    _api.markChatRead(chatId).catchError((e) {
      logError('ChatsProvider.markSeen', e);
    });
  }

  int unreadCount(int id) {
    final c = chats.firstWhere(
      (c) => (c['id'] as num?)?.toInt() == id,
      orElse: () => const {},
    );
    return (c['unread_count'] as num?)?.toInt() ?? 0;
  }

  void _connectWs(int chatId) {
    _disconnectWs();
    _stopFallbackPoller();
    _typingTimestamps.clear();

    _wsManager = _ChatWsManager(
      urlBuilder: () {
        final token = _api.token;
        if (token == null) return null;
        return '${_api.wsBaseUrl}/ws/$chatId?token=$token';
      },
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
          _api.markChatRead(chatId).catchError((e) {
            logError('ChatsProvider._handleWsMessage', e);
          });
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
      final before = _typingTimestamps.length;
      final cutoff = DateTime.now().subtract(const Duration(seconds: 3));
      _typingTimestamps.removeWhere((_, ts) => ts.isBefore(cutoff));
      if (_typingTimestamps.length != before) notifyListeners();
    });
  }

  void sendTyping() {
    _wsManager?.send({'type': 'typing'});
  }

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

  /// Последнее сообщение чата: если полная история уже загружена (чат
  /// открывали) — берём оттуда, иначе — превью с сервера из /chats/.
  dynamic _lastMsgFor(int id) {
    final loaded = messages[id];
    if (loaded != null && loaded.isNotEmpty) return loaded.last;
    final idx = chats.indexWhere((c) => (c['id'] as num?)?.toInt() == id);
    return idx == -1 ? null : chats[idx]['last_message'];
  }

  List<dynamic> get sortedChats {
    final sorted = List<dynamic>.from(chats);
    sorted.sort((a, b) {
      final aMsg = _lastMsgFor((a['id'] as num).toInt());
      final bMsg = _lastMsgFor((b['id'] as num).toInt());
      if (aMsg == null && bMsg == null) return 0;
      if (aMsg == null) return 1;
      if (bMsg == null) return -1;
      try {
        final aTime = DateTime.parse(aMsg['created_at']);
        final bTime = DateTime.parse(bMsg['created_at']);
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

  String? lastPreview(int id) {
    final last = _lastMsgFor(id);
    if (last == null) return null;
    final String content = last['content'] ?? '';
    final attachment = _attachmentPreviewKey(content);
    if (attachment != null) return attachment;
    return content.length > 45 ? '${content.substring(0, 45)}...' : content;
  }

  /// Превью вложения в списке чатов. Разбор общий с бабблом: сайт шлёт
  /// вложения markdown-ссылкой, приложение — голым URL.
  String? _attachmentPreviewKey(String content) {
    final att = parseMessageAttachment(content);
    if (att == null) return null;
    return att.isImage ? 'preview_photo' : 'preview_file';
  }

  String chatTime(int id) {
    final last = _lastMsgFor(id);
    if (last == null) return '';
    try {
      final d = DateTime.parse(last['created_at']);
      final now = DateTime.now();
      if (now.difference(d).inMinutes < 1) return 'time_now';
      if (now.difference(d).inHours < 24) return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      if (now.difference(d).inDays == 1) return 'time_yesterday';
      return '${d.day}.${d.month.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  bool hasUnread(int id) => unreadCount(id) > 0;
}
