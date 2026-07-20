import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// UGC-модерация (App Store Guideline 1.2): пользователь может заблокировать
/// другого пользователя и пожаловаться на контент.
///
/// Источник истины по блок-листу — сервер (таблица user_blocks): он переживает
/// переустановку и синхронизируется между устройствами. Локальный кэш в
/// SharedPreferences остаётся для мгновенной отрисовки и работы оффлайн, а
/// изменения, сделанные без сети, копятся в очереди и досылаются при следующей
/// синхронизации.
///
/// Жалобы теперь уходят на сервер (POST /reports) и видны админу; разработчик
/// обязан реагировать на них в течение 24 часов (требование Apple). Этот адрес
/// оставлен как общий контакт поддержки/модерации (в самом флоу жалоб не участвует).
const String kModerationEmail = 'chatra.support@gmail.com';

class ModerationService extends ChangeNotifier {
  ModerationService(this._api);

  final ApiService _api;

  /// id → отображаемое имя. Локальное зеркало серверного блок-листа: держим
  /// имена рядом с id, чтобы экран «Заблокированные» рисовался мгновенно и
  /// работал оффлайн.
  Map<int, String> _blocked = {};
  /// Операции, не доехавшие до сервера (оффлайн). Досылаются при следующем sync.
  Set<int> _pendingBlock = {};
  Set<int> _pendingUnblock = {};

  String _blockedKey = 'blocked_users_v2_anon';
  String _pendingKey = 'blocked_pending_v1_anon';
  String _reportsKey = 'ugc_reports_v1_anon';

  Set<int> get blockedIds => _blocked.keys.toSet();
  Map<int, String> get blockedUsers => Map.unmodifiable(_blocked);
  bool isBlocked(int? userId) => userId != null && _blocked.containsKey(userId);

  /// Загрузить блок-лист для конкретного аккаунта (вызывать при старте и после
  /// логина/смены пользователя): сперва кэш, затем синхронизация с сервером.
  Future<void> configure(int? uid) async {
    final suffix = uid?.toString() ?? 'anon';
    _blockedKey = 'blocked_users_v2_$suffix';
    _pendingKey = 'blocked_pending_v1_$suffix';
    _reportsKey = 'ugc_reports_v1_$suffix';
    try {
      final prefs = await SharedPreferences.getInstance();
      _blocked = _decode(prefs.getString(_blockedKey));
      _loadPending(prefs.getString(_pendingKey));
      if (_blocked.isEmpty) {
        // Миграция с v1 (просто список id, без имён). Такие блокировки ещё
        // нигде не зарегистрированы на сервере — ставим их в очередь на отправку.
        final legacy = prefs.getString('blocked_users_v1_$suffix');
        if (legacy != null && legacy.isNotEmpty) {
          _blocked = {
            for (final e in jsonDecode(legacy) as List) (e as num).toInt(): '',
          };
          _pendingBlock.addAll(_blocked.keys);
          await _persistBlocked();
        }
      }
    } catch (_) {
      _blocked = {};
      _pendingBlock = {};
      _pendingUnblock = {};
    }
    notifyListeners();

    if (uid != null) await syncFromServer();
  }

  /// Досылает отложенные операции и подтягивает серверный список.
  /// Оффлайн — тихо выходим, локальный кэш остаётся актуальным для UI.
  Future<void> syncFromServer() async {
    try {
      for (final id in _pendingBlock.toList()) {
        await _api.blockUser(id);
        _pendingBlock.remove(id);
      }
      for (final id in _pendingUnblock.toList()) {
        await _api.unblockUserApi(id);
        _pendingUnblock.remove(id);
      }

      final rows = await _api.getBlocks();
      _blocked = {
        for (final r in rows)
          ((r['user_id'] as num).toInt()): (r['name'] ?? '').toString(),
      };
      await _persistBlocked();
      notifyListeners();
    } catch (_) {
      // Нет сети / сервер недоступен — работаем на кэше, повторим позже.
    }
  }

  Map<int, String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(int.parse(k), (v ?? '').toString()));
    } catch (_) {
      return {};
    }
  }

  void _loadPending(String? raw) {
    _pendingBlock = {};
    _pendingUnblock = {};
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _pendingBlock =
          ((m['block'] ?? []) as List).map((e) => (e as num).toInt()).toSet();
      _pendingUnblock =
          ((m['unblock'] ?? []) as List).map((e) => (e as num).toInt()).toSet();
    } catch (_) {}
  }

  Future<void> block(int userId, {String? name}) async {
    final existing = _blocked[userId];
    // Не затираем уже сохранённое имя пустым, если блок повторный.
    final resolved = (name != null && name.isNotEmpty) ? name : (existing ?? '');
    // Оптимистично: контент нарушителя должен пропасть сразу, не дожидаясь сети.
    _blocked[userId] = resolved;
    _pendingUnblock.remove(userId);
    notifyListeners();

    try {
      await _api.blockUser(userId);
      _pendingBlock.remove(userId);
    } catch (_) {
      // Оффлайн — дошлём при следующей синхронизации, блок уже виден локально.
      _pendingBlock.add(userId);
    }
    await _persistBlocked();
  }

  Future<void> unblock(int userId) async {
    _blocked.remove(userId);
    _pendingBlock.remove(userId);
    notifyListeners();

    try {
      await _api.unblockUserApi(userId);
      _pendingUnblock.remove(userId);
    } catch (_) {
      _pendingUnblock.add(userId);
    }
    await _persistBlocked();
  }

  Future<void> _persistBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_blockedKey,
          jsonEncode(_blocked.map((k, v) => MapEntry(k.toString(), v))));
      await prefs.setString(_pendingKey, jsonEncode({
        'block': _pendingBlock.toList(),
        'unblock': _pendingUnblock.toList(),
      }));
    } catch (_) {}
  }

  /// Записать жалобу локально (журнал на устройстве). Отправка модератору идёт
  /// отдельно (email); локальная запись — на случай оффлайна и для истории.
  Future<void> recordReport({
    required int reportedUserId,
    required String reason,
    String? content,
    int? messageId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_reportsKey);
      final list = raw == null || raw.isEmpty
          ? <dynamic>[]
          : (jsonDecode(raw) as List);
      list.add({
        'reported_user_id': reportedUserId,
        'reason': reason,
        if (content != null) 'content': content,
        if (messageId != null) 'message_id': messageId,
        'at': DateTime.now().toIso8601String(),
      });
      await prefs.setString(_reportsKey, jsonEncode(list));
    } catch (_) {}
  }
}
