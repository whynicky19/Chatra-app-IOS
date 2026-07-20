import 'dart:async';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';
import 'auth_provider.dart';

class ClassesProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<dynamic> posts = [];
  List<Map<String, dynamic>> _cachedAllClasses = [];
  Set<int> joinedClassIds = {};
  Set<int> archivedClassIds = {};
  final ValueNotifier<int> notifBadge = ValueNotifier<int>(0);
  int get unreadNotifCount => notifBadge.value;
  bool loading = true;
  String? errorMessage;

  ClassesProvider(this._api, this._auth);

  void clearError() {
    errorMessage = null;
  }

  Map<String, dynamic> _normalizeClass(Map<String, dynamic> c) => {
        ...c,
        'title': c['name'],
        'teacher_name': c['teacher'],
        'user_id': c['created_by'],
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
      logError('ClassesProvider.load', e);
      errorMessage = 'err_load_data';
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
        logError('ClassesProvider.loadSaved', e2);
        errorMessage = 'err_load_saved_classes';
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
      logError('ClassesProvider.save', e);
      errorMessage = 'err_save_classes';
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
      logError('ClassesProvider.join', e);
      errorMessage = 'err_join_class';
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
      logError('ClassesProvider.leave', e);
      errorMessage = 'err_leave_class';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> joinByCode(String code) async {
    final cls = await _api.joinByCode(code);
    final id = (cls['id'] as num).toInt();
    joinedClassIds.add(id);
    await _saveJoined();
    notifyListeners();
    unawaited(load());
    return _normalizeClass(cls);
  }

  Future<bool> deleteClass(int id) async {
    try {
      await _api.deleteClass(id);
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response?.data['detail'] : null;
      logError('ClassesProvider.deleteClass', e);
      errorMessage = detail?.toString() ?? 'err_delete_class';
      notifyListeners();
      return false;
    } catch (e) {
      logError('ClassesProvider.deleteClass', e);
      errorMessage = 'err_delete_class';
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
      logError('ClassesProvider.createClass', e);
      errorMessage = 'err_create_class';
      notifyListeners();
      rethrow;
    }
    await load();
  }

  void addCreatedClass(Map<String, dynamic> raw) {
    final normalized = _normalizeClass(raw);
    final id = (normalized['id'] as num?)?.toInt();
    if (id == null) return;
    if (!_cachedAllClasses.any((c) => (c['id'] as num?)?.toInt() == id)) {
      _cachedAllClasses = [normalized, ..._cachedAllClasses];
      notifyListeners();
    }
  }

  void patchCachedClass(int id, Map<String, dynamic> raw) {
    final idx = _cachedAllClasses.indexWhere((c) => (c['id'] as num?)?.toInt() == id);
    if (idx < 0) return;
    _cachedAllClasses[idx] = {..._cachedAllClasses[idx], ..._normalizeClass(raw)};
    notifyListeners();
  }

  Future<void> loadNotifBadge() async {
    if (_auth.isTeacher) return;
    try {
      List<dynamic> subs = [];
      List<dynamic> assignments = [];
      List<dynamic> states = [];
      await Future.wait([
        () async { try { subs = await _api.getMySubmissions(); } catch (_) {} }(),
        () async { try { assignments = await _api.getAssignments(); } catch (_) {} }(),
        () async { try { states = await _api.getNotifStates(); } catch (_) {} }(),
      ]);

      final stateBy = {
        for (final s in states)
          (s['notif_key'] ?? '').toString(): {
            'read': s['read'] == true, 'dismissed': s['dismissed'] == true,
          }
      };
      bool unread(String key) {
        final st = stateBy[key];
        return st == null || (st['read'] != true && st['dismissed'] != true);
      }

      int count = subs.where((s) =>
        s['status'] == 'graded' &&
        s['grade'] != null &&
        unread('grade:${(s['id'] as num?)?.toInt()}'),
      ).length;

      final now = DateTime.now();
      for (final a in assignments) {
        final aId  = (a['id'] as num?)?.toInt() ?? 0;
        final cid  = (a['class_id'] as num?)?.toInt();
        if (cid == null || !joinedClassIds.contains(cid)) continue;
        if (!unread('assignment:$aId')) continue;
        final createdAt = a['created_at'] != null ? DateTime.tryParse(a['created_at']) : null;
        if (createdAt != null && now.difference(createdAt).inDays <= 7) count++;
      }

      notifBadge.value = count;
    } catch (e) {
      logError('ClassesProvider.loadNotifications', e);
      errorMessage = 'err_load_notifications';
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

  bool _isArchived(Map<String, dynamic> c) =>
      !_auth.isTeacher && !_auth.isAdmin && archivedClassIds.contains(c['id'] as int);

  List<Map<String, dynamic>> get activeClasses =>
      classes.where((c) => !_isArchived(c)).toList();

  List<Map<String, dynamic>> get archivedClasses =>
      classes.where((c) => _isArchived(c)).toList();

  int lectureCount(int id) =>
    posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][$id]')).length;
}
