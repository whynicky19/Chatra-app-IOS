import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../providers/auth_provider.dart';
import '../providers/l10n_provider.dart';
import '../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'ai/ai_screen.dart';
import 'admin/admin_screen.dart';
import 'settings/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Запрос переключения вкладки извне (пуш «жалоба/заявка» ведёт в админку).
  /// Значения: 'admin'. Обрабатывается и сбрасывается _MainShellState.
  static final ValueNotifier<String?> sectionRequest = ValueNotifier<String?>(null);

  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _idx = 0;
  late AnimationController _navAnim;

  bool _isOnline = true;
  bool _bannerDismissed = false;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  Timer? _offlineDebounce;
  Timer? _recheckTimer;
  int _recheckAttempt = 0;

  // ── Кэш статических nav-items: пересоздаются только при реальной смене
  // (локали, роли, платформы), а не на каждом rebuild. Без этого build()
  // каждый раз аллоцирует ~10 объектов LiquidGlassStyle + список с
  // closure-builder'ами — LiquidGlassTabBar не может сравнить их по == и
  // уходит в полный diff поддерева линзы. ──
  List<_NavItem> _navItemsCache = const [];
  String _navItemsKey = '';

  // ── Кэш тяжёлых LiquidGlassStyle'ов. Стили — const-объекты, но
  // зависимы от темы: пересоздаются при смене isDark, и в build() кладутся
  // уже готовые по тому же ключу. ──
  static const _DarkLightStyles _lightStyles = _DarkLightStyles._(
    shape: LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: 30,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.5,
      borderColor: Color(0x1F000000),
      lightIntensity: 0.8,
      lightDirection: 62,
      borderType: OpticalBorder(
        borderSaturation: 1.0,
        ambientIntensity: 0.7,
        borderSolidity: 0.5,
      ),
    ),
    restColor: Color(0x1FFFFFFF),
    neutralFg: Color(0xFF1C1C1E),
    adaptivityColorOnDark: Color(0x14000000),
    adaptivityColorOnLight: Color(0x14FFFFFF),
  );
  static const _DarkLightStyles _darkStyles = _DarkLightStyles._(
    shape: LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: 30,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.3,
      borderColor: Color(0x1FFFFFFF),
      lightIntensity: 0.4,
      lightDirection: 62,
      borderType: OpticalBorder(
        borderSaturation: 0.6,
        ambientIntensity: 0.3,
        borderSolidity: 0.2,
      ),
    ),
    restColor: Color(0x26FFFFFF),
    neutralFg: Color(0xEBFFFFFF), // 0.92 alpha
    adaptivityColorOnDark: Color(0x14000000),
    adaptivityColorOnLight: Color(0x14FFFFFF),
  );

  static const LiquidGlassAppearance _barAppearance = LiquidGlassAppearance(
    color: Color(0x0FFFFFFF),
    blur: LiquidGlassBlur(sigmaX: 2, sigmaY: 2),
    shadow: LiquidGlassShadow(blur: 22, opacity: 0.14),
  );

  static const LiquidGlassRefraction _barRefraction = LiquidGlassRefraction(
    distortion: 0.13,
    distortionWidth: 34,
    chromaticAberration: 0.006,
    magnification: 1.0,
  );

  static const LiquidGlassStyle _glassPillGlass = LiquidGlassStyle(
    appearance: LiquidGlassAppearance(color: Color(0x06FFFFFF)),
    refraction: LiquidGlassRefraction(
      distortion: 0.16,
      distortionWidth: 26,
      chromaticAberration: 0.008,
    ),
  );

  static const LiquidGlassTabMagnifierPillStyle _magnifierOff =
      LiquidGlassTabMagnifierPillStyle(enabled: false, magnification: 0.86);

  static const LiquidGlassLensMotionSpec _motionSpec = LiquidGlassLensMotionSpec(
    sampleWindow: 0.3,
    sensitivity: 0.00007,
    maxDeformation: 0.12,
    // Под новый travel ≈550 ms: линза должна жить синхронно
    // с морфингом пилюли, не «догонять» его на хвосте.
    responseTime: 0.30,
  );

  static const LiquidGlassAdaptivity _adaptivity = LiquidGlassAdaptivity(
    glassColorOnDark: Color(0x14000000),
    contentColorOnDark: Color(0xFFFFFFFF),
    glassColorOnLight: Color(0x14FFFFFF),
    contentColorOnLight: Color(0xFF1C1C1E),
    duration: Duration(milliseconds: 320),
    darkBelow: 0.50,
    lightAbove: 0.55,
  );

  static const LiquidGlassScaffoldAdaptivity _scaffoldAdaptivity =
      LiquidGlassScaffoldAdaptivity(
    _adaptivity,
    systemChrome: LiquidGlassSystemChrome.statusBar,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _navAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    _navAnim.forward();

    Connectivity().checkConnectivity().then(_applyConnectivity);
    _connectSub = Connectivity().onConnectivityChanged.listen(_applyConnectivity);

    MainShell.sectionRequest.addListener(_onSectionRequest);
    // Пуш мог прийти до построения шелла (холодный старт по тапу).
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSectionRequest());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // В фоне опрашивать сеть незачем: это чистый расход батареи, а iOS ещё и
    // помечает приложение как активное в фоне.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _recheckTimer?.cancel();
      _recheckTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      Connectivity().checkConnectivity().then(_applyConnectivity);
    }
  }

  void _onSectionRequest() {
    final section = MainShell.sectionRequest.value;
    if (section == null || !mounted) return;
    MainShell.sectionRequest.value = null;
    if (section == 'admin' && context.read<AuthProvider>().isAdmin) {
      // Вкладка админа — после Классов/ИИ.
      _onTap(2);
    }
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final online = results.isEmpty || results.any((v) => v != ConnectivityResult.none);
    if (online) {
      _offlineDebounce?.cancel();
      _offlineDebounce = null;
      _recheckTimer?.cancel();
      _recheckTimer = null;
      _recheckAttempt = 0;
      if (!_isOnline && mounted) {
        setState(() {
          _isOnline = true;
          _bannerDismissed = false;
        });
      }
      return;
    }

    if (!_isOnline || _offlineDebounce?.isActive == true) return;

    _offlineDebounce = Timer(const Duration(seconds: 3), () {
      if (mounted && _isOnline) {
        setState(() {
          _isOnline = false;
          _bannerDismissed = false;
        });
        _startRecheck();
      }
    });
  }

  /// Перепроверка с экспоненциальным откатом 2→4→…→60 с, а не Timer.periodic
  /// раз в 2 секунды навсегда. Поток onConnectivityChanged всё равно
  /// поймает возврат сети — это лишь подстраховка.
  void _startRecheck() {
    _recheckTimer?.cancel();
    // Счётчик ограничен ДО сдвига: `2 << 62` переполняет int64 в минус, и
    // clamp(2, 60) вернул бы 2 секунды — откат схлопывался бы обратно в опрос.
    final seconds = (2 << _recheckAttempt.clamp(0, 5)).clamp(2, 60);
    _recheckTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted) return;
      _recheckAttempt++;
      final results = await Connectivity().checkConnectivity();
      if (!mounted) return;
      _applyConnectivity(results);
      if (mounted && !_isOnline) _startRecheck();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MainShell.sectionRequest.removeListener(_onSectionRequest);
    _offlineDebounce?.cancel();
    _recheckTimer?.cancel();
    _connectSub?.cancel();
    _navAnim.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    if (_idx == i) return;
    HapticFeedback.lightImpact();
    setState(() => _idx = i);
  }

  @override
  Widget build(BuildContext context) {
    // context.select вместо context.watch: build() ребилдится ТОЛЬКО при
    // смене нужного поля (роль), а не при ЛЮБОМ notifyListeners() от
    // AuthProvider/L10n. AuthProvider дёргает notifyListeners() при
    // refresh-токена, сетевых ошибках, логине/логауте — watch на нём
    // раньше ребилдил весь шелл на каждый чих, и в нём пересоздавались
    // тяжёлые LiquidGlassStyle, которые потом не diff'ились по ==.
    final isAdmin = context.select<AuthProvider, bool>((a) => a.isAdmin);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final useMaterial = Theme.of(context).platform == TargetPlatform.android;

    // Локализованные подписи — отдельный select, чтобы перерисовка
    // навбара случалась только при СМЕНЕ самих строк, а не на каждый
    // notifyListeners() от L10n (он шлёт их при инициализации/смене
    // языка, не при горячих апдейтах).
    final l10nTick = context.select<L10n, int>((l) => l.version);

    final screens = <Widget>[
      const HomeScreen(), const AiScreen(),
      if (isAdmin) const AdminScreen(),
      const SettingsScreen(),
    ];

    // ── Кэш nav-items: пересоздаём список только при смене зависимостей. ──
    final itemsKey = '$l10nTick|${isAdmin ? 1 : 0}|${useMaterial ? 1 : 0}';
    if (itemsKey != _navItemsKey) {
      _navItemsKey = itemsKey;
      // Читаем L10n напрямую для сборки подписей (select выше даёт только
      // tick для инвалидации кэша).
      final l = context.read<L10n>();
      _navItemsCache = <_NavItem>[
        _NavItem(
          useMaterial ? Icons.menu_book_outlined : CupertinoIcons.book,
          useMaterial ? Icons.menu_book : CupertinoIcons.book_fill,
          l.t('nav_classes'),
        ),
        _NavItem(
          useMaterial ? Icons.auto_awesome_outlined : CupertinoIcons.sparkles,
          useMaterial ? Icons.auto_awesome : CupertinoIcons.sparkles,
          l.t('nav_ai'),
        ),
        if (isAdmin)
          _NavItem(
            useMaterial ? Icons.shield_outlined : CupertinoIcons.shield,
            useMaterial ? Icons.shield : CupertinoIcons.shield_fill,
            l.t('nav_admin'),
          ),
        _NavItem(
          useMaterial ? Icons.settings_outlined : CupertinoIcons.gear,
          useMaterial ? Icons.settings : CupertinoIcons.gear_alt_fill,
          l.t('nav_settings'),
        ),
      ];
    }
    final items = _navItemsCache;

    // Локальная переменная вместо мутации поля прямо в build(): роль могла
    // смениться (админ вышел) и вкладок стало меньше.
    final idx = _idx >= screens.length ? 0 : _idx;

    // Тело шелла: плавающий навбар-скоуп + ленивый стек вкладок +
    // оффлайн-баннер сверху. На iOS оборачиваем в `Material(transparency)`
    // БЕЗ собственного `color` — иначе линза навбара рефрагирует наш
    // плоский scaffoldBackgroundColor, а не живой контент вкладки. Цвет
    // фона страницы рисует сама вкладка.
    final body = RepaintBoundary(
      // Изолируем скролл внутри вкладок от навбара: пока пользователь
      // крутит ListView, LiquidGlass-капсула и пилюля не перерисовываются.
      // Особенно важно для стека двух линз: capture-pipeline бара не
      // триггерится репейнтом scrollable.
      child: Stack(children: [
        Positioned.fill(
          child: FloatingNavBarScope(
            child: _LazyIndexedStack(
              index: idx,
              children: screens,
            ),
          ),
        ),
          Positioned(
            top: 0, left: 0, right: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 340),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: (_isOnline || _bannerDismissed)
                  ? const SizedBox.shrink(key: ValueKey('online'))
                  : _OfflineBanner(
                      key: const ValueKey('offline'),
                      title: context.read<L10n>().t('no_connection'),
                      onDismiss: () => setState(() => _bannerDismissed = true),
                    ),
            ),
          ),
      ]),
    );

    if (useMaterial) {
      // Android: нативный M3 NavigationBar, но с нейтральной
      // палитрой как на iOS — никакого «голубоватого» selected
      // accent. M3 по умолчанию использует colorScheme.primary
      // (наш teal/orange) и tint-индикатор — это и давало
      // «тёмные голубые кнопки». Принудительно задаём чёрный в
      // светлой теме и белый в тёмной через NavigationBarTheme.
      //
      // Оборачиваем в Scaffold, чтобы M3 сам обрезал body по
      // верху навбара — иначе поверх стека остаётся «полоса»
      // (запас bottomBarClearance + сама высота навбара). Сейчас
      // навбар лежит в самом низу, а body идёт ровно до его
      // верха — без зазора.
      final androidNeutralFg = isDark
          ? Colors.white.withValues(alpha: 0.92)
          : const Color(0xFF1C1C1E);
      final androidDimFg = isDark
          ? Colors.white.withValues(alpha: 0.55)
          : const Color(0xFF1C1C1E).withValues(alpha: 0.55);
      final mq = MediaQuery.of(context);
      return Scaffold(
        // body обрезается по верху bottomNavigationBar, без
        // двойной вставки safe-area.
        extendBody: false,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: MediaQuery(
          // Убираем нижний safe-area, который Scaffold уже учёл в
          // навбаре — иначе вкладки внутри получают лишний padding
          // снизу и появляется «полоса воздуха» под контентом.
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: 0),
          ),
          child: body,
        ),
        bottomNavigationBar: RepaintBoundary(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _navAnim,
              curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _navAnim, curve: Curves.easeOutCubic)),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  // Чистый selected-цвет (без «голубоватого» accent).
                  // Индикатор — прозрачный, чтобы не было
                  // tinted-капсулы под selected.
                  indicatorColor: Colors.transparent,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Colors.transparent,
                  // Иконки: selected = полный, unselected = тот же
                  // цвет с alpha 0.55. Как в iOS-варианте, только
                  // через M3-атрибут.
                  iconTheme: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.selected)) {
                      return IconThemeData(color: androidNeutralFg, size: 26);
                    }
                    return IconThemeData(color: androidDimFg, size: 24);
                  }),
                  // Лейблы: тот же подход, font-weight меняется.
                  labelTextStyle: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.selected)) {
                      return TextStyle(
                        color: androidNeutralFg,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      );
                    }
                    return TextStyle(
                      color: androidDimFg,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    );
                  }),
                ),
                child: NavigationBar(
                  selectedIndex: idx,
                  onDestinationSelected: _onTap,
                  destinations: [
                    for (final it in items)
                      NavigationDestination(
                        icon: Icon(it.inactive),
                        selectedIcon: Icon(it.active),
                        label: it.label,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // iOS / iPadOS / macOS: native iOS 26 Liquid Glass.
    //
    // Архитектура: LiquidGlassScaffold владеет capture-pipeline (sampler
    // 8 fps) и настраивает OS chrome. На iOS по умолчанию Impeller —
    // линзы читают живой backdrop, рефракция работает напрямую без view.
    // Scaffold наследует adaptivity на бар.
    //
    // Стеклянный pill (mode: both) сам себе LiquidGlass-линза: при
    // переключении вкладки вырастает (growHeight 10), скользит по spring
    // (300/26 ≈ критично-демпфированный, без овершута), squash по
    // ускорению (±12%).
    //
    // Magnifier-pill ОТКЛЮЧЁН: его эффект (доп. «выпуклость» под
    // пилюлей) был ничтожен, а стек двух линз под капсулой бара удваивал
    // стоимость каждого shader-прохода при движении пилюли и при живом
    // скролле рядом. На статичной пилюле бар по-прежнему стеклянный —
    // без второй рефракции внутри неё.
    //
    // pixelRatio 0.05 (8×40 px sampler) + realTimeCapture: false +
    // useSync: false — capture-pipeline спит большую часть времени
    // (включается ровно на 280 ms движения пилюли при тапе) и кладётся в
    // крошечный 8×40 px буфер вместо full-screen.
    final styles = isDark ? _darkStyles : _lightStyles;
    final neutralFg = styles.neutralFg;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final barWidth = (screenWidth - 16 * 2).clamp(280.0, 560.0);

    final bar = LiquidGlassTabBar(
        items: items
            .map((it) => LiquidGlassTabBarItem(
                  label: it.label,
                  iconBuilder: (context, i) => Icon(
                    i.selected ? it.active : it.inactive,
                    size: i.underGlass ? 27 : 24,
                    color: i.color,
                  ),
                ))
            .toList(),
        selectedIndex: idx,
        onChanged: _onTap,
        width: barWidth,
        height: 60,
        itemPadding: 3,
        // Дистанция от низа. LiquidGlassScaffold сам добавляет
        // safe-area inset. Отрицательные значения сдвигают бар
        // ближе к нижнему краю экрана (залезают под safe-area).
        margin: const EdgeInsets.only(bottom: -12),
        style: LiquidGlassStyle(
          shape: styles.shape,
          appearance: _barAppearance,
          refraction: _barRefraction,
        ),
        itemStyle: LiquidGlassTabItemStyle(
          // Один нейтральный цвет для selected и unselected — как в
          // iOS 26. Отличается только вес/заполненность иконки.
          selectedColor: neutralFg,
          unselectedColor: neutralFg,
          iconSize: 24,
          labelFontSize: 10.5,
          iconLabelGap: 2,
          underGlassIconSize: 27,
          underGlassLabelFontSize: 10.5,
          selectedFontWeight: FontWeight.w700,
          unselectedFontWeight: FontWeight.w500,
        ),
        pillStyle: LiquidGlassTabPillStyle(
          // Glass-refracting morphing pill.
          mode: LiquidGlassPillMode.both,
          show: true,
          glassStyle: _glassPillGlass,
          rest: LiquidGlassStyle(
            appearance: LiquidGlassAppearance(color: styles.restColor),
          ),
          // Spring-перенос: stiffness 200, damping 32 (ζ≈1.13) — слегка
          // пере-демпфированный, без овершута, гасится гладко без
          // хвоста. Длиннее ход (~550 ms) и более плавная кривая
          // дают «шёлковое» скольжение вместо рывка.
          travelStiffness: 200,
          travelDamping: 32,
          // Вырастает на 12px — чуть мягче squash при ускорении.
          growHeight: 12,
          motion: _motionSpec,
          magnifierPill: _magnifierOff,
          animated: true,
          // Длиннее, чем ход spring — ход успевает полностью
          // затухнуть в окне анимации, без жёсткого «обрыва».
          animationDuration: const Duration(milliseconds: 620),
          // Очень мягкий ease-out: плавный старт, плавный
          // финиш, без «утыкания» в конце.
          animationCurve: Cubic(0.12, 0.85, 0.28, 1.0),
        ),
    );

    return LiquidGlassScaffold(
      // pixelRatio 0.05 вместо 1.0: capture 8×40 px = 1.3 KB вместо
      // ~1.3 MB на каждый кадр. Адаптивный вердикт получает ту же
      // информацию (фон-«среднее»), что и при полном захвате — но без
      // копирования экрана в текстуру каждый кадр.
      pixelRatio: 0.05,
      // realTimeCapture: false → capture-pipeline спит, пока бар не
      // движется. Скролл контента внутри вкладок больше не запускает
      // перезахват body. Capture просыпается только на ~280 ms движения
      // пилюли при тапе вкладки.
      realTimeCapture: false,
      // useSync: false → убираем sync barrier на каждом кадре захвата.
      // На Impeller это просто снимает stall, на Skia — заметный выигрыш
      // по FPS при морфинге пилюли.
      useSync: false,
      adaptivity: _scaffoldAdaptivity,
      body: body,
      bottomNavigationBar: RepaintBoundary(
        // Изолируем бар от репейнтов scrollable-вкладок. Внутренние
        // ListView/Stack экранов теперь не перекрашивают область
        // навбара при каждом скролле.
        child: bar,
      ),
    );
  }
}

class _NavItem {
  final IconData inactive, active;
  final String label;
  const _NavItem(this.inactive, this.active, this.label);
}

/// Кэш констант стилей, зависящих только от темы (isDark). Они const-объекты,
/// но не получится сделать top-level const, потому что зависят от условия,
/// вычисляемого в build. Поэтому храним две готовые ветки — light/dark — и
/// берём подходящую за O(1) без аллокаций.
class _DarkLightStyles {
  final LiquidGlassShape shape;
  final Color restColor;
  final Color neutralFg;
  final Color adaptivityColorOnDark;
  final Color adaptivityColorOnLight;
  const _DarkLightStyles._({
    required this.shape,
    required this.restColor,
    required this.neutralFg,
    required this.adaptivityColorOnDark,
    required this.adaptivityColorOnLight,
  });
}

// ── Константы оффлайн-баннера: вынесены в файловый скоуп, чтобы не
// пересоздавать ImageFilter/BoxShadow/Border на каждом build (особенно
// ImageFilter — он создаёт GPU-ресурс, и его dispose/replace дороже
// самого blur-прохода). ──
const BorderRadius _kOfflineRadius = BorderRadius.all(Radius.circular(100));
final ImageFilter _offlineBlur = ImageFilter.blur(sigmaX: 24, sigmaY: 24);
const Color _offlineGlassDark = Color(0xFF1C1C1E); // alpha 0xB8 = 0.72
const Color _offlineGlassLight = Color(0xCCFFFFFF); // alpha 0.80
final List<BoxShadow> _offlineShadowDark = cardShadow(true);
final List<BoxShadow> _offlineShadowLight = cardShadow(false);
const Color _offlineBorderDark = Color(0x1FFFFFFF); // alpha 0.12
const Color _offlineBorderLight = Color(0x0F000000); // alpha 0.06

class _LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  const _LazyIndexedStack({required this.index, required this.children});

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late List<bool> _built;

  @override
  void initState() {
    super.initState();
    _built = List.filled(widget.children.length, false);
    _built[widget.index] = true;
  }

  @override
  void didUpdateWidget(_LazyIndexedStack old) {
    super.didUpdateWidget(old);
    if (widget.children.length != _built.length) {
      _built = List.filled(widget.children.length, false);
    }
    _built[widget.index] = true;
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _built[i] ? widget.children[i] : const SizedBox.shrink(),
      ],
    );
  }
}

