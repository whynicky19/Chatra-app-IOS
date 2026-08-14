import 'dart:async';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';
import '../utils/notif_feed.dart';
import 'auth_provider.dart';

class ClassesProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<Map<String, dynamic>> _cachedAllClasses = [];
  Set<int> joinedClassIds = {};
  Set<int> archivedClassIds = {};
  final ValueNotifier<int> notifBadge = ValueNotifier<int>(0);
  int get unreadNotifCount => notifBadge.value;
  bool loading = true;
  String? errorMessage;

  ClassesProvider(this._api, this._auth);

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    notifyListeners();
  }

  /// Полная очистка при выходе/смене аккаунта. Провайдер живёт всё время работы
  /// процесса (создан в main), поэтому без явного сброса классы, посты, бейдж и
  /// список вступлений предыдущего пользователя остаются на экране до тех пор,
  /// пока не отработает load() нового — а в офлайне не пропадают вовсе.
  void reset() {
    _cachedAllClasses = [];
    _myClassesRaw = null;
    // Забываем загрузку прошлого аккаунта: без этого первый же loadJoined()
    // нового пользователя приклеился бы к запросу, отправленному со старым
    // токеном, и получил бы чужой список классов.
    _joinedInFlight = null;
    joinedClassIds = {};
    archivedClassIds = {};
    notifBadge.value = 0;
    loading = true;
    errorMessage = null;
    notifyListeners();
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
      // Раньше рядом с классами грузился ещё и GET /posts/?page_size=100 —
      // все лекции всех классов сразу. Их результат клался в `posts`, который
      // никто никогда не читал: у экрана класса свой запрос с class_id. При
      // этом Future.wait ждал ОБА ответа, то есть скелет на главной висел до
      // самого медленного из них, а самый тяжёлый payload приложения качался и
      // разбирался ровно в тот момент, когда строится первый экран после
      // логина. Запрос убран целиком.
      final list = await _api.getAllClasses();
      _cachedAllClasses =
          list.map((c) => _normalizeClass(c as Map<String, dynamic>)).toList();
    } catch (e) {
      logError('ClassesProvider.load', e);
      errorMessage = 'err_load_data';
    }
    loading = false;
    notifyListeners();
  }

  /// Сырой ответ последнего УСПЕШНОГО `GET /classes/`. Тот же список нужен
  /// ленте уведомлений (названия классов), и раньше она запрашивала его вторым
  /// запросом параллельно с этим — два одинаковых обращения к серверу на
  /// каждое открытие главной. `null` — членство ни разу не загрузилось (или
  /// сбросили аккаунт): тогда фид сходит за списком сам.
  List<dynamic>? _myClassesRaw;

  /// Загрузка членства «в полёте». Служит двум целям: не пускать второй такой
  /// же запрос (главная зовёт loadJoined и из initState, и из pull-to-refresh)
  /// и дать [loadNotifBadge] точку синхронизации — он ждёт именно эту загрузку
  /// вместо того, чтобы гонять свою копию запроса или читать устаревший кэш.
  Future<void>? _joinedInFlight;

  Future<void> loadJoined() {
    final existing = _joinedInFlight;
    if (existing != null) return existing;
    final future = _loadJoined().whenComplete(() => _joinedInFlight = null);
    _joinedInFlight = future;
    return future;
  }

  Future<void> _loadJoined() async {
    final uid = _auth.userId ?? 0;
    try {
      final list = await _api.getClasses();
      _myClassesRaw = list;
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
      {String? description,
      String? teacher,
      String? period,
      String? coverColor,
      String? coverIcon}) async {
    try {
      await _api.createClass(name,
          description: description, teacher: teacher, period: period,
          coverColor: coverColor, coverIcon: coverIcon);
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

  /// Число на колокольчике — это ровно `unreadCount` того же фида, который
  /// покажет экран уведомлений (см. [loadNotifFeed]). Своей копии правил здесь
  /// больше нет: из-за неё бейдж показывал непрочитанные, которых в списке не
  /// было, а отметить прочитанным их было невозможно.
  ///
  /// Фид сам берёт членство в классах с сервера, поэтому этот метод больше не
  /// зависит от того, успел ли до него отработать [loadJoined].
  Future<void> loadNotifBadge() async {
    if (_auth.isTeacher) return;
    try {
      // Список классов берём у загрузки членства, а не запрашиваем свой.
      // Порядок важен: если она прямо сейчас в полёте (pull-to-refresh зовёт
      // обе разом) — ждём её и получаем свежий ответ; если уже отработала —
      // берём готовый; и только если членство не грузилось ни разу, запускаем
      // загрузку сами. Раньше вместо этого всегда шёл второй такой же запрос,
      // причём параллельно первому.
      final inFlight = _joinedInFlight;
      if (inFlight != null) {
        await inFlight;
      } else if (_myClassesRaw == null) {
        await loadJoined();
      }
      final feed = await loadNotifFeed(_api, myClasses: _myClassesRaw);
      notifBadge.value = feed.unreadCount;
    } catch (e) {
      // Бейдж — фоновая задача, пользователю о её сбое сообщать нечего.
      // Раньше errorMessage всплывал тостом поверх произвольного экрана.
      logError('ClassesProvider.loadNotifications', e);
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
}
