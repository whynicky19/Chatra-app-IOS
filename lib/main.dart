import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'providers/auth_provider.dart';
import 'providers/org_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/l10n_provider.dart';
import 'providers/classes_provider.dart';
import 'providers/chats_provider.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/org_select_screen.dart';
import 'screens/main_shell.dart';
import 'screens/classes/class_detail_screen.dart';

/// Выбираем правильный baseUrl в зависимости от платформы:
/// - Android emulator: 10.0.2.2 — это alias хоста
/// - iOS simulator / macOS / web: 127.0.0.1
/// - Реальное устройство: подставь IP машины с бэком вручную ниже
String _resolveBaseUrl() {
  const overrideUrl = String.fromEnvironment('API_URL');
  if (overrideUrl.isNotEmpty) return overrideUrl;
  if (kIsWeb) return 'http://127.0.0.1:8000';
  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://192.168.10.6:8000';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  final api = ApiService(baseUrl: _resolveBaseUrl());
  final auth = AuthProvider(api);
  final org = OrgProvider();
  final theme = ThemeProvider();
  final l10n = L10n();
  final classes = ClassesProvider(api, auth);
  final chats = ChatsProvider(api, auth);

  api.onUnauthorized = () => auth.logout();
  Future.wait([auth.init(), org.init(), theme.init(), l10n.init()]);

  runApp(MultiProvider(
    providers: [
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<OrgProvider>.value(value: org),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<L10n>.value(value: l10n),
      ChangeNotifierProvider<ClassesProvider>.value(value: classes),
      ChangeNotifierProvider<ChatsProvider>.value(value: chats),
    ],
    child: ChatraApp(),
  ));
}

class ChatraApp extends StatelessWidget {
  const ChatraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final org   = context.watch<OrgProvider>();
    final isSchool = org.isSchool;
    return MaterialApp(
      title: 'Chatra', debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFor(isSchool),
      darkTheme: AppTheme.darkFor(isSchool),
      themeMode: theme.mode,
      builder: (context, child) => GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: child!,
      ),
      home: const _AuthGate(),
      onGenerateRoute: (s) {
        switch (s.name) {
          case '/class': return MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: s.arguments as int));
          default: return MaterialPageRoute(builder: (_) => const _AuthGate());
        }
      },
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 800), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final org = context.watch<OrgProvider>();

    // Показываем splash пока: auth/org не загрузились ИЛИ минимальное время не прошло
    if (!auth.initialized || !org.isInitialized || !_splashDone) return const _Splash();

    // Плавный переход от splash к контенту
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      child: auth.isAuthenticated
          ? const MainShell(key: ValueKey('main'))
          : !org.isSelected
              ? const OrgSelectScreen(key: ValueKey('org'))
              : const _AuthNavigator(key: ValueKey('auth')),
    );
  }
}

// Отдельный Navigator только для auth экранов
class _AuthNavigator extends StatefulWidget {
  const _AuthNavigator({super.key});
  @override
  State<_AuthNavigator> createState() => _AuthNavigatorState();
}

class _AuthNavigatorState extends State<_AuthNavigator> {
  bool _showRegister = false;

  void _goRegister() => setState(() => _showRegister = true);
  void _goLogin() => setState(() => _showRegister = false);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _showRegister
          ? RegisterScreen(key: const ValueKey('register'), onGoLogin: _goLogin)
          : LoginScreen(key: const ValueKey('login'), onGoRegister: _goRegister),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();
    _logoCtrl = AnimationController(vsync: this, duration: Duration(milliseconds: 700));
    _logoScale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );
    _logoCtrl.forward();
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Color(0xFF0A1214) : Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: Image.asset(
                    'assets/logo-icon.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.contain,
                    // Fallback на случай если ассет не подгрузился — рисуем
                    // простой кружок с буквой "C", чтобы не было пустоты
                    errorBuilder: (_, __, ___) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text('C',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24),
              // Текст показываем сразу, без fade-in, чтобы не было пустого экрана
              Text(
                'Chatra',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Education Platform',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF7AABB5),
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 40),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}