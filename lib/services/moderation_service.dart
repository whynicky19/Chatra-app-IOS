import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UGC-модерация (App Store Guideline 1.2): пользователь может заблокировать
/// другого пользователя и пожаловаться на контент. Блок-лист хранится локально
/// и переживает перезапуск; список отдельный для каждого аккаунта.
///
/// ⚠️ Замени на реальный адрес модерации — сюда уходят жалобы. Разработчик
/// обязан реагировать на жалобы в течение 24 часов (требование Apple).
const String kModerationEmail = 'chatra.support@gmail.com';

class ModerationService extends ChangeNotifier {
  Set<int> _blocked = {};
  String _blockedKey = 'blocked_users_v1_anon';
  String _reportsKey = 'ugc_reports_v1_anon';

  Set<int> get blockedIds => _blocked;
  bool isBlocked(int? userId) => userId != null && _blocked.contains(userId);

  /// Загрузить блок-лист для конкретного аккаунта (вызывать при старте и после
  /// логина/смены пользователя).
  Future<void> configure(int? uid) async {
    final suffix = uid?.toString() ?? 'anon';
    _blockedKey = 'blocked_users_v1_$suffix';
    _reportsKey = 'ugc_reports_v1_$suffix';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_blockedKey);
      _blocked = raw == null || raw.isEmpty
          ? <int>{}
          : (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toSet();
    } catch (_) {
      _blocked = {};
    }
    notifyListeners();
  }

  Future<void> block(int userId) async {
    if (_blocked.add(userId)) {
      await _persistBlocked();
      notifyListeners();
    }
  }

  Future<void> unblock(int userId) async {
    if (_blocked.remove(userId)) {
      await _persistBlocked();
      notifyListeners();
    }
  }

  Future<void> _persistBlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_blockedKey, jsonEncode(_blocked.toList()));
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
