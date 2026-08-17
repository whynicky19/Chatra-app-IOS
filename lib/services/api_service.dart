import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_thread.dart';

final _localhostRe = RegExp(r'https?://localhost:\d+');
final _loopbackRe = RegExp(r'https?://127\.0\.0\.1:\d+');
final _relUploadsRe = RegExp(r'(^|\s)(/uploads/\S+)');
final _absUrlPathRe = RegExp(r'^https?://[^/]+(/.*)$');

/// Обрезанное представление тела запроса/ответа для отладочного лога.
String _short(Object? data) {
  if (data == null) return 'null';
  final text = data.toString();
  return text.length <= 500 ? text : '${text.substring(0, 500)}… (${text.length} символов)';
}

class ApiService {
  late final Dio _dio;
  Dio get dio => _dio;

  /// Клиент БЕЗ интерцептора авторизации — для скачивания файлов по абсолютным
  /// URL, которые указывают на чужой хост (R2/CDN, подписанные ссылки).
  /// Через него Bearer-токен физически не может уйти третьей стороне.
  late final Dio _plainDio;
  Dio get downloadClient => _plainDio;

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

  /// Хост собственного API. Токен добавляется ТОЛЬКО к запросам на него.
  late final String _apiHost = Uri.parse(baseUrl).host;

  /// Запрос идёт на наш бэкенд? Относительные пути (host пуст до склейки с
  /// baseUrl) считаем своими; абсолютные — сверяем по хосту.
  bool _isOwnHost(RequestOptions options) {
    final host = options.uri.host;
    return host.isEmpty || host == _apiHost;
  }

