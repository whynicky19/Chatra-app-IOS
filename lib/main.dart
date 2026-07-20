import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/api_service.dart';
import 'services/crash_reporting.dart';
import 'services/push_service.dart';
import 'services/moderation_service.dart';
import 'utils/errors.dart';
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
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/classes/class_detail_screen.dart';
import 'screens/classes/archive_screen.dart';

/// Дефолт для локальной разработки. Сейчас — LAN-IP этого Mac, чтобы приложение
/// на реальном телефоне (в той же Wi-Fi) достучалось до локального FastAPI без
/// лишних флагов. Для симулятора/macOS/web этот же адрес тоже работает.
/// Если IP Mac поменяется (другая сеть) — обнови значение здесь.
///
/// ⚠️ ДЛЯ РЕЛИЗА / App Store так собирать НЕЛЬЗЯ: нужен задеплоенный прод-домен
/// с валидным HTTPS. Передавай его сборке:
///   flutter build ipa --dart-define=API_URL=https://api.твойдомен
const String _kDevApiUrl = 'http://192.168.10.13:8000';

/// Единый бэкенд для всех платформ — тот же, что у сайта (общая база).
///
/// В release дефолта НЕТ: без --dart-define функция вернёт null, и приложение
/// покажет явный экран ошибки конфигурации вместо белого экрана с висящими
/// запросами в недоступную локалку. Именно так App Store ловил бы 2.1
/// (App Completeness), если бы флаг забыли передать.
String? _resolveBaseUrl() {
  // Прод-URL инжектится сборкой (принимаются оба имени: API_URL / API_BASE_URL):
  //   flutter build ipa --dart-define=API_URL=https://api.твойдомен
  const overrideUrl = String.fromEnvironment('API_URL');
  if (overrideUrl.isNotEmpty) return overrideUrl;
  const overrideUrl2 = String.fromEnvironment('API_BASE_URL');
  if (overrideUrl2.isNotEmpty) return overrideUrl2;
  return kReleaseMode ? null : _kDevApiUrl;
}

/// Экран-заглушка для release-сборки без API_URL. Лучше явная диагностика,
/// чем молчаливо нерабочее приложение.
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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

/// Глобальный ключ навигатора — нужен push-сервису, чтобы открывать нужный
/// экран по тапу по уведомлению (в т.ч. из фонового/убитого состояния).
final navigatorKey = GlobalKey<NavigatorState>();

