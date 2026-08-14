import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'services/api_service.dart';
import 'services/crash_reporting.dart';
import 'services/push_service.dart';
import 'utils/errors.dart';
import 'providers/auth_provider.dart';
import 'providers/org_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/l10n_provider.dart';
import 'providers/classes_provider.dart';
import 'providers/ai_chats_provider.dart';
import 'theme/app_theme.dart';
import 'widgets/brand_gradient.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/org_select_screen.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/classes/class_detail_screen.dart';
import 'screens/classes/archive_screen.dart';

// Дев-адрес бэкенда «хост-машина», не зависящий от Wi-Fi IP:
//  - iOS-симулятор делит сеть с хостом → 127.0.0.1
//  - Android-эмулятор видит хост как 10.0.2.2
// Для релиза и физических устройств переопредели через --dart-define=API_URL=https://...
String get _kDevApiUrl {
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
  return 'http://127.0.0.1:8000';
}

String? _resolveBaseUrl() {
  const overrideUrl = String.fromEnvironment('API_URL');
  if (overrideUrl.isNotEmpty) return '$overrideUrl/api';
  const overrideUrl2 = String.fromEnvironment('API_BASE_URL');
  if (overrideUrl2.isNotEmpty) return '$overrideUrl2/api';
  return kReleaseMode ? null : '$_kDevApiUrl/api';
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle, size: 48),
                  SizedBox(height: 16),
                  Text(
                    'Сборка без адреса сервера',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Пересобери с флагом:\n'
                    'flutter build ipa --dart-define=API_URL=https://<домен>',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

final navigatorKey = GlobalKey<NavigatorState>();

void main() => CrashReporting.runGuarded(_start);

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // Прогрев шейдеров плавающего навбара (main_shell.dart) заранее, параллельно
  // с остальной инициализацией ниже. Без этого компиляция .frag-шейдеров
  // случается при первом маунте LiquidGlassBottomNavBar — то есть прямо на
  // экране MainShell, самом частом первом экране пользователя — и даёт либо
  // джанк на первом кадре, либо на миг "замороженный" fallback вместо стекла.
  // .ignore() — намеренно не блокирует старт: сплэш и auth/org/theme.init()
  // ниже и так занимают время, обычно этого достаточно, чтобы шейдер успел
  // скомпилироваться до того, как бар вообще станет виден.
  LiquidGlassShaders.ensureLoaded().ignore();

  final isMobile = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  if (isMobile) {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }
  }
  await CrashReporting.init();

  final resolvedBaseUrl = _resolveBaseUrl();
  if (resolvedBaseUrl == null) {
    runApp(const _MisconfiguredApp());
    return;
  }

  final api = ApiService(baseUrl: resolvedBaseUrl);
  final auth = AuthProvider(api);
  final org = OrgProvider();
  final theme = ThemeProvider();
  final l10n = L10n();
  final classes = ClassesProvider(api, auth);
  final aiChats = AiChatsProvider(api, auth);

  int? lastUid = auth.userId;
  CrashReporting.setUser(auth.userId);
  auth.addListener(() {
    if (auth.userId != lastUid) {
      lastUid = auth.userId;
      CrashReporting.setUser(auth.userId);
      // Провайдеры живут всё время работы процесса. Без явного сброса при
      // смене аккаунта (в том числе при выходе, когда userId → null) новый
      // пользователь видит классы, посты, бейдж и ИИ-треды предыдущего.
      classes.reset();
      aiChats.reset();
    }
  });

  api.onUnauthorized = () => auth.logout();
  api.onAccountBlocked = () => auth.logout(reason: 'account_blocked');

  if (isMobile) {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final push = PushService(api, navigatorKey);
      await push.init();
      auth.onLogin = () => push.onAuthenticated();
      auth.onLogout = () => push.onLogout();
    } catch (e, st) {
      logError('main.pushInit', e, st);
    }
  }

  Future.wait([auth.init(), org.init(), theme.init(), l10n.init()])
      .catchError((Object e, StackTrace st) {
    logError('main.init', e, st);
    return const <void>[];
  });

  runApp(MultiProvider(
    providers: [
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<OrgProvider>.value(value: org),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<L10n>.value(value: l10n),
      ChangeNotifierProvider<ClassesProvider>.value(value: classes),
      ChangeNotifierProvider<AiChatsProvider>.value(value: aiChats),
    ],
    child: const ChatraApp(),
  ));
}