  bool isOwnHostUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty || host == _apiHost;
  }

  ApiService({required this.baseUrl}) {
    _dio = Dio(BaseOptions(
  baseUrl: baseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 15),
  headers: {
    'ngrok-skip-browser-warning': 'true',
  },
));

    _plainDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
  onRequest: (options, handler) {
    if (kDebugMode) {
      print('>>> REQUEST: ${options.method} ${options.baseUrl}${options.path}');
      final isAuth = options.path.startsWith('/auth/');
      print('>>> DATA: ${isAuth ? '<redacted>' : _short(options.data)}');
    }
    return handler.next(options);
  },
  onResponse: (response, handler) {
    if (kDebugMode) {
      final isAuth = response.requestOptions.path.startsWith('/auth/');
      print('>>> RESPONSE: ${response.statusCode} ${isAuth ? '<redacted>' : _short(response.data)}');
    }
    return handler.next(response);
  },
  onError: (error, handler) {
    if (kDebugMode) {
      print('>>> ERROR: ${error.type} ${error.message}');
      print('>>> ERROR RESPONSE: ${_short(error.response?.data)}');
    }
    return handler.next(error);
  },
));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        // Токен уходит ТОЛЬКО на собственный хост. Абсолютные URL файлов
        // указывают на R2/CDN — туда Authorization отправлять нельзя, иначе
        // access-токен утекает третьей стороне (она логирует заголовки).
        if (_token != null &&
            options.extra['_skipAuth'] != true &&
            _isOwnHost(options)) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        final status = error.response?.statusCode ?? 0;

        if (error.requestOptions.extra['_skipAuthRetry'] == true) {
          return handler.next(error);
        }

        // _authRetried не даёт зациклиться: сервер, который отдаёт 401 даже на
        // свежий токен, иначе уводит клиент в бесконечный refresh → retry → 401.
        if (status == 401 &&
            error.requestOptions.path != '/auth/refresh' &&
            error.requestOptions.extra['_authRetried'] != true) {
          final newAccess = await _refreshAccessToken();
          if (newAccess != null) {
            final opts = error.requestOptions;
            opts.extra['_authRetried'] = true;
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

  /// Безопасное приведение тела ответа к списку: голое `as List` роняет
  /// приложение, когда прокси вместо JSON отдаёт HTML-страницу ошибки.
  static List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }

  /// То же для объектов.
  static Map<String, dynamic> _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

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
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> register(String email, String password, String role,
      {String? fullName, String orgType = 'university'}) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      if (fullName != null) 'full_name': fullName,
      'org_type': orgType,
    });
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/auth/me');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updateMe(String fullName) async {
    final response = await _dio.patch('/auth/me', data: {
      'full_name': fullName,
    });
    return _asMap(response.data);
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
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updatePost(int id, String title, String body) async {
    final response = await _dio.put('/posts/$id', data: {'title': title, 'body': body});
    return _asMap(response.data);
  }

  Future<void> deletePost(int id) async {
    await _dio.delete('/posts/$id');
  }

  Future<List<dynamic>> getClasses() async =>
      _asList((await _dio.get('/classes/')).data);

  Future<List<dynamic>> getAllClasses() async =>
      _asList((await _dio.get('/classes/all')).data);

  Future<Map<String, dynamic>> getClass(int id) async {
    final response = await _dio.get('/classes/$id');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> lookupClassByCode(String code) async {
    final response = await _dio.get('/classes/lookup-by-code', queryParameters: {'code': code});
    return _asMap(response.data);
  }

  /// [isAdmin] — пробовать ли админский фолбэк. Студенту он всегда вернёт 403:
  /// это лишний round-trip и шум в логах/Crashlytics на каждом открытии класса.
  Future<List<dynamic>> getClassMembers(int classId,
      {int? cohortId, bool isAdmin = false}) async {
    final params = cohortId != null ? {'cohort_id': cohortId} : null;
    try {
      return _asList((await _dio.get('/classes/$classId/members', queryParameters: params)).data);
    } catch (_) {
      if (!isAdmin) rethrow;
    }
    return _asList(
        (await _dio.get('/admin/classes/$classId/members', queryParameters: params)).data);
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
    return _asMap(response.data);
  }

  /// Обложка собирается сервером по паре «цвет + иконка»; AI-версию клиент
  /// запрашивает следующим шагом через [generateClassCover].
  Future<Map<String, dynamic>> createClass(String name,
      {String? description,
      String? teacher,
      String? period,
      String? coverColor,
      String? coverIcon}) async {
    final response = await _dio.post('/classes/', data: {
      'name': name,
      if (description != null) 'description': description,
      if (teacher != null) 'teacher': teacher,
      if (period != null) 'period': period,
      if (coverColor != null) 'cover_color': coverColor,
      if (coverIcon != null) 'cover_icon': coverIcon,
    });
    return _asMap(response.data);
  }

  /// Смена цвета/иконки без генерации перерисовывает обложку локальным
  /// фолбэком на бэкенде — мгновенно и бесплатно.
  Future<Map<String, dynamic>> updateClass(int classId,
      {String? name,
      String? description,
      String? teacher,
      String? coverColor,
      String? coverIcon}) async {
    final response = await _dio.put('/classes/$classId', data: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (teacher != null) 'teacher': teacher,
      if (coverColor != null) 'cover_color': coverColor,
      if (coverIcon != null) 'cover_icon': coverIcon,
    });
    return _asMap(response.data);
  }

  /// Палитра и набор предметных иконок для пикеров оформления. Отдаётся
  /// бэкендом, чтобы набор в приложении, на сайте и в рендере обложки был один.
  Future<Map<String, dynamic>> getCoverOptions() async {
    final response = await _dio.get('/classes/cover/options');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> generateClassCover(int classId,
      {String? color, String? icon}) async {
    final response = await _dio.post('/classes/$classId/cover/generate', data: {
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
    });
    return _asMap(response.data);
  }

  Future<void> deleteClass(int classId) async => _dio.delete('/classes/$classId');

  Future<List<dynamic>> getClassCohorts(int classId) async {
    final response = await _dio.get('/classes/$classId/cohorts');
    return response.data is List ? response.data : [];
  }

  Future<Map<String, dynamic>> setRotationMode(int classId, String mode) async {
    final response = await _dio.patch('/classes/$classId/rotation-mode',
        data: {'rotation_mode': mode});
    return _asMap(response.data);
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
    return _asMap(response.data);
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
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> createAssignment(Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/', data: body);
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> updateAssignment(int id, Map<String, dynamic> body) async {
    final response = await _dio.put('/assignments/$id', data: body);
    return _asMap(response.data);
  }

  Future<void> deleteAssignment(int id) async => _dio.delete('/assignments/$id');

  Future<Map<String, dynamic>> submitAssignment(int assignmentId, Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/$assignmentId/submit', data: body);
    return _asMap(response.data);
  }

  Future<List<dynamic>> getMySubmissions() async =>
      _asList((await _dio.get('/assignments/student/my-submissions')).data);

  Future<List<dynamic>> getSubmissions(int assignmentId, {int? cohortId}) async {
    final response = await _dio.get('/assignments/$assignmentId/submissions',
        queryParameters: cohortId != null ? {'cohort_id': cohortId} : null);
    return _asList(response.data);
  }

  Future<Map<String, dynamic>> aiGrade(int submissionId) async {
    try {
      final response = await _dio.post('/submissions/$submissionId/ai-grade',
          options: Options(receiveTimeout: const Duration(minutes: 2)));
      return _asMap(response.data);
    } on DioException catch (e) {
      final detail = (e.response?.data is Map) ? e.response!.data['detail']?.toString() : null;
      throw Exception(detail ?? 'Ошибка оценки ИИ');
    }
  }

  Future<void> retractSubmission(int submissionId) async => _dio.delete('/submissions/$submissionId');

  Future<Map<String, dynamic>> getSubmission(int id) async {
    final response = await _dio.get('/submissions/$id');
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getMyRating({int? classId}) async {
    final params = classId != null ? '?class_id=$classId' : '';
    final response = await _dio.get('/assignments/student/my-rating$params');
    return _asMap(response.data);
  }

  // ── ИИ-треды (мульти-чат главного ассистента) ──────────────────────────
  Future<List<AiThread>> getAiThreads() async {
    final response = await _dio.get('/ai/threads');
    return _asList(response.data)
        .map((e) => AiThread.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<AiThread> createAiThread() async {
    final response = await _dio.post('/ai/threads');
    return AiThread.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<AiThread> renameAiThread(int id, String title) async {
    final response = await _dio.patch('/ai/threads/$id', data: {'title': title});
    return AiThread.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<AiThread> pinAiThread(int id, bool pinned) async {
    final response = await _dio.patch('/ai/threads/$id', data: {'pinned': pinned});
    return AiThread.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> deleteAiThread(int id) async {
    await _dio.delete('/ai/threads/$id');
  }

  Future<Map<String, dynamic>> aiChat(List<Map<String, dynamic>> messages,
      {int? classId, int? threadId, int maxTokens = 1500, double temperature = 0.7,
      CancelToken? cancelToken, String? requestId,
      int? annotationId, int? lectureId, int? lecturePage, String? quote}) async {
    final data = <String, dynamic>{
      'messages': messages,
      'max_tokens': maxTokens,
      'temperature': temperature,
    };
    if (classId != null) data['class_id'] = classId;
    if (threadId != null) data['thread_id'] = threadId;
    if (requestId != null) data['request_id'] = requestId;
    // Вопрос по выделенному фрагменту лекции: сервер по этим полям добавляет
    // в контекст источник (лекция + страница), тексту сообщения он не доверяет.
    if (annotationId != null) data['annotation_id'] = annotationId;
    if (lectureId != null) data['lecture_id'] = lectureId;
    if (lecturePage != null && lecturePage > 0) data['lecture_page'] = lecturePage;
    if (quote != null && quote.isNotEmpty) data['quote'] = quote;
    final response = await _dio.post('/ai/chat', data: data,
        cancelToken: cancelToken,
        options: Options(receiveTimeout: const Duration(minutes: 2), sendTimeout: const Duration(seconds: 30)));
    return _asMap(response.data);
  }

  /// Сообщает бэкенду, что ответ больше не нужен: `CancelToken` рвёт только
  /// клиентское соединение, и сервер иначе сохранил бы отменённый ответ.
  /// Шлём без cancelToken, иначе отмена отменила бы сама себя.
  Future<void> cancelAiChat(String requestId) async {
    try {
      await _dio.post('/ai/chat/cancel', data: {'request_id': requestId});
    } catch (_) {}
  }

  /// Дневная квота сообщений ИИ: {limit, used, remaining, unlimited, resets_at}.
  Future<Map<String, dynamic>> getAiLimits() async {
    final response = await _dio.get('/ai/limits');
    return _asMap(response.data);
  }

  Future<List<dynamic>> getAiHistory({int? classId, int? threadId}) async {
    final params = <String, dynamic>{};
    if (classId != null) params['class_id'] = classId;
    if (threadId != null) params['thread_id'] = threadId;
    final response = await _dio.get('/ai/history',
        queryParameters: params.isEmpty ? null : params);
    return _asList(response.data);
  }

  Future<void> clearAiHistory({int? classId, int? threadId}) async {
    final params = <String, dynamic>{};
    if (classId != null) params['class_id'] = classId;
    if (threadId != null) params['thread_id'] = threadId;
    await _dio.delete('/ai/history',
        queryParameters: params.isEmpty ? null : params);
  }

  Future<List<dynamic>> importAiHistory(List<Map<String, String>> messages,
      {int? classId, int? threadId}) async {
    final response = await _dio.post('/ai/history/import',
        data: {'class_id': classId, 'thread_id': threadId, 'messages': messages});
    return _asList(response.data);
  }

  /// PDF-версия office-файла (.ppt/.pptx/.doc/.docx/.rtf) — конвертирует
  /// бэкенд (LibreOffice) и кэширует, чтобы материал открывался во встроенном
  /// просмотрщике с выделениями, а не системным вьюером.
  Future<Map<String, dynamic>> previewPdf(String url) async {
    final response = await _dio.get('/upload/utils/preview-pdf',
        queryParameters: {'url': url});
    return _asMap(response.data);
  }

  // ── Выделения и заметки к лекциям ─────────────────────────────────────
  // Серверная истина, общая с сайтом: пометка с телефона видна в вебе и наоборот.

  Future<List<dynamic>> getAnnotations({int? lectureId, int? classId}) async {
    final params = <String, dynamic>{};
    if (lectureId != null) params['lecture_id'] = lectureId;
    if (classId != null) params['class_id'] = classId;
    final response = await _dio.get('/annotations',
        queryParameters: params.isEmpty ? null : params);
    return _asList(response.data);
  }

  Future<Map<String, dynamic>> createAnnotation({
    required int lectureId,
    required int classId,
    required String selectedText,
    required int startOffset,
    required int endOffset,
    String prefix = '',
    String suffix = '',
    int fileIndex = -1,
    int page = 0,
    String color = 'yellow',
    String? comment,
  }) async {
    final response = await _dio.post('/annotations', data: {
      'lecture_id': lectureId,
      'class_id': classId,
      'file_index': fileIndex,
      'page': page,
      'selected_text': selectedText,
      'prefix': prefix,
      'suffix': suffix,
      'start_offset': startOffset,
      'end_offset': endOffset,
      'color': color,
      'comment': comment,
    });
    return _asMap(response.data);
  }

  /// Меняются только цвет и заметка: положение — свойство самого выделения.
  Future<Map<String, dynamic>> updateAnnotation(int id, {String? color, String? comment}) async {
    final data = <String, dynamic>{};
    if (color != null) data['color'] = color;
    if (comment != null) data['comment'] = comment;
    final response = await _dio.patch('/annotations/$id', data: data);
    return _asMap(response.data);
  }

  Future<void> deleteAnnotation(int id) async => _dio.delete('/annotations/$id');

  // ── Модерация UGC (App Store Guideline 1.2 и политика Google Play) ─────

  /// [targetType]: post | assignment | submission | ai_message | user
  Future<void> reportContent({
    required String targetType,
    required int targetId,
    required String reason,
    String? comment,
  }) async {
    await _dio.post('/reports', data: {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
  }

  /// Очередь модерации (только админ).
  Future<List<dynamic>> adminReports({bool onlyOpen = true}) async => _asList(
      (await _dio.get('/admin/reports', queryParameters: {'open': onlyOpen})).data);

  Future<void> adminResolveReport(int reportId, {String? action}) async {
    await _dio.post('/admin/reports/$reportId/resolve',
        data: {if (action != null) 'action': action});
  }

  /// Удалить контент, на который пожаловались (лекция/пост или задание),
  /// и закрыть жалобу.
  Future<void> adminDeleteReportContent(int reportId) async =>
      _dio.post('/admin/reports/$reportId/delete-content');


  Future<List<dynamic>> getNotifStates() async =>
      _asList((await _dio.get('/notifications/state')).data);

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
    return _asMap(response.data);
  }

  Future<List<dynamic>> getUsers() async {
    try {
      return _asList((await _dio.get('/admin/users')).data);
    } catch (_) {
      try {
        return _asList((await _dio.get('/users/')).data);
      } catch (_) {
        return const [];
      }
    }
  }

  Future<List<dynamic>> adminUsers() async =>
      _asList((await _dio.get('/admin/users')).data);

  Future<Map<String, dynamic>> adminCreateUser(String email, String password, String role) async {
    final response = await _dio.post('/admin/users', data: {
      'email': email, 'password': password, 'role': role,
    });
    return _asMap(response.data);
  }

  Future<void> adminSetRole(int userId, String role) async =>
      _dio.put('/admin/users/$userId/role', queryParameters: {'new_role': role});

  Future<void> adminBlock(int userId) async => _dio.put('/admin/users/$userId/block');
  Future<void> adminUnblock(int userId) async => _dio.put('/admin/users/$userId/unblock');
  Future<void> adminDelete(int userId) async => _dio.delete('/admin/users/$userId');

  /// Список пользователей с агрегатами (расход токенов, число предметов,
  /// последнее действие) — одна строка списка админки без запроса на каждого.
  Future<List<dynamic>> adminUsersOverview() async =>
      _asList((await _dio.get('/admin/users/overview')).data);

  /// Карточка пользователя целиком: профиль, расход ИИ по видам, квота,
  /// предметы и учебная активность.
  Future<Map<String, dynamic>> adminUserDetail(int userId) async =>
      _asMap((await _dio.get('/admin/users/$userId')).data);

  /// Карточка предмета: состав с расходом, потоки, содержимое, расход ИИ.
  Future<Map<String, dynamic>> adminClassDetail(int classId) async =>
      _asMap((await _dio.get('/admin/classes/$classId')).data);

  /// Дашборд расхода ИИ за период: итоги, разбивка по видам, классам, дням и
  /// пользователям одним запросом.
  Future<Map<String, dynamic>> adminAiDashboard({int days = 30}) async =>
      _asMap((await _dio.get('/admin/ai-usage/dashboard',
              queryParameters: {'days': days}))
          .data);

  /// [endpoint] — вид расхода; можно перечислить несколько через запятую
  /// (чат = chat,chat_vision). [classId] = 0 — расход вне предметов.
  Future<Map<String, dynamic>> adminAiUsagePage({
    int? classId,
    String? endpoint,
    int? userId,
    int? days,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String, dynamic>{'page': page, 'page_size': pageSize};
    if (classId != null) params['class_id'] = classId;
    if (endpoint != null && endpoint.isNotEmpty) params['endpoint'] = endpoint;
    if (userId != null) params['user_id'] = userId;
    if (days != null) params['days'] = days;
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

  Future<List<dynamic>> adminAiSummary() async =>
      _asList((await _dio.get('/admin/ai-usage/summary')).data);

  Future<void> adminSetAiUnlimited(int userId, bool unlimited) async =>
      _dio.put('/admin/users/$userId/ai_unlimited', data: {'unlimited': unlimited});

  Future<List<dynamic>> getAssignmentVariants(int assignmentId) async {
    final response = await _dio.get('/assignments/$assignmentId/variants');
    final data = response.data;
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return [];
  }

  Future<Map<String, dynamic>> createAssignmentVariant(int assignmentId, Map<String, dynamic> body) async {
    final response = await _dio.post('/assignments/$assignmentId/variants', data: body);
    return _asMap(response.data);
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
    return _asMap(response.data);
  }

  Future<Map<String, dynamic>> getSubmissionGrade(int submissionId) async {
    final response = await _dio.get('/submissions/$submissionId/grade');
    return _asMap(response.data);
  }

  /// Текст файла по абсолютному URL. Внешние хосты (R2/CDN) идут через
  /// [_plainDio] — без Authorization, иначе токен утекает наружу.
  Future<String> fetchFileText(String url) async {
    try {
      final client = isOwnHostUrl(url) ? _dio : _plainDio;
      final response = await client.get<String>(url,
          options: Options(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 10)));
      return response.data ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Клиент для скачивания файла по абсолютному URL: свой хост — с токеном,
  /// чужой — без. Используется в utils/file_opener.dart.
  Dio clientForUrl(String url) => isOwnHostUrl(url) ? _dio : _plainDio;

  // URL файлов от бэкенда уже содержат "/api/uploads/...", а baseUrl тоже
  // заканчивается на "/api": подменять хост надо корнем БЕЗ "/api", иначе
  // получится задвоенный "/api/api/uploads/..." и 404.
  String get _uploadHostRoot =>
      baseUrl.endsWith('/api') ? baseUrl.substring(0, baseUrl.length - 4) : baseUrl;

  String fixUrl(String url) {
    if (url.isEmpty) return url;
    var fixed = url
        .replaceAll(_localhostRe, _uploadHostRoot)
        .replaceAll(_loopbackRe, _uploadHostRoot);
    if (!fixed.startsWith('http') && !fixed.startsWith('ws')) {
      fixed = '$baseUrl${fixed.startsWith('/') ? '' : '/'}$fixed';
    }
    return fixed;
  }

  String fixUrlsInText(String text) {
    if (text.isEmpty) return text;
    var out = text
        .replaceAll(_localhostRe, _uploadHostRoot)
        .replaceAll(_loopbackRe, _uploadHostRoot);
    out = out.replaceAllMapped(
      _relUploadsRe,
      (m) => '${m[1]}$baseUrl${m[2]}',
    );
    return out;
  }

  String toRelativeUploadUrl(String url) {
    final m = _absUrlPathRe.firstMatch(url);
    return m != null ? m.group(1)! : url;
  }
}
