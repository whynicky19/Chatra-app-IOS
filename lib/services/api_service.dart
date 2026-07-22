import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  late final Dio _dio;
  Dio get dio => _dio;
  String? _token;
  VoidCallback? onUnauthorized;
  VoidCallback? onAccountBlocked;
  Future<String?>? _refreshing;

  // Дефолта baseUrl тут нет намеренно: иначе release без --dart-define уйдёт на localhost.
  static const _tokenKey = '_tk';
  static const _refreshKey = '_rtk';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String baseUrl;

  ApiService({required this.baseUrl}) {
    _dio = Dio(BaseOptions(
  baseUrl: baseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 15),
  headers: {
    'ngrok-skip-browser-warning': 'true',
  },
));

    _dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) {
    if (kDebugMode) {
      print('>>> REQUEST: ${options.method} ${options.baseUrl}${options.path}');
      final isAuth = options.path.startsWith('/auth/');
      print('>>> DATA: ${isAuth ? '<redacted>' : options.data}');
    }
    return handler.next(options);
  },
  onResponse: (response, handler) {
    if (kDebugMode) {
      final isAuth = response.requestOptions.path.startsWith('/auth/');
      print('>>> RESPONSE: ${response.statusCode} ${isAuth ? '<redacted>' : response.data}');
    }
    return handler.next(response);
  },
  onError: (error, handler) {
    if (kDebugMode) {
      print('>>> ERROR: ${error.type} ${error.message}');
      print('>>> ERROR RESPONSE: ${error.response?.data}');
    }
    return handler.next(error);
  },
));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_token != null && options.extra['_skipAuth'] != true) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode ?? 0;

        if (error.requestOptions.extra['_skipAuthRetry'] == true) {
          return handler.next(error);
        }

        if (status == 401 && error.requestOptions.path != '/auth/refresh') {
          final newAccess = await _refreshAccessToken();
          if (newAccess != null) {
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $newAccess';
            try {
              final response = await _dio.fetch(opts);
              return handler.resolve(response);
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          await clearToken();
          onUnauthorized?.call();
          return handler.next(error);
        }

        // Блокировка админом: без немедленного разлогина экран сыпет ошибками до истечения токена.
        if (status == 403 &&
            error.response?.data is Map &&
            error.response!.data['detail'] == 'user_inactive') {
          await clearToken();
          onAccountBlocked?.call();
          return handler.next(error);
        }

        if (status == 403 &&
            error.response?.data is Map &&
            error.response!.data['detail'] == 'email_not_verified') {
          await clearToken();
          onUnauthorized?.call();
          return handler.next(error);
        }

        final isRetryable = (error.type != DioExceptionType.badResponse || status >= 500) &&
            error.requestOptions.method == 'GET';
        final attempt = (error.requestOptions.extra['_retry'] ?? 0) as int;

        if (isRetryable && attempt < 3) {
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

  Future<String?> _refreshAccessToken() {
    return _refreshing ??= _performRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _performRefresh() async {
    final rt = await loadRefreshToken();
    if (rt == null) return null;
    try {
      final resp = await _dio.post('/auth/refresh',
          data: {'refresh_token': rt},
          options: Options(extra: {'_skipAuth': true}));
      final newAccess = resp.data['access_token'] as String;
      final newRefresh = resp.data['refresh_token'] as String?;
      await saveToken(newAccess);
      if (newRefresh != null) await saveRefreshToken(newRefresh);
      return newAccess;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadToken() async {
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
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
    await clearRefreshToken();
  }

  Future<void> saveRefreshToken(String token) async {
    try {
      await _storage.write(key: _refreshKey, value: token);
    } catch (_) {}
  }

  Future<String?> loadRefreshToken() async {
    try {
      return await _storage.read(key: _refreshKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRefreshToken() async {
    try {
      await _storage.delete(key: _refreshKey);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> login(String email, String password, {String orgType = 'university'}) async {
    final response = await _dio.post(
      '/auth/login',
      queryParameters: {'org_type': orgType},
      data: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return response.data;
  }

  Future<Map<String, dynamic>> register(String email, String password, String role,
      {String? fullName, String orgType = 'university'}) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (fullName != null) 'full_name': fullName,
      'org_type': orgType,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/auth/me');
    return response.data;
  }

  Future<Map<String, dynamic>> updateMe(String fullName) async {
    final response = await _dio.patch('/auth/me', data: {
      'full_name': fullName,
    });
    return response.data;
  }

  Future<void> registerPushToken(String token, {String? platform}) async {
    await _dio.post('/push/register', data: {
      'token': token,
      if (platform != null) 'platform': platform,
    });
  }

  // _skipAuthRetry обязателен: без него 401 на отозванном токене даёт бесконечный каскад логаутов.
  Future<void> unregisterPushToken(String token) async {
    try {
      await _dio.post('/push/unregister',
          data: {'token': token},
          options: Options(extra: {'_skipAuthRetry': true}));
    } catch (_) {}
  }

  Future<void> logoutServer() async {
    try {
      await _dio.post('/auth/logout',
          options: Options(extra: {'_skipAuthRetry': true}));
    } catch (_) {}
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final response = await _dio.post('/auth/change-password', data: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
    final access = response.data['access_token'] as String?;
    final refresh = response.data['refresh_token'] as String?;
    if (access != null) await saveToken(access);
    if (refresh != null) await saveRefreshToken(refresh);
  }

  Future<void> deleteAccount(String password) async {
    await _dio.delete('/auth/me', data: {'password': password});
  }

  Future<void> verifyEmail(String email, String code, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/verify-email',
        data: {'email': email, 'org_type': orgType, 'code': code},
        options: Options(extra: {'_skipAuth': true}));
    await _saveTokenPair(resp.data);
  }

  Future<Map<String, dynamic>> resendVerification(String email, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/resend-verification',
        data: {'email': email, 'org_type': orgType},
        options: Options(extra: {'_skipAuth': true}));
    return resp.data is Map<String, dynamic> ? resp.data : {};
  }

  Future<Map<String, dynamic>> forgotPassword(String email, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/forgot-password',
        data: {'email': email, 'org_type': orgType},
        options: Options(extra: {'_skipAuth': true}));
    return resp.data is Map<String, dynamic> ? resp.data : {};
  }

  Future<void> resetPassword(String email, String code, String newPassword,
      {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/reset-password',
        data: {'email': email, 'org_type': orgType, 'code': code, 'new_password': newPassword},
        options: Options(extra: {'_skipAuth': true}));
    await _saveTokenPair(resp.data);
  }

  Future<void> _saveTokenPair(dynamic data) async {
    final access = (data is Map) ? data['access_token'] as String? : null;
    final refresh = (data is Map) ? data['refresh_token'] as String? : null;
    if (access != null) await saveToken(access);
    if (refresh != null) await saveRefreshToken(refresh);
  }

  Future<List<dynamic>> getPosts({int page = 1, int pageSize = 100, int? classId}) async {
    final response = await _dio.get('/posts/', queryParameters: {
      'page': page,
      'page_size': pageSize,
      if (classId != null) 'class_id': classId,
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

  Future<Map<String, dynamic>> lookupClassByCode(String code) async {
    final response = await _dio.get('/classes/lookup-by-code', queryParameters: {'code': code});
    return response.data;
  }

  Future<List<dynamic>> getClassMembers(int classId, {int? cohortId}) async {
    final params = cohortId != null ? {'cohort_id': cohortId} : null;
    try {
      final response = await _dio.get('/classes/$classId/members', queryParameters: params);
      if (response.data is List) return response.data;
    } catch (_) {}
    final response = await _dio.get('/admin/classes/$classId/members', queryParameters: params);
    return response.data is List ? response.data : [];
  }

  Future<void> joinClass(int classId) async => _dio.post('/classes/$classId/join', data: {});
  Future<void> leaveClass(int classId) async => _dio.delete('/classes/$classId/leave');

  Future<String> regenerateInviteCode(int classId) async {
    final response = await _dio.post('/classes/$classId/regenerate-code', data: {});
    return (response.data?['invite_code'] ?? '').toString();
  }

  Future<List<dynamic>> getRejoinableStudents(int classId) async {
    final response = await _dio.get('/classes/$classId/rejoinable-students');
    return response.data is List ? response.data : [];
  }

  Future<void> addClassMember(int classId, int userId) async {
    await _dio.post('/classes/$classId/members', data: {'user_id': userId});
  }

  Future<Map<String, dynamic>> joinByCode(String code) async {
    final response = await _dio.post('/classes/join-by-code', data: {'code': code});
    return response.data;
  }

  Future<Map<String, dynamic>> createClass(String name,
      {String? description, String? teacher, String? period, String? coverImage}) async {
    final response = await _dio.post('/classes/', data: {
      'name': name,
      if (description != null) 'description': description,
      if (teacher != null) 'teacher': teacher,
      if (period != null) 'period': period,
      if (coverImage != null) 'cover_image': coverImage,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> updateClass(int classId,
      {String? name, String? description, String? teacher, String? coverImage}) async {
    final response = await _dio.put('/classes/$classId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (teacher != null) 'teacher': teacher,
      if (coverImage != null) 'cover_image': coverImage,
    });
    return response.data;
  }

  Future<void> deleteClass(int classId) async => _dio.delete('/classes/$classId');

  Future<List<dynamic>> getClassCohorts(int classId) async {
    final response = await _dio.get('/classes/$classId/cohorts');
    return response.data is List ? response.data : [];
  }

  Future<Map<String, dynamic>> setRotationMode(int classId, String mode) async {
    final response = await _dio.patch('/classes/$classId/rotation-mode',
        data: {'rotation_mode': mode});
    return response.data;
  }

  Future<List<dynamic>> getRolloverPreview() async {
    final response = await _dio.get('/rollover/preview');
    return response.data is List ? response.data : [];
  }

  Future<List<dynamic>> rollover(List<int> classIds,
      {required String newAcademicYear, required String newStartDate}) async {
    final response = await _dio.post('/rollover', data: {
      'class_ids': classIds,
      'new_academic_year': newAcademicYear,
      'new_start_date': newStartDate,
    });
    return response.data is List ? response.data : [];
  }

  Future<List<dynamic>> getCohortDeadlines(int cohortId) async {
    final response = await _dio.get('/cohorts/$cohortId/deadlines');
    return response.data is List ? response.data : [];
  }

  Future<Map<String, dynamic>> updateDeadline(int deadlineId,
      {String? dueDate, bool? isPublished}) async {
    final response = await _dio.patch('/deadlines/$deadlineId', data: {
      if (dueDate != null) 'due_date': dueDate,
      if (isPublished != null) 'is_published': isPublished,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> publishAllDeadlines(int cohortId) async {
    final response = await _dio.patch('/cohorts/$cohortId/deadlines/publish-all');
    return response.data is Map<String, dynamic> ? response.data : {};
  }

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

  Future<List<dynamic>> getSubmissions(int assignmentId, {int? cohortId}) async {
    final response = await _dio.get('/assignments/$assignmentId/submissions',
        queryParameters: cohortId != null ? {'cohort_id': cohortId} : null);
    return response.data;
  }

  Future<Map<String, dynamic>> aiGrade(int submissionId) async {
    try {
      final response = await _dio.post('/submissions/$submissionId/ai-grade',
          options: Options(receiveTimeout: const Duration(minutes: 2)));
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

  Future<Map<String, dynamic>> aiChat(List<Map<String, dynamic>> messages,
      {int? classId, int maxTokens = 1500, double temperature = 0.7, String? lectureContext}) async {
    final data = <String, dynamic>{
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
    if (classId != null) data['class_id'] = classId;
    if (lectureContext != null) data['lecture_context'] = lectureContext;
    final response = await _dio.post('/ai/chat', data: data,
        options: Options(receiveTimeout: const Duration(minutes: 2), sendTimeout: const Duration(seconds: 30)));
    return response.data;
  }

  /// Дневная квота сообщений ИИ: {limit, used, remaining, unlimited, resets_at}.
  Future<Map<String, dynamic>> getAiLimits() async {
    final response = await _dio.get('/ai/limits');
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> getAiHistory({int? classId}) async {
    final response = await _dio.get('/ai/history',
        queryParameters: classId != null ? {'class_id': classId} : null);
    return response.data as List<dynamic>;
  }

  Future<void> clearAiHistory({int? classId}) async {
    await _dio.delete('/ai/history',
        queryParameters: classId != null ? {'class_id': classId} : null);
  }

  Future<List<dynamic>> importAiHistory(List<Map<String, String>> messages, {int? classId}) async {
    final response = await _dio.post('/ai/history/import',
        data: {'class_id': classId, 'messages': messages});
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getNotifStates() async {
    final response = await _dio.get('/notifications/state');
    return response.data as List<dynamic>;
  }

  Future<void> setNotifState(String notifKey, {bool? read, bool? dismissed}) async {
    final data = <String, dynamic>{'notif_key': notifKey};
    if (read != null) data['read'] = read;
    if (dismissed != null) data['dismissed'] = dismissed;
    await _dio.post('/notifications/state', data: data);
  }

  Future<void> markAllNotifsRead(List<String> keys) async {
    await _dio.post('/notifications/read-all', data: {'keys': keys});
  }

  Future<Map<String, dynamic>> uploadFile(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    // Таймаут 2 мин: аплоад по мобильной сети + парсинг на сервере не влезают в дефолтные 15с.
    final response = await _dio.post(
      '/upload/',
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return response.data;
  }

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

  Future<Map<String, dynamic>> adminAiUsagePage({int? classId, int page = 1, int pageSize = 50}) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (classId != null) params['class_id'] = classId;
    final response = await _dio.get('/admin/ai-usage', queryParameters: params);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is List) return {'total': data.length, 'page': 1, 'page_size': data.length, 'items': data};
    return {'total': 0, 'page': 1, 'page_size': pageSize, 'items': []};
  }

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

  Future<Map<String, dynamic>?> getMyAvatar() async {
    try {
      final response = await _dio.get('/avatars/me');
      return response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createMyAvatar({
    String? displayName,
    required String photoUrl,
    required String voiceSampleUrl,
  }) async {
    final response = await _dio.post('/avatars/me', data: {
      if (displayName != null && displayName.isNotEmpty) 'display_name': displayName,
      'photo_url': photoUrl,
      'voice_sample_url': voiceSampleUrl,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> createAvatarLecture({
    required int classId,
    required String title,
    required String sourceFileUrl,
    String? sourceFilename,
    required int durationMinutes,
    required String style,
    String language = 'en',
    required bool autoSummary,
  }) async {
    final response = await _dio.post('/avatars/lectures', data: {
      'class_id': classId,
      'title': title,
      'source_file_url': sourceFileUrl,
      if (sourceFilename != null) 'source_filename': sourceFilename,
      'duration_minutes': durationMinutes,
      'style': style,
      'language': language,
      'auto_summary': autoSummary,
    });
    return response.data;
  }

  Future<List<dynamic>> getMyAvatarLectures() async {
    final response = await _dio.get('/avatars/lectures/mine');
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<List<dynamic>> getClassAvatarLectures(int classId) async {
    final response = await _dio.get('/avatars/lectures/class/$classId');
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<Map<String, dynamic>> getAvatarLectureFull(int id) async {
    final response = await _dio.get('/avatars/lectures/$id/full');
    return response.data;
  }

  Future<void> deleteAvatarLecture(int id) async => _dio.delete('/avatars/lectures/$id');

  Future<List<dynamic>> adminAvatars({String? status}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    final response = await _dio.get('/admin/avatars', queryParameters: params);
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<void> adminReviewAvatar(int id, {required bool approve, String? rejectionReason}) async {
    await _dio.post('/admin/avatars/$id/review', data: {
      'approve': approve,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    });
  }

  Future<void> adminDeleteAvatar(int id) async => _dio.delete('/admin/avatars/$id');

  Future<List<dynamic>> adminAvatarLectures({String? status}) async {
    final params = <String, dynamic>{};
    if (status != null) params['status'] = status;
    final response = await _dio.get('/admin/avatar-lectures', queryParameters: params);
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<void> adminReviewAvatarLecture(int id, {required bool approve, String? rejectionReason}) async {
    await _dio.post('/admin/avatar-lectures/$id/review', data: {
      'approve': approve,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    });
  }

  Future<Map<String, dynamic>> ragIngest(String filePath, String fileName, {int? classId}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      if (classId != null) 'class_id': classId,
    });
    final response = await _dio.post('/rag/ingest', data: formData);
    return response.data;
  }

  Future<List<dynamic>> ragDocuments({int? classId}) async {
    try {
      final params = <String, dynamic>{};
      if (classId != null) params['class_id'] = classId;
      final response = await _dio.get('/rag/documents', queryParameters: params);
      final data = response.data;
      if (data is List) return data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteRagDocument(int docId) async => _dio.delete('/rag/documents/$docId');

  Future<List<dynamic>> getAssignmentVariants(int assignmentId) async {
    final response = await _dio.get('/assignments/$assignmentId/variants');
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<Map<String, dynamic>> createAssignmentVariant(int assignmentId, Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/$assignmentId/variants', data: body);
    return response.data;
  }

  Future<void> deleteAssignmentVariant(int assignmentId, int variantId) async =>
      _dio.delete('/assignments/$assignmentId/variants/$variantId');

  Future<void> deleteSubmission(int submissionId) async => _dio.delete('/submissions/$submissionId');

  Future<Map<String, dynamic>> gradeSubmission(int submissionId, {
    required num score,
    String? feedback,
    List<dynamic>? criteriaScores,
  }) async {
    final response = await _dio.post('/submissions/$submissionId/grade', data: {
      'score': score,
      if (feedback != null) 'feedback': feedback,
      if (criteriaScores != null) 'criteria_scores': criteriaScores,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> getSubmissionGrade(int submissionId) async {
    final response = await _dio.get('/submissions/$submissionId/grade');
    return response.data;
  }

  Future<String> fetchFileText(String url) async {
    try {
      final response = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)));
      return response.data ?? '';
    } catch (_) {
      return '';
    }
  }

  String fixUrl(String url) {
    if (url.isEmpty) return url;
    var fixed = url
        .replaceAll(RegExp(r'https?://localhost:\d+'), baseUrl)
        .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), baseUrl);
    if (!fixed.startsWith('http') && !fixed.startsWith('ws')) {
      fixed = '$baseUrl${fixed.startsWith('/') ? '' : '/'}$fixed';
    }
    return fixed;
  }

  String fixUrlsInText(String text) {
    if (text.isEmpty) return text;
    var out = text
        .replaceAll(RegExp(r'https?://localhost:\d+'), baseUrl)
        .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), baseUrl);
    out = out.replaceAllMapped(
      RegExp(r'(^|\s)(/uploads/\S+)'),
      (m) => '${m[1]}$baseUrl${m[2]}',
    );
    return out;
  }

  String toRelativeUploadUrl(String url) {
    final m = RegExp(r'^https?://[^/]+(/.*)$').firstMatch(url);
    return m != null ? m.group(1)! : url;
  }
}
