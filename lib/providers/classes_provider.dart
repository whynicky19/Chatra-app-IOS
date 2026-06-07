import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class ClassesProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<dynamic> posts = [];
  Set<int> joinedClassIds = {};
  int unreadNotifCount = 0;
  bool loading = true;
  String? errorMessage;

  ClassesProvider(this._api, this._auth);

  void clearError() {
    errorMessage = null;
  }

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      posts = await _api.getPosts();
    } catch (e) {
      errorMessage = 'Не удалось загрузить данные: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadJoined() async {
    final uid = _auth.userId ?? 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('joined_classes_$uid') ?? [];
      joinedClassIds = list.map(int.parse).toSet();
      notifyListeners();
    } catch (e) {
      errorMessage = 'Ошибка загрузки сохранённых классов: $e';
      notifyListeners();
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
    await _saveJoined();
    try {
      await _api.enrollPostClass(id);
    } catch (e) {
      errorMessage = 'Ошибка при вступлении в класс: $e';
      notifyListeners();
    }
  }

  Future<void> leaveClass(int id) async {
    joinedClassIds.remove(id);
    notifyListeners();
    await _saveJoined();
    try {
      await _api.leavePostClass(id);
    } catch (e) {
      errorMessage = 'Ошибка при выходе из класса: $e';
      notifyListeners();
    }
  }

  Future<void> deleteClass(int id) async {
    try {
      await _api.deletePost(id);
    } catch (e) {
      errorMessage = 'Ошибка при удалении класса: $e';
      notifyListeners();
      return;
    }
    await load();
  }

  Future<void> createClass(String title, String body) async {
    try {
      await _api.createPost(title, body);
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

  List<Map<String, dynamic>> get allClasses {
    return posts.where((p) {
      try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; }
    }).map((p) {
      try {
        final b = jsonDecode(p['body']);
        return {...p as Map<String, dynamic>, ...b as Map<String, dynamic>, 'title': p['title']};
      } catch (_) { return p as Map<String, dynamic>; }
    }).toList();
  }

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

  int lectureCount(int id) =>
    posts.where((p) => (p['title'] ?? '').startsWith('[LECTURE][$id]')).length;
}
