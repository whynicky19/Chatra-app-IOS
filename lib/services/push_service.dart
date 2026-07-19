import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Обработчик фоновых/убитых FCM-сообщений. Должен быть top-level функцией
/// (запускается в отдельном изоляте). Само уведомление в фоне рисует система
/// (в payload есть notification-блок), поэтому тут ничего показывать не нужно.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // no-op: системный трей уже показал уведомление.
}

/// Инкапсулирует push-уведомления: инициализация FCM, разрешения, показ
/// уведомлений в foreground и навигация по тапу. Регистрация токена на бэкенде
/// привязана к сессии (после логина — register, при выходе — unregister).
class PushService {
  PushService(this.api, this.navigatorKey);

  final ApiService api;
  final GlobalKey<NavigatorState> navigatorKey;

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'chatra_default';
  static const _channelName = 'Уведомления';

  bool _initialized = false;
  bool _isAuthed = false;
  String? _lastSyncedToken;

  /// Инициализация один раз при старте приложения (после Firebase.initializeApp).
  /// Не запрашивает регистрацию на бэкенде — это делает [onAuthenticated].
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Локальный плагин для показа уведомлений, пока приложение открыто.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // разрешение просим через FirebaseMessaging
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null) _routeByType(_decodePayload(payload));
      },
    );

    // Канал Android (важно для heads-up на 8.0+); совпадает с манифестом.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Оценки, сообщения и напоминания о дедлайнах',
          importance: Importance.high,
        ));

    // Foreground: FCM не рисует трей сам — показываем через local notifications.
    FirebaseMessaging.onMessage.listen(_showForeground);

    // Тап по уведомлению, когда приложение в фоне (но живо).
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _routeByType(m.data));

    // Приложение запущено тапом по уведомлению из убитого состояния.
    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      // Небольшая задержка — дать дереву навигации подняться.
      Future.delayed(const Duration(milliseconds: 800),
          () => _routeByType(initial.data));
    }

    // Обновление токена — пересинхронизируем, если пользователь залогинен.
    _fm.onTokenRefresh.listen((t) {
      _lastSyncedToken = null;
      if (_isAuthed) _syncToken(t);
    });
  }

  /// Вызывать после успешного входа/восстановления сессии: спросить разрешение
  /// и зарегистрировать текущий токен на бэкенде.
  Future<void> onAuthenticated() async {
    _isAuthed = true;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      // iOS: без APNs-токена getToken() кинет — глотаем (нет платного аккаунта).
      final token = await _fm.getToken();
      if (token != null) await _syncToken(token);
    } catch (e) {
      if (kDebugMode) print('PushService.onAuthenticated: $e');
    }
  }

  /// Вызывать при выходе: снять токен с сервера, чтобы чужие пуши не приходили.
  Future<void> onLogout() async {
    _isAuthed = false;
    try {
      final token = await _fm.getToken();
      if (token != null) await api.unregisterPushToken(token);
    } catch (_) {}
    _lastSyncedToken = null;
  }

  Future<void> _syncToken(String token) async {
    if (token == _lastSyncedToken) return;
    try {
      await api.registerPushToken(token, platform: _platform());
      _lastSyncedToken = token;
    } catch (e) {
      if (kDebugMode) print('PushService._syncToken: $e');
    }
  }

  String? _platform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return null;
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final n = message.notification;
    final String title = n?.title ?? message.data['title']?.toString() ?? 'Chatra';
    final String body = n?.body ?? message.data['body']?.toString() ?? '';
    await _local.show(
      id: message.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: _encodePayload(message.data),
    );
  }

  // ── Навигация по тапу ──────────────────────────────────────────────────────

  void _routeByType(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    final type = data['type']?.toString();
    final classId = int.tryParse(data['class_id']?.toString() ?? '');

    switch (type) {
      case 'grade':
      case 'deadline':
        if (classId != null) nav.pushNamed('/class', arguments: classId);
        break;
      case 'message':
        // Точный чат открыть сложнее (нужен таб-навигатор); открываем класс,
        // если он передан, иначе оставляем пользователя на текущем экране.
        if (classId != null) nav.pushNamed('/class', arguments: classId);
        break;
    }
  }

  // FCM data — плоская Map<String,String>; кодируем в query-строку для payload.
  String _encodePayload(Map<String, dynamic> data) => data.entries
      .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
      .join('&');

  Map<String, dynamic> _decodePayload(String payload) {
    final map = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final i = pair.indexOf('=');
      if (i > 0) {
        map[Uri.decodeComponent(pair.substring(0, i))] =
            Uri.decodeComponent(pair.substring(i + 1));
      }
    }
    return map;
  }
}
