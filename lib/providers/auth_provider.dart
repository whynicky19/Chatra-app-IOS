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
  String get group => _user?['group'] ?? '';
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

  Future<void> init() async {
    await api.loadToken();
    if (api.token != null) {
      try {
        _user = await api.me();
      } catch (_) {
        await api.clearToken();
        _user = null;
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password, {String orgType = 'university'}) async {
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
      return true;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String? lastError;

  Future<bool> register(String email, String password, String role, {String? fullName, String? group, String orgType = 'university'}) async {
    _isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      await api.register(email, password, role, fullName: fullName, group: group, orgType: orgType);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      final statusCode = (e is DioException) ? e.response?.statusCode : null;
      if (statusCode == 409) {
        lastError = 'Этот email уже зарегистрирован';
      } else if (statusCode == 400) {
        lastError = 'Такой группы не существует';
      } else {
        lastError = 'Ошибка регистрации. Попробуйте снова';
      }
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

  Future<void> logout() async {
    await api.clearToken();
    _user = null;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    try {
      _user = await api.me();
      notifyListeners();
    } catch (_) {}
  }
}
