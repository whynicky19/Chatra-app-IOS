import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  late final Dio _dio;
  String? _token;
  VoidCallback? onUnauthorized;

  // Default baseUrl. В main.dart мы переопределяем его на лету через _resolveBaseUrl()
  // в зависимости от платформы (iOS/Android/web). Это значение тут — на крайний случай.
  static const String defaultBaseUrl = 'http://127.0.0.1:8000';

  String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? defaultBaseUrl {
    _dio = Dio(BaseOptions(
      baseUrl: this.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          onUnauthorized?.call();
        }
        return handler.next(error);
      },
    ));
  }

  void setToken(String? token) {
    _token = token;
  }

  String? get token => _token;

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('_tk');
  }

  Future<void> saveToken(String token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('_tk', token);
  }

  Future<void> clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('_tk');
  }

  // ── Auth ──
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post('/auth/login',
      data: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> register(String email, String password, String role, {String? fullName, String? group}) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'role': role,
      if (fullName != null) 'full_name': fullName,
      if (group != null) 'group': group,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/auth/me');
    return response.data;
  }

  Future<Map<String, dynamic>> updateMe(String fullName, {String? group}) async {
    final response = await _dio.patch('/auth/me', data: {
      'full_name': fullName,
      if (group != null) 'group': group,
    });
    return response.data;
  }

  Future<List<String>> searchGroups(String q) async {
    final response = await _dio.get('/auth/groups/search', queryParameters: {'q': q});
    return List<String>.from(response.data);
  }

  // ── Posts (Classes storage) ──
  Future<List<dynamic>> getPosts() async {
    final response = await _dio.get('/posts/');
    return response.data;
  }

  Future<Map<String, dynamic>> createPost(String title, String body) async {
    final response = await _dio.post('/posts/create', data: {'title': title, 'body': body});
    return response.data;
  }

  Future<Map<String, dynamic>> updatePost(int id, String title, String body) async {
    final response = await _dio.put('/posts/$id', data: {'title': title, 'body': body});
    return response.data;
  }

  Future<void> deletePost(int id) async {
    await _dio.delete('/posts/$id');
  }

  // ── Classes ──
  Future<List<dynamic>> getClasses() async {
    final response = await _dio.get('/classes/');
    return response.data;
  }

  Future<List<dynamic>> getAllClasses() async {
    final response = await _dio.get('/classes/all');
    return response.data;
  }

  Future<Map<String, dynamic>> getClass(int id) async {
    final response = await _dio.get('/classes/$id');
    return response.data;
  }

  Future<void> joinClass(int classId) async {
    await _dio.post('/classes/$classId/join', data: {});
  }

  Future<void> leaveClass(int classId) async {
    await _dio.delete('/classes/$classId/leave');
  }

  Future<Map<String, dynamic>> createClass(String name, {String? description}) async {
    final response = await _dio.post('/classes/', data: {
      'name': name,
      if (description != null) 'description': description,
    });
    return response.data;
  }

  Future<void> deleteClass(int classId) async {
    await _dio.delete('/classes/$classId');
  }

  // ── Assignments ──
  Future<List<dynamic>> getAssignments({int? classId}) async {
    final params = classId != null ? '?class_id=$classId' : '';
    final response = await _dio.get('/assignments/$params');
    return response.data;
  }

  Future<Map<String, dynamic>> getAssignment(int id) async {
    final response = await _dio.get('/assignments/$id');
    return response.data;
  }

  Future<Map<String, dynamic>> createAssignment(Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/', data: body);
    return response.data;
  }

  Future<Map<String, dynamic>> updateAssignment(int id, Map<String, dynamic> body) async {
    final response = await _dio.put('/assignments/$id', data: body);
    return response.data;
  }

  Future<void> deleteAssignment(int id) async {
    await _dio.delete('/assignments/$id');
  }

  Future<Map<String, dynamic>> submitAssignment(int assignmentId, Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/$assignmentId/submit', data: body);
    return response.data;
  }

  Future<List<dynamic>> getMySubmissions() async {
    final response = await _dio.get('/assignments/student/my-submissions');
    return response.data;
  }

  Future<List<dynamic>> getSubmissions(int assignmentId) async {
    final response = await _dio.get('/assignments/$assignmentId/submissions');
    return response.data;
  }

  Future<Map<String, dynamic>> aiGrade(int submissionId) async {
    try {
      final response = await _dio.post('/submissions/$submissionId/ai-grade');
      return response.data;
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response!.data['detail']?.toString() : null;
      throw Exception(detail ?? 'Ошибка оценки ИИ');
    }
  }

  Future<void> retractSubmission(int submissionId) async {
    await _dio.delete('/submissions/$submissionId');
  }

  Future<Map<String, dynamic>> getSubmission(int id) async {
    final response = await _dio.get('/submissions/$id');
    return response.data;
  }

  Future<Map<String, dynamic>> getMyRating({int? classId}) async {
    final params = classId != null ? '?class_id=$classId' : '';
    final response = await _dio.get('/assignments/student/my-rating$params');
    return response.data;
  }

  // ── Chats ──
  Future<List<dynamic>> getChats() async {
    final response = await _dio.get('/chats/');
    return response.data;
  }

  Future<Map<String, dynamic>> createChat(String name) async {
    final response = await _dio.post('/chats/', data: {'name': name});
    return response.data;
  }

  Future<List<dynamic>> getChatUsers(int chatId) async {
    final response = await _dio.get('/chats/$chatId/users');
    return response.data;
  }

  Future<void> addChatUser(int chatId, int userId) async {
    await _dio.post('/chats/$chatId/users/$userId');
  }

  Future<void> removeChatUser(int chatId, int userId) async {
    await _dio.delete('/chats/$chatId/users/$userId');
  }

  // ── Messages ──
  Future<List<dynamic>> getMessages(int chatId) async {
    final response = await _dio.get('/messages/chat/$chatId');
    return response.data;
  }

  Future<Map<String, dynamic>> sendMessage(int chatId, String content) async {
    final response = await _dio.post('/messages/chat/$chatId', data: {'content': content});
    return response.data;
  }

  Future<void> deleteMessage(int id) async {
    await _dio.delete('/messages/$id');
  }

  // ── AI ──
  Future<Map<String, dynamic>> aiChat(List<Map<String, dynamic>> messages, {int? classId, int maxTokens = 1500, double temperature = 0.7}) async {
    final data = <String, dynamic>{
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
    if (classId != null) data['class_id'] = classId;
    final response = await _dio.post('/ai/chat', data: data);
    return response.data;
  }

  // ── Upload ──
  Future<Map<String, dynamic>> uploadFile(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _dio.post('/upload/', data: formData);
    return response.data;
  }

  // ── Users ──
  Future<List<dynamic>> getUsers() async {
    try {
      final response = await _dio.get('/admin/users');
      return response.data;
    } catch (_) {
      try {
        final response = await _dio.get('/users/');
        return response.data;
      } catch (_) {
        return [];
      }
    }
  }

  // ── Admin ──
  Future<List<dynamic>> adminUsers() async {
    final response = await _dio.get('/admin/users');
    return response.data;
  }

  Future<Map<String, dynamic>> adminCreateUser(String email, String password, String role) async {
    final response = await _dio.post('/admin/users', data: {
      'email': email, 'password': password, 'role': role,
    });
    return response.data;
  }

  Future<void> adminSetRole(int userId, String role) async {
    await _dio.put('/admin/users/$userId/role', queryParameters: {'new_role': role});
  }

  Future<void> adminBlock(int userId) async {
    await _dio.put('/admin/users/$userId/block');
  }

  Future<void> adminUnblock(int userId) async {
    await _dio.put('/admin/users/$userId/unblock');
  }

  Future<void> adminDelete(int userId) async {
    await _dio.delete('/admin/users/$userId');
  }

  Future<List<dynamic>> adminAiUsage({int? classId}) async {
    final params = classId != null ? {'class_id': classId} : null;
    final response = await _dio.get('/admin/ai-usage', queryParameters: params);
    return response.data;
  }

  Future<List<dynamic>> adminAiSummary() async {
    final response = await _dio.get('/admin/ai-usage/summary');
    return response.data;
  }

  Future<void> adminSetAiUnlimited(int userId, bool unlimited) async {
    await _dio.put('/admin/users/$userId/ai_unlimited', data: {'unlimited': unlimited});
  }

  // ── Reactions ──
  Future<void> addReaction(int msgId, String emoji) async {
    await _dio.post('/reactions/$msgId', queryParameters: {'emoji': emoji});
  }

  Future<void> removeReaction(int msgId) async {
    await _dio.delete('/reactions/$msgId');
  }

  String get wsBaseUrl {
    return baseUrl.replaceFirst('http', 'ws');
  }
}

// VoidCallback is from Flutter SDK
