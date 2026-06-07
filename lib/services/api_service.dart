import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  late final Dio _dio;
  Dio get dio => _dio;
  String? _token;
  VoidCallback? onUnauthorized;

  static const String defaultBaseUrl = 'http://192.168.10.6:8000';
  static const _tokenKey = '_tk';

  // Secure storage — encrypted on both Android (EncryptedSharedPreferences)
  // and iOS (Keychain). Falls back gracefully if unavailable.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

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
      onError: (error, handler) async {
        final status = error.response?.statusCode ?? 0;

        // 401 → trigger logout immediately, no retry.
        if (status == 401) {
          onUnauthorized?.call();
          return handler.next(error);
        }

        // Retry on network errors (no response) and 5xx server errors.
        final isRetryable = error.type != DioExceptionType.badResponse || status >= 500;
        final attempt = (error.requestOptions.extra['_retry'] ?? 0) as int;

        if (isRetryable && attempt < 3) {
          // Exponential backoff: 1 s, 2 s, 4 s.
          await Future.delayed(Duration(seconds: 1 << attempt));
          error.requestOptions.extra['_retry'] = attempt + 1;
          try {
            final response = await _dio.fetch(error.requestOptions);
            return handler.resolve(response);
          } on DioException catch (e) {
            return handler.next(e);
          }
        }

        return handler.next(error);
      },
    ));
  }

  void setToken(String? token) => _token = token;
  String? get token => _token;

  Future<void> loadToken() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      // Secure storage unavailable on some emulators/environments.
      _token = null;
    }
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<void> clearToken() async {
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post('/auth/login',
      data: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> register(String email, String password, String role,
      {String? fullName, String? group}) async {
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

  // ── Posts (class storage) ────────────────────────────────────────────────────
  // Pagination params are passed to the backend; ignored if it doesn't support them.

  Future<List<dynamic>> getPosts({int page = 1, int pageSize = 100}) async {
    final response = await _dio.get('/posts/', queryParameters: {
      'page': page,
      'page_size': pageSize,
    });
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
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

  // ── Classes ──────────────────────────────────────────────────────────────────

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

  Future<List<dynamic>> getClassMembers(int classId) async {
    final response = await _dio.get('/admin/classes/$classId/members');
    return response.data is List ? response.data : [];
  }

  Future<void> enrollPostClass(int postId) async => _dio.post('/posts/$postId/join');
  Future<void> leavePostClass(int postId) async => _dio.delete('/posts/$postId/leave');

  Future<void> joinClass(int classId) async => _dio.post('/classes/$classId/join', data: {});
  Future<void> leaveClass(int classId) async => _dio.delete('/classes/$classId/leave');

  Future<Map<String, dynamic>> createClass(String name, {String? description}) async {
    final response = await _dio.post('/classes/', data: {
      'name': name,
      if (description != null) 'description': description,
    });
    return response.data;
  }

  Future<void> deleteClass(int classId) async => _dio.delete('/classes/$classId');

  // ── Assignments ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> getAssignments({int? classId, int page = 1, int pageSize = 50}) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (classId != null) params['class_id'] = classId;
    final response = await _dio.get('/assignments/', queryParameters: params);
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
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

  Future<void> deleteAssignment(int id) async => _dio.delete('/assignments/$id');

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

  Future<void> retractSubmission(int submissionId) async => _dio.delete('/submissions/$submissionId');

  Future<Map<String, dynamic>> getSubmission(int id) async {
    final response = await _dio.get('/submissions/$id');
    return response.data;
  }

  Future<Map<String, dynamic>> getMyRating({int? classId}) async {
    final params = classId != null ? '?class_id=$classId' : '';
    final response = await _dio.get('/assignments/student/my-rating$params');
    return response.data;
  }

  // ── Chats ─────────────────────────────────────────────────────────────────────

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

  Future<void> addChatUser(int chatId, int userId) async => _dio.post('/chats/$chatId/users/$userId');
  Future<void> removeChatUser(int chatId, int userId) async => _dio.delete('/chats/$chatId/users/$userId');
  Future<void> deleteChat(int chatId) async => _dio.delete('/chats/$chatId');

  // ── Messages ──────────────────────────────────────────────────────────────────
  // [before]: message id cursor for older-message pagination (load before this id)
  // [limit]: max number of messages to return

  Future<List<dynamic>> getMessages(int chatId, {int? before, int limit = 50}) async {
    final params = <String, dynamic>{'limit': limit};
    if (before != null) params['before'] = before;
    final response = await _dio.get('/messages/chat/$chatId', queryParameters: params);
    return response.data;
  }

  Future<Map<String, dynamic>> sendMessage(int chatId, String content) async {
    final response = await _dio.post('/messages/chat/$chatId', data: {'content': content});
    return response.data;
  }

  Future<void> deleteMessage(int id) async => _dio.delete('/messages/$id');

  // ── AI ────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> aiChat(List<Map<String, dynamic>> messages,
      {int? classId, int maxTokens = 1500, double temperature = 0.7, String? lectureContext}) async {
    final data = <String, dynamic>{
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
    if (classId != null) data['class_id'] = classId;
    if (lectureContext != null) data['lecture_context'] = lectureContext;
    final response = await _dio.post('/ai/chat', data: data);
    return response.data;
  }

  // ── Upload ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadFile(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _dio.post('/upload/', data: formData);
    return response.data;
  }

  // ── Users ─────────────────────────────────────────────────────────────────────

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

  // ── Admin ─────────────────────────────────────────────────────────────────────

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

  Future<void> adminSetRole(int userId, String role) async =>
      _dio.put('/admin/users/$userId/role', queryParameters: {'new_role': role});

  Future<void> adminBlock(int userId) async => _dio.put('/admin/users/$userId/block');
  Future<void> adminUnblock(int userId) async => _dio.put('/admin/users/$userId/unblock');
  Future<void> adminDelete(int userId) async => _dio.delete('/admin/users/$userId');

  Future<List<dynamic>> adminAiUsage({int? classId}) async {
    final params = <String, dynamic>{'page_size': 200};
    if (classId != null) params['class_id'] = classId;
    final response = await _dio.get('/admin/ai-usage', queryParameters: params);
    final data = response.data;
    if (data is Map && data['items'] is List) return List<dynamic>.from(data['items'] as List);
    return data is List ? data : [];
  }

  Future<List<dynamic>> adminAiSummary() async {
    final response = await _dio.get('/admin/ai-usage/summary');
    return response.data;
  }

  Future<void> adminSetAiUnlimited(int userId, bool unlimited) async =>
      _dio.put('/admin/users/$userId/ai_unlimited', data: {'unlimited': unlimited});

  // ── Reactions ─────────────────────────────────────────────────────────────────

  Future<void> addReaction(int msgId, String emoji) async =>
      _dio.post('/reactions/$msgId', queryParameters: {'emoji': emoji});

  Future<void> removeReaction(int msgId) async => _dio.delete('/reactions/$msgId');

  // ── Files ─────────────────────────────────────────────────────────────────────

  Future<String> fetchFileText(String url) async {
    try {
      final response = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)));
      return response.data ?? '';
    } catch (_) {
      return '';
    }
  }

  String get wsBaseUrl => baseUrl.replaceFirst('http', 'ws');
}
