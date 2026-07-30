import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../utils/initials.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService api;

  AuthProvider(this.api);

  Future<void> Function()? onLogin;
  Future<void> Function()? onLogout;

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

  String get initials => initialsFrom(fullName, email: email);

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
        if (_user != null) onLogin?.call();
      } on DioException catch (e) {
        // Токен стираем только на 401/403. На сети/5xx оставляем, иначе офлайн-запуск разлогинивает.
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) {
          await api.clearToken();
          _user = null;
        }
      } catch (_) {
      }
    }
    _initialized = true;
    notifyListeners();
  }

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
      onLogin?.call();
      _isLoading = false;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      _isLoading = false;
      notifyListeners();
      final status = e.response?.statusCode ?? 0;
      final detail = (e.response?.data is Map) ? e.response!.data['detail'] : null;
      if (status == 429) return 'login_rate_limited';
      if (status == 403 && detail == 'email_not_verified') return 'email_not_verified';
      if (status == 403) return 'account_blocked';
      if (e.response == null) return 'no_connection';
      return 'wrong_creds';
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      return 'wrong_creds';
    }
  }

  String? lastError;

  bool lastRegisterEmailSent = true;

  Future<bool> register(String email, String password, String role, {String? fullName, String orgType = 'university'}) async {
    _isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      final created = await api.register(email, password, role,
          fullName: fullName, orgType: orgType);
      lastRegisterEmailSent = created['email_sent'] != false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
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

  bool _loggingOut = false;

  Future<void> logout({String? reason}) async {
    // Гвард обязателен: logout шлёт запросы, 401 зовёт logout — без него бесконечный каскад.
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      await _performLogout(reason: reason);
    } finally {
      _loggingOut = false;
    }
  }

  Future<void> _performLogout({String? reason}) async {
    await onLogout?.call();
    if (reason == null) await api.logoutServer();
    await api.clearToken();
    _user = null;
    _sessionEndReason = reason;
    notifyListeners();
  }

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

  Future<String?> verifyEmail(String email, String code, {String orgType = 'university'}) async {
    try {
      await api.verifyEmail(email, code, orgType: orgType);
      _user = await api.me();
      onLogin?.call();
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

  Future<({bool sent, String devCode})?> resendVerification(String email,
      {String orgType = 'university'}) async {
    try {
      final resp = await api.resendVerification(email, orgType: orgType);
      return (
        sent: resp['sent'] == true,
        devCode: (resp['dev_code'] ?? '').toString(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) return null;
      rethrow;
    }
  }

  Future<String> forgotPassword(String email, {String orgType = 'university'}) async {
    final resp = await api.forgotPassword(email, orgType: orgType);
    return (resp['dev_code'] ?? '').toString();
  }

  Future<String?> resetPassword(String email, String code, String newPassword,
      {String orgType = 'university'}) async {
    try {
      await api.resetPassword(email, code, newPassword, orgType: orgType);
      _user = await api.me();
      onLogin?.call();
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
