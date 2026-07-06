import 'dart:async';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class ClassesProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<dynamic> posts = [];
  List<Map<String, dynamic>> _cachedAllClasses = [];
  Set<int> joinedClassIds = {};
  // Классы, где студент состоит только в архивных потоках. Признак приходит
  // из GET /classes/ (там он считается per-student); /classes/all его не
  // отдаёт, поэтому храним отдельно, а не читаем c['is_archived_for_user'].
  Set<int> archivedClassIds = {};
  int unreadNotifCount = 0;
  bool loading = true;
  String? errorMessage;

  ClassesProvider(this._api, this._auth);

  void clearError() {
    errorMessage = null;
  }

  // The real Class API uses `name`/`teacher`/`created_by`; the rest of the UI
  // still reads the legacy Post-shaped keys (`title`/`teacher_name`/`user_id`).
  // Normalize once here instead of touching every call site.
  Map<String, dynamic> _normalizeClass(Map<String, dynamic> c) => {
        ...c,
        'title': c['name'],
        'teacher_name': c['teacher'],
        'user_id': c['created_by'],
        // Cohort fields — default safely so the UI keeps working against a
        // backend that predates the cohorts change (regular active-cohort flow).
        'rotation_mode': c['rotation_mode'] ?? 'manual',
        'is_archived_for_user': c['is_archived_for_user'] ?? false,
      };

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([_api.getAllClasses(), _api.getPosts()]);
      _cachedAllClasses = results[0]
          .map((c) => _normalizeClass(c as Map<String, dynamic>))
          .toList();
      posts = results[1];
    } catch (e) {
      errorMessage = 'Не удалось загрузить данные: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadJoined() async {
    final uid = _auth.userId ?? 0;
    try {
      final list = await _api.getClasses();
      joinedClassIds = list.map((c) => (c['id'] as num).toInt()).toSet();
      archivedClassIds = list
          .where((c) => c['is_archived_for_user'] == true)
          .map((c) => (c['id'] as num).toInt())
          .toSet();
      notifyListeners();
      await _saveJoined();
    } catch (e) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('joined_classes_$uid') ?? [];
        joinedClassIds = list.map(int.parse).toSet();
        notifyListeners();
      } catch (e2) {
        errorMessage = 'Ошибка загрузки сохранённых классов: $e2';
        notifyListeners();
      }
    }
  }

  Future<void> _saveJoined() async {
    final uid = _auth.userId ?? 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'joined_classes_$uid',
        joinedClassIds.map((e) => e.toString()).toList(),
      );
    } catch (e) {
      errorMessage = 'Ошибка сохранения списка классов: $e';
      notifyListeners();
    }
  }

  Future<void> joinClass(int id) async {
    joinedClassIds.add(id);
    notifyListeners();
    try {
      await _api.joinClass(id);
      await _saveJoined();
    } catch (e) {
      joinedClassIds.remove(id);
      errorMessage = 'Ошибка при вступлении в класс: $e';
      notifyListeners();
    }
  }

  Future<void> leaveClass(int id) async {
    joinedClassIds.remove(id);
    notifyListeners();
    try {
      await _api.leaveClass(id);
      await _saveJoined();
    } catch (e) {
      joinedClassIds.add(id);
      errorMessage = 'Ошибка при выходе из класса: $e';
      notifyListeners();
    }
  }

  /// Joins a class by its invite code via the real backend lookup (no more
  /// local guessing of a class's code from its id). Returns the joined class
  /// (normalized) on success.
  Future<Map<String, dynamic>> joinByCode(String code) async {
    final cls = await _api.joinByCode(code);
    final id = (cls['id'] as num).toInt();
    joinedClassIds.add(id);
    await _saveJoined();
    notifyListeners();
    unawaited(load());
    return _normalizeClass(cls);
  }

  /// Возвращает true при успехе. При ошибке кладёт человекочитаемый текст
  /// (detail с бэкенда, если есть) в [errorMessage], чтобы UI мог его показать
  /// вместо ложного «удалено».
  Future<bool> deleteClass(int id) async {
    try {
      await _api.deleteClass(id);
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response?.data['detail'] : null;
      errorMessage = detail?.toString() ?? 'Ошибка при удалении класса: ${e.message}';
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Ошибка при удалении класса: $e';
      notifyListeners();
      return false;
    }
    await load();
    return true;
  }

  Future<void> createClass(String name,
      {String? description, String? teacher, String? period, String? coverImage}) async {
    try {
      await _api.createClass(name,
          description: description, teacher: teacher, period: period, coverImage: coverImage);
    } catch (e) {
      errorMessage = 'Ошибка при создании класса: $e';
      notifyListeners();
      rethrow;
    }
    await load();
  }

  Future<void> loadNotifBadge() async {
    if (_auth.isTeacher) return;
    final uid = _auth.userId ?? 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenGrade = (prefs.getStringList('notif_seen_grade_$uid') ?? []).map(int.parse).toSet();
      final seenAsgn  = (prefs.getStringList('notif_seen_asgn_$uid')  ?? []).map(int.parse).toSet();
      final dismissed = (prefs.getStringList('notif_dismissed_$uid')   ?? []).toSet();

      List<dynamic> subs = [];
      List<dynamic> assignments = [];
      await Future.wait([
        () async { try { subs = await _api.getMySubmissions(); } catch (_) {} }(),
        () async { try { assignments = await _api.getAssignments(); } catch (_) {} }(),
      ]);

      // Unread grade notifications
      int count = subs.where((s) =>
        s['status'] == 'graded' &&
        s['grade'] != null &&
        !seenGrade.contains((s['id'] as num?)?.toInt()) &&
        !dismissed.contains('grade_${(s['id'] as num?)?.toInt()}'),
      ).length;

      // Unread new-assignment notifications (from joined classes, last 7 days)
      final now = DateTime.now();
      for (final a in assignments) {
        final aId  = (a['id'] as num?)?.toInt() ?? 0;
        final cid  = (a['class_id'] as num?)?.toInt();
        if (cid == null || !joinedClassIds.contains(cid)) continue;
        if (seenAsgn.contains(aId)) continue;
        if (dismissed.contains('asgn_$aId')) continue;
        final createdAt = a['created_at'] != null ? DateTime.tryParse(a['created_at']) : null;
        if (createdAt != null && now.difference(createdAt).inDays <= 7) count++;
      }

      unreadNotifCount = count;
      notifyListeners();
    } catch (e) {
      errorMessage = 'Не удалось загрузить уведомления: $e';
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> get allClasses => _cachedAllClasses;

  List<Map<String, dynamic>> get classes {
    if (_auth.isAdmin) return allClasses;
    if (_auth.isTeacher) {
      final myId = _auth.userId;
      return allClasses.where((c) {
        final isOwn = (c['user_id'] as num?)?.toInt() == myId;
        final isJoined = joinedClassIds.contains(c['id'] as int);
        return isOwn || isJoined;
      }).toList();
    }
    return allClasses.where((c) => joinedClassIds.contains(c['id'] as int)).toList();
  }

  // Classes the user is only in via archived cohorts — shown read-only in a
  // collapsed "Archive" section. Teachers/admins never see their classes as
  // archived (is_archived_for_user is a student-membership flag).
  bool _isArchived(Map<String, dynamic> c) =>
      !_auth.isTeacher && !_auth.isAdmin && archivedClassIds.contains(c['id'] as int);

  List<Map<String, dynamic>> get activeClasses =>
      classes.where((c) => !_isArchived(c)).toList();

  List<Map<String, dynamic>> get archivedClasses =>
      classes.where((c) => _isArchived(c)).toList();

  int lectureCount(int id) =>
    posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][$id]')).length;
}
