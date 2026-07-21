import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../providers/chats_provider.dart';
import '../screens/main_shell.dart';
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
          description: 'Оценки, сообщения и напоминания о дедлайнах',
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

  Future<void> onAuthenticated() async {
    _isAuthed = true;
    try {
      await _fm.requestPermission(alert: true, badge: true, sound: true);
      final token = await _fm.getToken();
      if (token != null) await _syncToken(token);
    } catch (e) {
      if (kDebugMode) print('PushService.onAuthenticated: $e');
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
    if (message.data['type'] == 'message') {
      final chatId = int.tryParse(message.data['chat_id']?.toString() ?? '');
      if (chatId != null) ChatsProvider.pushChatPing.value = chatId;
    }
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
      case 'message':
        final chatId = int.tryParse(data['chat_id']?.toString() ?? '');
        if (chatId != null) {
          ChatsProvider.requestOpenChat.value = chatId;
          MainShell.sectionRequest.value = 'chats';
        }
        break;
      // Админские события: жалоба, заявка на аватар, лекция на модерации —
      // переключаем шелл на вкладку админки (проверка роли — в MainShell).
      case 'admin_report':
      case 'avatar_request':
      case 'lecture_request':
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
