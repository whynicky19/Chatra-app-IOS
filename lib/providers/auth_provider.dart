import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService api;

  AuthProvider(this.api);

  Map<String, dynamic>? _user;
  bool _isLoading = false;
  bool _initialized = false;

  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null && api.token != null;
  bool get isAdmin => _user?['role'] == 'admin';
  bool get isTeacher => _user?['role'] == 'teacher' || _user?['role'] == 'admin';
  String get role => _user?['role'] ?? 'student';
  int? get userId => _user?['id'];
  String get email => _user?['email'] ?? '';
  String get fullName => _user?['full_name'] ?? '';
  bool get initialized => _initialized;

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    return email.split('@').first;
  }

  String get initials {
    if (fullName.isNotEmpty) {
      final parts = fullName.split(' ');
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return fullName[0].toUpperCase();
    }
    return email.isNotEmpty ? email[0].toUpperCase() : '?';
  }

  // Причина завершения сессии (например 'account_blocked') — экран входа
  // покажет её один раз через consumeSessionEndReason().
  String? _sessionEndReason;
  String? consumeSessionEndReason() {
    final r = _sessionEndReason;
    _sessionEndReason = null;
    return r;
  }

  Future<void> init() async {
    await api.loadToken();
    if (api.token != null) {
      try {
        _user = await api.me();
      } on DioException catch (e) {
        // Токен стираем ТОЛЬКО если он реально невалиден (401/403 отдаёт
        // интерсептор после неудачного refresh). При сетевой ошибке/таймауте/5xx
        // (e.response == null или >=500) токен оставляем: иначе запуск офлайн
        // разлогинивал бы пользователя без причины. me() остаётся null —
        // приложение поднимется, когда сеть вернётся (refreshUser).
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) {
          await api.clearToken();
          _user = null;
        }
      } catch (_) {
        // Непредвиденная (не Dio) ошибка — консервативно оставляем сессию.
      }
    }
    _initialized = true;
    notifyListeners();
  }

  /// Возвращает null при успехе, иначе — ключ L10n для показа на экране входа
  /// ('wrong_creds' / 'login_rate_limited' / 'account_blocked' / 'no_connection').
  Future<String?> login(String email, String password, {String orgType = 'university'}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await api.login(email, password, orgType: orgType);
      final token = data['access_token'] as String;
      await api.saveToken(token);
      final refreshToken = data['refresh_token'] as String?;
      if (refreshToken != null) await api.saveRefreshToken(refreshToken);
      _user = await api.me();
      _isLoading = false;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      _isLoading = false;
      notifyListeners();
      final status = e.response?.statusCode ?? 0;
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (status == 429) return 'login_rate_limited';
      // Оба — 403, но ведут в разные места: не подтверждён email → экран кода,
      // заблокирован админом → сообщение.
      if (status == 403 && detail == 'email_not_verified') return 'email_not_verified';
      if (status == 403) return 'account_blocked';
      // Нет ответа сервера — сеть/таймаут (не путать с неверным паролем).
      if (e.response == null) return 'no_connection';
      return 'wrong_creds';
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return 'wrong_creds';
    }
  }

  String? lastError;

  Future<bool> register(String email, String password, String role, {String? fullName, String orgType = 'university'}) async {
    _isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      await api.register(email, password, role, fullName: fullName, orgType: orgType);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      // AP-2: храним семантический КЛЮЧ ошибки, а не русский текст — экран
      // регистрации переводит его через L10n (kk/en больше не видят русский).
      final statusCode = (e is DioException) ? e.response?.statusCode : null;
      lastError = (statusCode == 409) ? 'email_taken' : 'register_error';
      notifyListeners();
      return false;
    }
  }

  Future<void> updateProfile(String fullName) async {
    try {
      await api.updateMe(fullName);
      _user?['full_name'] = fullName;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> logout({String? reason}) async {
    // Серверный отзыв токенов (best-effort) до локальной очистки, пока токен
    // ещё в памяти. Не выполняем при forced-logout (reason задан) — там токен
    // уже недействителен/очищен интерсептором, лишний запрос бессмыслен.
    if (reason == null) await api.logoutServer();
    await api.clearToken();
    _user = null;
    _sessionEndReason = reason;
    notifyListeners();
  }

  /// Меняет пароль. Возвращает null при успехе, иначе ключ L10n ошибки.
  Future<String?> changePassword(String currentPassword, String newPassword) async {
    try {
      await api.changePassword(currentPassword, newPassword);
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (status == 400 && detail == 'wrong_current_password') return 'wrong_current_password';
      if (e.response == null) return 'no_connection';
      return 'change_password_error';
    } catch (_) {
      return 'change_password_error';
    }
  }

  /// Удаляет аккаунт (подтверждение паролем). null при успехе, иначе ключ ошибки.
  Future<String?> deleteAccount(String password) async {
    try {
      await api.deleteAccount(password);
      await api.clearToken();
      _user = null;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (status == 400 && detail == 'wrong_current_password') return 'wrong_current_password';
      if (e.response == null) return 'no_connection';
      return 'delete_account_error';
    } catch (_) {
      return 'delete_account_error';
    }
  }

  // ── Верификация email / восстановление пароля ───────────────────────────────

  /// Подтверждает email кодом и авто-входит (устанавливает _user). null при
  /// успехе, иначе ключ L10n ('invalid_code' / 'no_connection' / 'verify_error').
  Future<String?> verifyEmail(String email, String code, {String orgType = 'university'}) async {
    try {
      await api.verifyEmail(email, code, orgType: orgType);
      _user = await api.me();
      notifyListeners();
      return null;
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (e.response?.statusCode == 400 && detail == 'invalid_code') return 'invalid_code';
      if (e.response == null) return 'no_connection';
      return 'verify_error';
    } catch (_) {
      return 'verify_error';
    }
  }

  /// Повторно шлёт код подтверждения. Возвращает dev_code (только в dev), либо ''.
  /// Кидает 'no_connection'/'code_send_error' как исключение-ключ при сбое.
  Future<String?> resendVerification(String email, {String orgType = 'university'}) async {
    try {
      final resp = await api.resendVerification(email, orgType: orgType);
      return (resp['dev_code'] ?? '').toString();
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) return null; // rate-limit — код уже слали недавно
      rethrow;
    }
  }

  /// Запрашивает код сброса пароля. Возвращает dev_code (только в dev), либо ''.
  Future<String> forgotPassword(String email, {String orgType = 'university'}) async {
    final resp = await api.forgotPassword(email, orgType: orgType);
    return (resp['dev_code'] ?? '').toString();
  }

  /// Сбрасывает пароль по коду и авто-входит. null при успехе, иначе ключ L10n.
  Future<String?> resetPassword(String email, String code, String newPassword,
      {String orgType = 'university'}) async {
    try {
      await api.resetPassword(email, code, newPassword, orgType: orgType);
      _user = await api.me();
      notifyListeners();
      return null;
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (e.response?.statusCode == 400 && detail == 'invalid_code') return 'invalid_code';
      if (e.response == null) return 'no_connection';
      return 'reset_error';
    } catch (_) {
      return 'reset_error';
    }
  }

  Future<void> refreshUser() async {
    try {
      _user = await api.me();
      notifyListeners();
    } catch (_) {}
  }
}