// Всё приложение живёт внутри защищённой зоны: необработанные ошибки из
// колбэков и таймеров попадают в Crashlytics, а не теряются молча.
void main() => CrashReporting.runGuarded(_start);

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // Firebase (и следом Crashlytics) поднимаем как можно раньше — чтобы ошибки
  // самого старта тоже фиксировались. Только мобильные платформы.
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
  final chats = ChatsProvider(api, auth);
  final moderation = ModerationService(api);

  // UGC-модерация: блок-лист свой для каждого аккаунта. Перезагружаем его
  // только при реальной смене пользователя (логин/логаут/смена аккаунта).
  int? lastModUid = auth.userId;
  moderation.configure(auth.userId);
  CrashReporting.setUser(auth.userId);
  auth.addListener(() {
    if (auth.userId != lastModUid) {
      lastModUid = auth.userId;
      moderation.configure(auth.userId);
      // Чтобы в консоли Crashlytics было видно, у кого воспроизводится краш.
      CrashReporting.setUser(auth.userId);
    }
  });

  api.onUnauthorized = () => auth.logout();
  // Заблокированный админом аккаунт — разлогин с причиной для сообщения на входе.
  api.onAccountBlocked = () => auth.logout(reason: 'account_blocked');

  // Push-уведомления: только мобильные платформы (Android/iOS). Инициализируем
  // ДО auth.init(), чтобы при холодном старте с живой сессией токен успел
  // зарегистрироваться (auth.init → onLogin). Любой сбой не мешает старту.
  // Firebase.initializeApp() уже вызван выше (нужен Crashlytics).
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

  // Kick off initialization but never let a failing init() bubble up as an
  // unhandled async error — the app must still start (providers fall back to
  // their default state and _AuthGate shows the splash until they settle).
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
      ChangeNotifierProvider<ChatsProvider>.value(value: chats),
      ChangeNotifierProvider<ModerationService>.value(value: moderation),
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
      // Тема меняется мгновенно: дефолтный 200мс-лерп ThemeData перестраивал
      // всё дерево ~12 кадров подряд и лагал.
      themeAnimationDuration: Duration.zero,
      // Системный размер шрифта (iOS Dynamic Type / Android font size) теперь
      // учитывается, но с потолком: до 1.3 вёрстка держится, выше — плотные
      // карточки и кнопки начинают резать текст. 1.3 покрывает весь обычный
      // диапазон Dynamic Type; обрезаются только accessibility-размеры (до 3.1),
      // под которые пришлось бы перерисовывать все экраны.
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
          case '/class': return MaterialPageRoute(builder: (_) => ClassDetailScreen(classId: s.arguments as int));
          case '/archive': return MaterialPageRoute(builder: (_) => const ArchiveScreen());
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
  // null — флаг ещё не прочитан; держим splash, чтобы интро не мигнуло.
  bool? _onboardingSeen;

  @override
  void initState() {
    super.initState();
    // Короткая брендинг-пауза; дольше держать пользователя незачем —
    // обычно auth/org инициализируются быстрее.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _splashDone = true);
    });
    OnboardingScreen.isSeen().then((seen) {
      if (mounted) setState(() => _onboardingSeen = seen);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final org = context.watch<OrgProvider>();

    // Показываем splash пока: auth/org не загрузились ИЛИ минимальное время не прошло
    if (!auth.initialized ||
        !org.isInitialized ||
        !_splashDone ||
        _onboardingSeen == null) {
      return const _Splash();
    }

    // Интро — самый первый экран, до выбора организации. Пользователю с живой
    // сессией (переустановка с сохранённым токеном) его не показываем.
    if (_onboardingSeen == false && !auth.isAuthenticated) {
      return OnboardingScreen(
        key: const ValueKey('onboarding'),
        onDone: () => setState(() => _onboardingSeen = true),
      );
    }

    // Плавный переход от splash к контенту
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
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

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
    // Логотип: мягкое появление с лёгким overshoot (премиальный iOS-feel).
    _logoFade = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.5, curve: Curves.easeOut));
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack)),
    );
    // Вордмарк — следом, чуть выезжает снизу.
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
    final primary = isSchool ? C.amber : C.teal;
    final bg = isDark ? Colors.black : Colors.white;
    final wordColor = isDark ? Colors.white : C.text1;

    return Scaffold(
      backgroundColor: bg,
      body: Stack(
        children: [
          // Едва заметный брендовый градиент по фону — глубина без пестроты.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  primary.withValues(alpha: isDark ? 0.06 : 0.045),
                  bg,
                ],
                stops: const [0.0, 0.55],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Логотип с мягким брендовым свечением за ним.
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: SizedBox(
                        width: 168, height: 168,
                        child: Stack(alignment: Alignment.center, children: [
                          // Radial glow
                          DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  primary.withValues(alpha: isDark ? 0.24 : 0.16),
                                  primary.withValues(alpha: 0.0),
                                ],
                                stops: const [0.0, 1.0],
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                          Image.asset(
                            'assets/logo-icon.png',
                            width: 96, height: 96,
                            fit: BoxFit.contain,
                            color: isSchool ? C.amber : null,
                            errorBuilder: (_, __, ___) => Container(
                              width: 96, height: 96,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [primary, isSchool ? C.amberDk : C.tealDk],
                                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.center,
                              child: const Text('C',
                                style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Вордмарк — монохромный (Apple-style), плотный трекинг.
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(children: [
                        Text('Chatra',
                            style: TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w800,
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
          // Индикатор загрузки — внизу, деликатный (Cupertino).
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