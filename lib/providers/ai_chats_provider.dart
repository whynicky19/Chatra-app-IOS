import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ai_thread.dart';
import '../services/api_service.dart';
import '../utils/errors.dart';
import 'auth_provider.dart';

/// Список тредов (чатов) главного ИИ-ассистента. Бэкенд — источник истины,
/// синхронизируется между устройствами. Мутации оптимистичны с откатом.
class AiChatsProvider extends ChangeNotifier {
  final ApiService _api;
  final AuthProvider _auth;

  List<AiThread> threads = [];
  bool loading = false;
  String? errorMessage;

  bool _legacyCleaned = false;

  AiChatsProvider(this._api, this._auth);

  void clearError() {
    errorMessage = null;
  }

  /// Сортировка как на бэке: закреплённые сверху, внутри — по свежести.
  void _sort() {
    threads.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      threads = await _api.getAiThreads();
      _sort();
      _cleanupLegacyCache();
    } catch (e) {
      logError('AiChatsProvider.load', e);
      errorMessage = 'err_load_data';
    }
    loading = false;
    notifyListeners();
  }

  Future<AiThread> createThread() async {
    final t = await _api.createAiThread();
    threads = [t, ...threads];
    _sort();
    notifyListeners();
    return t;
  }

  Future<void> rename(int id, String title) async {
    final idx = threads.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final prev = threads[idx].title;
    threads[idx].title = title;
    notifyListeners();
    try {
      await _api.renameAiThread(id, title);
    } catch (e) {
      threads[idx].title = prev;
      logError('AiChatsProvider.rename', e);
      errorMessage = 'connection_error';
      notifyListeners();
    }
  }

  Future<void> togglePin(int id) async {
    final idx = threads.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final next = !threads[idx].pinned;
    threads[idx].pinned = next;
    _sort();
    notifyListeners();
    try {
      await _api.pinAiThread(id, next);
    } catch (e) {
      final i = threads.indexWhere((t) => t.id == id);
      if (i >= 0) threads[i].pinned = !next;
      _sort();
      logError('AiChatsProvider.togglePin', e);
      errorMessage = 'connection_error';
      notifyListeners();
    }
  }

  Future<void> delete(int id) async {
    final idx = threads.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    final removed = threads[idx];
    threads.removeAt(idx);
    notifyListeners();
    try {
      await _api.deleteAiThread(id);
    } catch (e) {
      threads.insert(idx.clamp(0, threads.length), removed);
      _sort();
      logError('AiChatsProvider.delete', e);
      errorMessage = 'connection_error';
      notifyListeners();
    }
  }

  /// Локальный патч после отправки сообщения в детальном экране: обновляет
  /// заголовок/свежесть без полной перезагрузки списка.
  void patchLocal(int id, {String? title, DateTime? updatedAt}) {
    final idx = threads.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    if (title != null && title.isNotEmpty) threads[idx].title = title;
    if (updatedAt != null) threads[idx].updatedAt = updatedAt;
    _sort();
    notifyListeners();
  }

  /// Одноразовая уборка осиротевшего одно-тредового кэша (v1). Серверная
  /// миграция бэкапит старую историю в отдельный «legacy»-тред, локальный
  /// кэш больше не читается — просто удаляем его.
  Future<void> _cleanupLegacyCache() async {
    if (_legacyCleaned) return;
    _legacyCleaned = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = _auth.userId;
      await prefs.remove('ai_chat_history_v1_${uid ?? 'anon'}');
      await prefs.remove('ai_chat_history_v1');
    } catch (_) {}
  }
}