class ChatraApp extends StatelessWidget {
  const ChatraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<ThemeProvider, ThemeMode>((t) => t.mode);
    final isSchool  = context.select<OrgProvider, bool>((o) => o.isSchool);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Chatra', debugShowCheckedModeBanner: false,
      theme:     isSchool ? AppTheme.lightSchool : AppTheme.light,
      darkTheme: isSchool ? AppTheme.darkSchool  : AppTheme.dark,
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 1.0,
        maxScaleFactor: 1.3,
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: child!,
        ),
      ),
      home: const _AuthGate(),
      onGenerateRoute: (s) {
        switch (s.name) {
          case '/class':
            // Без проверки типа push с неожиданным class_id ронял построение
            // маршрута TypeError'ом.
            final id = s.arguments;
            if (id is! int) return null;
            return MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: id));
          case '/archive':
            return MaterialPageRoute(builder: (_) => const ArchiveScreen());
          default:
            // Раньше здесь возвращался ещё один _AuthGate — неизвестный
            // маршрут клал второй сплэш/шелл поверх существующего вместо
            // понятной ошибки.
            return null;
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
  bool? _onboardingSeen;

  @override
  void initState() {
    super.initState();
    // Раньше здесь была искусственная задержка в 400мс — избыточна: сплэш и
    // так висит на экране, пока не завершатся auth.init()/org.init()/
    // theme.init() (см. условие ниже в build), этого достаточно как нижней
    // границы показа сплэша.
    _splashDone = true;
    OnboardingScreen.isSeen().then((seen) {
      if (mounted) setState(() => _onboardingSeen = seen);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final org = context.watch<OrgProvider>();

    if (!auth.initialized ||
        !org.isInitialized ||
        !_splashDone ||
        _onboardingSeen == null) {
      return const _Splash();
    }

    if (_onboardingSeen == false && !auth.isAuthenticated) {
      return OnboardingScreen(
        key: const ValueKey('onboarding'),
        onDone: () => setState(() => _onboardingSeen = true),
      );
    }

    // Вход в приложение — намеренно без кросс-фейда, сразу шеллом.
    //
    // Пока MainShell был веткой AnimatedSwitcher, переход занимал 250 мс, в
    // течение которых жили и рисовались ОБА дерева: уходящий экран логина и
    // строящийся шелл. А первый кадр шелла — самый тяжёлый за всю сессию:
    // раскладка карточек классов, декодирование обложек, компиляция шейдера
    // стеклянного таб-бара. Вдобавок FadeTransition — это Opacity < 1, то есть
    // оба экрана рисуются в отдельные offscreen-слои (saveLayer), а
    // BackdropFilter таб-бара внутри такого слоя ещё и не видит фон за собой
    // (та же механика, что чинилась на кнопке экрана выбора организации).
    //
    // Анимация между самими экранами входа (выбор организации → логин)
    // осталась: там оба дерева лёгкие.
    if (auth.isAuthenticated) return const MainShell(key: ValueKey('main'));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOut,
      child: !org.isSelected
          ? const OrgSelectScreen(key: ValueKey('org'))
          : const _AuthNavigator(key: ValueKey('auth')),
    );
  }
}

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

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    // Интервалы кривых ниже заданы в долях [0,1] от длительности контроллера,
    // поэтому пересчитывать их отдельно не нужно — они уже пропорциональны.
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _logoFade = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)),
    );
    _textFade = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic)),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSchool = context.select<OrgProvider, bool>((o) => o.isSchool);
    final bg = isDark ? C.darkBg : Colors.white;
    final wordColor = isDark ? Colors.white : C.text1;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: SizedBox(
                        width: 168, height: 168,
                        child: Center(
                          // ТЕСТ: градиентная заливка глифа вместо плоского
                          // чёрного/белого — только здесь (splash), остальные
                          // места (login/register/org-select) не трогали.
                          child: Builder(builder: (_) {
                            final fallback = Container(
                              width: 96, height: 96,
                              decoration: BoxDecoration(
                                color: isDark ? C.darkSurface2 : C.surface2,
                                borderRadius: BorderRadius.circular(AppRadii.card),
                              ),
                              alignment: Alignment.center,
                              child: Text('C',
                                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: wordColor)),
                            );
                            if (isSchool) {
                              return Image.asset('assets/logo-icon.png', width: 96, height: 96,
                                  fit: BoxFit.contain, color: C.amber,
                                  errorBuilder: (_, __, ___) => fallback);
                            }
                            return BrandGradient.mask(
                              child: Image.asset('assets/logo-icon.png', width: 96, height: 96,
                                  fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(children: [
                        Text('Chatra',
                            style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w700,
                              color: wordColor, letterSpacing: -0.5,
                            )),
                        const SizedBox(height: 5),
                        Text('EDUCATION PLATFORM',
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: (isDark ? Colors.white : C.text4).withValues(alpha: 0.55),
                              letterSpacing: 2.4,
                            )),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 54,
            child: FadeTransition(
              opacity: _textFade,
              child: Center(
                child: CupertinoActivityIndicator(
                  radius: 13,
                  color: (isDark ? Colors.white : C.text1).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