/// Компактная «пилюля» в духе системных плашек iOS: по ширине содержимого,
/// без плашки-ручки (это афорданс нижних шторок) и без крестика — смахивание
/// вверх закрывает. Индикатор повторной попытки — родной CupertinoActivityIndicator.
class _OfflineBanner extends StatelessWidget {
  final String title;
  final VoidCallback onDismiss;
  const _OfflineBanner({
    super.key,
    required this.title,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.paddingOf(context).top;
    // Константные статические объекты подняты наружу из build —
    // иначе каждый rebuild аллоцирует новый ImageFilter (и его GPU
    // cleanup дороже самого blur).
    final glass = isDark ? _offlineGlassDark : _offlineGlassLight;
    final shadow = isDark ? _offlineShadowDark : _offlineShadowLight;
    final borderColor = isDark ? _offlineBorderDark : _offlineBorderLight;
    final activityColor = isDark ? C.darkText2 : C.text3;
    final textColor = adaptiveText1(context);

    return RepaintBoundary(
      // Изолируем репейнт: BackdropFilter(blur 24) на всю ширину
      // баннера и анимированный activity-indicator теперь не
      // триггерят перерисовку navbar / ListView вкладок, и наоборот.
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) < -80) onDismiss();
          },
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: _kOfflineRadius,
                boxShadow: shadow,
              ),
              child: ClipRRect(
                borderRadius: _kOfflineRadius,
                child: BackdropFilter(
                  filter: _offlineBlur,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                    decoration: BoxDecoration(
                      color: glass,
                      borderRadius: _kOfflineRadius,
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.wifi_slash,
                            size: 15, color: C.red),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        CupertinoActivityIndicator(
                          radius: 7,
                          color: activityColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
