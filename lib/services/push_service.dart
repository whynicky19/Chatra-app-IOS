import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/main_shell.dart';
import '../utils/errors.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
}

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

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
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

    // Канал должен совпадать с манифестом, иначе heads-up на Android 8+ не показывается.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Оценки и напоминания о дедлайнах',
          importance: Importance.high,
        ));

    FirebaseMessaging.onMessage.listen(_showForeground);

    FirebaseMessaging.onMessageOpenedApp.listen((m) => _routeByType(m.data));

    final initial = await _fm.getInitialMessage();
    if (initial != null) {
      Future.delayed(const Duration(milliseconds: 800),
          () => _routeByType(initial.data));
    }

    _fm.onTokenRefresh.listen((t) {
      _lastSyncedToken = null;
      if (_isAuthed) _syncToken(t);
    });
  }

  /// Автотестовые прогоны (flutter drive) идут без запроса разрешения: системный
  /// диалог перехватывает ввод и делает прогон бессмысленным. В обычных сборках
  /// флага нет, поведение прежнее.
  static const _skipPermission = bool.fromEnvironment('NO_PUSH_PROMPT');

  Future<void> onAuthenticated() async {
    _isAuthed = true;
    if (_skipPermission) return;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await _fm.getToken();
      // Отсутствие токена — не мелочь: обычно это забытый entitlement
      // aps-environment или отвалившийся APNs. Раньше это молчало, и пуши
      // просто не приходили без единого следа. Теперь видно в Crashlytics.
      if (token == null) {
        logError('PushService.getToken', StateError('FCM token is null'));
        return;
      }
      await _syncToken(token);
    } catch (e, st) {
      logError('PushService.onAuthenticated', e, st);
    }
  }

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
    } catch (e, st) {
      logError('PushService._syncToken', e, st);
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
      // Админские события: жалоба на модерации —
      // переключаем шелл на вкладку админки (проверка роли — в MainShell).
      case 'admin_report':
        MainShell.sectionRequest.value = 'admin';
        break;
    }
  }

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
