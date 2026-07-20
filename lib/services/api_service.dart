import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  late final Dio _dio;
  Dio get dio => _dio;
  String? _token;
  VoidCallback? onUnauthorized;
  // Аккаунт заблокирован админом (is_active=false → 403 user_inactive):
  // клиент должен разлогинить с понятным сообщением, а не «ломаться» молча.
  VoidCallback? onAccountBlocked;
  // Shared in-flight refresh: while non-null, concurrent 401s await this instead
  // of each firing their own /auth/refresh (which would race and invalidate tokens).
  Future<String?>? _refreshing;

  // Адрес бэкенда задаётся только в main.dart (_resolveBaseUrl) — здесь дефолта
  // нет намеренно, иначе release-сборка без --dart-define молча ушла бы
  // на localhost вместо экрана ошибки конфигурации.
  static const _tokenKey = '_tk';
  static const _refreshKey = '_rtk';

  // Secure storage — encrypted on both Android (EncryptedSharedPreferences)
  // and iOS (Keychain). Falls back gracefully if unavailable.
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
      // Never log credentials: mask the body for auth endpoints (login/register
      // carry the plaintext password) and never print the Authorization header.
      final isAuth = options.path.startsWith('/auth/');
      print('>>> DATA: ${isAuth ? '<redacted>' : options.data}');
    }
    return handler.next(options);
  },
  onResponse: (response, handler) {
    if (kDebugMode) {
      // Auth responses carry access/refresh tokens — keep them out of the log.
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

        // Запросы самого logout (logoutServer, unregister push-токена) не должны
        // запускать refresh/onUnauthorized: при отозванном токене они сами дают
        // 401, а onUnauthorized → logout → снова эти запросы = бесконечный цикл.
        if (error.requestOptions.extra['_skipAuthRetry'] == true) {
          return handler.next(error);
        }

        if (status == 401 && error.requestOptions.path != '/auth/refresh') {
          // Deduplicate concurrent refreshes: the first 401 kicks off the
          // /auth/refresh call, every other in-flight 401 awaits the same Future.
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

        // Аккаунт заблокирован админом в активной сессии: бэкенд отдаёт 403 с
        // detail='user_inactive'. Немедленно разлогиниваем — иначе экран сыпет
        // ошибками без объяснения, пока не истечёт access-токен.
        if (status == 403 &&
            error.response?.data is Map &&
            error.response!.data['detail'] == 'user_inactive') {
          await clearToken();
          onAccountBlocked?.call();
          return handler.next(error);
        }

        // Неподтверждённый email по сохранённому токену — тихо разлогиниваем,
        // чтобы юзер вернулся на вход и прошёл верификацию (login → экран кода).
        if (status == 403 &&
            error.response?.data is Map &&
            error.response!.data['detail'] == 'email_not_verified') {
          await clearToken();
          onUnauthorized?.call();
          return handler.next(error);
        }

        // Retry on network errors (no response) and 5xx server errors.
        // Only for GET: retrying POST/PUT/DELETE risks duplicating non-idempotent
        // requests (sendMessage, createPost, submitAssignment, etc.).
        final isRetryable = (error.type != DioExceptionType.badResponse || status >= 500) &&
            error.requestOptions.method == 'GET';
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

  /// Returns a fresh access token, refreshing at most once even when many
  /// requests hit 401 at the same time. Returns null if refresh is impossible
  /// (no refresh token) or fails.
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

  // ── Auth ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> login(String email, String password, {String orgType = 'university'}) async {
    final response = await _dio.post(
      '/auth/login',
      queryParameters: {'org_type': orgType},
      data: 'username=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}',
      options: Options(contentType: 'application/x-www-form-urlencoded'),
    );
    return response.data;
  }

  // role больше не отправляется: бэкенд всегда регистрирует student.
  // Параметр оставлен, чтобы не менять сигнатуру у вызывающих.
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

  /// Регистрирует FCM-токен устройства для push-уведомлений (best-effort).
  Future<void> registerPushToken(String token, {String? platform}) async {
    await _dio.post('/push/register', data: {
      'token': token,
      if (platform != null) 'platform': platform,
    });
  }

  /// Удаляет FCM-токен на сервере (при выходе). Ошибку глотаем. _skipAuthRetry —
  /// чтобы 401 (например при уже отозванном токене) не запускал разлогин-каскад.
  Future<void> unregisterPushToken(String token) async {
    try {
      await _dio.post('/push/unregister',
          data: {'token': token},
          options: Options(extra: {'_skipAuthRetry': true}));
    } catch (_) {}
  }

  /// Best-effort серверный отзыв токенов. Ошибку глотаем — локальный logout
  /// (очистка secure storage) выполняется в любом случае.
  Future<void> logoutServer() async {
    try {
      await _dio.post('/auth/logout',
          options: Options(extra: {'_skipAuthRetry': true}));
    } catch (_) {}
  }

  /// Меняет пароль и сохраняет новую пару токенов (старые сессии сервер отзывает).
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

  /// Удаляет собственный аккаунт (подтверждение паролем).
  Future<void> deleteAccount(String password) async {
    await _dio.delete('/auth/me', data: {'password': password});
  }

  // ── Верификация email / восстановление пароля (OTP-код) ──────────────────────

  /// Подтверждает email кодом и сохраняет выданную пару токенов (авто-вход).
  Future<void> verifyEmail(String email, String code, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/verify-email',
        data: {'email': email, 'org_type': orgType, 'code': code},
        options: Options(extra: {'_skipAuth': true}));
    await _saveTokenPair(resp.data);
  }

  /// Повторно шлёт код подтверждения. Возвращает тело ответа ({sent, dev_code?}).
  Future<Map<String, dynamic>> resendVerification(String email, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/resend-verification',
        data: {'email': email, 'org_type': orgType},
        options: Options(extra: {'_skipAuth': true}));
    return resp.data is Map<String, dynamic> ? resp.data : {};
  }

  /// Запрашивает код сброса пароля. Возвращает тело ответа ({sent, dev_code?}).
  Future<Map<String, dynamic>> forgotPassword(String email, {String orgType = 'university'}) async {
    final resp = await _dio.post('/auth/forgot-password',
        data: {'email': email, 'org_type': orgType},
        options: Options(extra: {'_skipAuth': true}));
    return resp.data is Map<String, dynamic> ? resp.data : {};
  }

  /// Сбрасывает пароль по коду и сохраняет выданную пару токенов (авто-вход).
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

  // ── Posts (class storage) ────────────────────────────────────────────────────
  // Pagination params are passed to the backend; ignored if it doesn't support them.

  Future<List<dynamic>> getPosts({int page = 1, int pageSize = 100, int? classId}) async {
    final response = await _dio.get('/posts/', queryParameters: {
      'page': page,
      'page_size': pageSize,
      // Server-side filter: only this class's [LECTURE]/[HW] posts instead of
      // every post in the organization.
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

  /// Read-only existence check for a join code — does NOT join. Throws (404)
  /// if no class in the user's org has this code.
  Future<Map<String, dynamic>> lookupClassByCode(String code) async {
    final response = await _dio.get('/classes/lookup-by-code', queryParameters: {'code': code});
    return response.data;
  }

  /// Mirrors the site: try the teacher-facing endpoint first (works without
  /// admin rights), fall back to the admin one only if that fails.
  /// [cohortId] filters to a specific academic-year cohort (teacher viewing past
  /// years). Omit it for the active cohort — keeps the existing behaviour intact.
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

  // Перегенерация инвайт-кода класса (владелец/админ). Старый код перестаёт
  // работать, возвращается новый.
  Future<String> regenerateInviteCode(int classId) async {
    final response = await _dio.post('/classes/$classId/regenerate-code', data: {});
    return (response.data?['invite_code'] ?? '').toString();
  }

  // Студенты из архивных потоков класса, которых можно вернуть в активный поток
  // (для админа/владельца). Возврат — addClassMember.
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

  // ── Cohorts / Rollover (teacher-owner only) ────────────────────────────────────

  /// All cohorts (academic years) of a class, newest first. Owner/admin only.
  Future<List<dynamic>> getClassCohorts(int classId) async {
    final response = await _dio.get('/classes/$classId/cohorts');
    return response.data is List ? response.data : [];
  }

  /// Toggle a class between 'manual' and 'yearly' rotation. Returns the updated class.
  Future<Map<String, dynamic>> setRotationMode(int classId, String mode) async {
    final response = await _dio.patch('/classes/$classId/rotation-mode',
        data: {'rotation_mode': mode});
    return response.data;
  }

  /// Classes eligible for year rollover (rotation_mode='yearly' + active cohort).
  Future<List<dynamic>> getRolloverPreview() async {
    final response = await _dio.get('/rollover/preview');
    return response.data is List ? response.data : [];
  }

  /// Roll the given classes into a new academic year. [newStartDate] is 'YYYY-MM-DD',
  /// [newAcademicYear] must match 'YYYY/YYYY'. Returns per-class result items.
  Future<List<dynamic>> rollover(List<int> classIds,
      {required String newAcademicYear, required String newStartDate}) async {
    final response = await _dio.post('/rollover', data: {
      'class_ids': classIds,
      'new_academic_year': newAcademicYear,
      'new_start_date': newStartDate,
    });
    return response.data is List ? response.data : [];
  }

  /// Deadlines of a cohort (post-rollover drafts included). Owner only.
  Future<List<dynamic>> getCohortDeadlines(int cohortId) async {
    final response = await _dio.get('/cohorts/$cohortId/deadlines');
    return response.data is List ? response.data : [];
  }

  /// Edit a single deadline's date and/or publish state. [dueDate] is ISO-8601.
  Future<Map<String, dynamic>> updateDeadline(int deadlineId,
      {String? dueDate, bool? isPublished}) async {
    final response = await _dio.patch('/deadlines/$deadlineId', data: {
      if (dueDate != null) 'due_date': dueDate,
      if (isPublished != null) 'is_published': isPublished,
    });
    return response.data;
  }

  /// Publish all draft deadlines of a cohort at once. Returns {'published': n}.
  Future<Map<String, dynamic>> publishAllDeadlines(int cohortId) async {
    final response = await _dio.patch('/cohorts/$cohortId/deadlines/publish-all');
    return response.data is Map<String, dynamic> ? response.data : {};
  }

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

  /// [cohortId] filters submissions to a past cohort (teacher viewing prior
  /// years). Omit it for the active cohort.
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

  // ── UGC moderation ──────────────────────────────────────────────────────────
  // Жалоба на пользователя/сообщение уходит на сервер (таблица reports), где её
  // видит админ. Guideline 1.2 — жалоба должна доходить до модератора.
  Future<void> createReport({
    required int reportedUserId,
    required String reason,
    String? content,
    int? messageId,
  }) async {
    await _dio.post('/reports', data: {
      'reported_user_id': reportedUserId,
      'reason': reason,
      if (content != null && content.isNotEmpty) 'content': content,
      if (messageId != null) 'message_id': messageId,
    });
  }

  // Блок-лист — серверная истина (таблица user_blocks): переживает
  // переустановку и синхронизируется между устройствами.
  // Возвращает [{user_id, name}, ...].
  Future<List<dynamic>> getBlocks() async {
    final response = await _dio.get('/blocks');
    return response.data;
  }

  Future<void> blockUser(int userId) async => _dio.post('/blocks/$userId');

  Future<void> unblockUserApi(int userId) async => _dio.delete('/blocks/$userId');

  // Админ: список жалоб (по умолчанию открытые) и пометка обработанной.
  Future<List<dynamic>> getReports({String? status}) async {
    final response = await _dio.get('/reports',
        queryParameters: status != null ? {'status': status} : null);
    return response.data;
  }

  Future<void> resolveReport(int reportId) async =>
      _dio.put('/reports/$reportId/resolve');

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
    final response = await _dio.post('/ai/chat', data: data,
        options: Options(receiveTimeout: const Duration(minutes: 2), sendTimeout: const Duration(seconds: 30)));
    return response.data;
  }

  // История чатов с ИИ хранится на сервере (синхронизация между устройствами).
  // classId == null — глобальный ИИ-экран; иначе — ИИ-вкладка класса.
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

  // Состояние уведомлений (прочитано/скрыто) — серверная истина.
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

  // ── Upload ────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadFile(String filePath, String fileName) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    // AP-4: аплоад большого файла по мобильной сети + серверный парсинг
    // (OCR/pdf) легко перешагивают дефолтные 15с — ставим 2 мин на отправку и
    // приём, иначе клиент показывает ложную ошибку, хотя файл уже принят.
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

  /// Returns the raw paginated envelope ({total, page, page_size, items}) so
  /// callers can drive "load more" pagination like the site does.
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

  // ── Teacher AI Avatar ────────────────────────────────────────────────────────

  /// Returns the teacher's avatar, or null if none exists yet (backend may
  /// respond with either a null body or a 404 — both mean "no avatar").
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

  // ── Avatar lectures ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createAvatarLecture({
    required int classId,
    required String title,
    required String sourceFileUrl,
    String? sourceFilename,
    required int durationMinutes,
    required String style,
    // Обучение в организации идёт строго на английском — язык не выбирается.
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

  // ── Admin: avatar moderation ─────────────────────────────────────────────────

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

  // ── RAG documents (AI knowledge base) ────────────────────────────────────────

  Future<Map<String, dynamic>> ragIngest(String filePath, String fileName, {int? classId}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      if (classId != null) 'class_id': classId,
    });
    final response = await _dio.post('/rag/ingest', data: formData);
    return response.data;
  }

  /// Returns an empty list on error, matching the site's behavior.
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

  // ── Assignment variants ──────────────────────────────────────────────────────

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

  // ── Submissions (grading) ────────────────────────────────────────────────────

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

  // ── Reactions ─────────────────────────────────────────────────────────────────

  Future<void> addReaction(int msgId, String emoji) async =>
      _dio.post('/reactions/$msgId', queryParameters: {'emoji': emoji});

  Future<void> removeReaction(int msgId) async => _dio.delete('/reactions/$msgId');

  /// List of reactions on a message. Not currently used in the UI (reactions
  /// are read from the message payload), kept for future use/parity with site.
  Future<List<dynamic>> getReactions(int msgId) async {
    final response = await _dio.get('/reactions/$msgId');
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

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

  /// То же, что [fixUrl], но для произвольного ТЕКСТА со ссылками внутри
  /// (содержимое сообщения, тело поста).
  ///
  /// Бэкенд строит ссылки на файлы из APP_BASE_URL, который по умолчанию равен
  /// http://localhost:8000 — такой адрес сохраняется в сообщении и на телефоне
  /// не открывается. Плюс сюда же подставляем baseUrl относительным путям
  /// (/uploads/...), которые клиент теперь отправляет вместо абсолютных.
  String fixUrlsInText(String text) {
    if (text.isEmpty) return text;
    var out = text
        .replaceAll(RegExp(r'https?://localhost:\d+'), baseUrl)
        .replaceAll(RegExp(r'https?://127\.0\.0\.1:\d+'), baseUrl);
    // Относительный /uploads/... в начале строки или после пробела.
    out = out.replaceAllMapped(
      RegExp(r'(^|\s)(/uploads/\S+)'),
      (m) => '${m[1]}$baseUrl${m[2]}',
    );
    return out;
  }

  /// Обратная операция: убрать origin, чтобы в БД лёг переносимый путь.
  /// Абсолютный адрес привязан к машине, где крутился сервер, и ломается на
  /// другом устройстве или после смены домена.
  String toRelativeUploadUrl(String url) {
    final m = RegExp(r'^https?://[^/]+(/.*)$').firstMatch(url);
    return m != null ? m.group(1)! : url;
  }

  String get wsBaseUrl => baseUrl.replaceFirst('http', 'ws');
}
