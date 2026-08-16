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
    final auth = context.watch<AuthProvider>();
    final l = context.watch<L10n>();
    final isAdmin = auth.isAdmin;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = <Widget>[
      const HomeScreen(), const AiScreen(),
      if (isAdmin) const AdminScreen(),
      const SettingsScreen(),
    ];

    final items = <_NavItem>[
      _NavItem(CupertinoIcons.book,               CupertinoIcons.book_fill,              l.t('nav_classes')),
      _NavItem(CupertinoIcons.sparkles,           CupertinoIcons.sparkles,               l.t('nav_ai')),
      if (isAdmin)
        _NavItem(CupertinoIcons.shield,           CupertinoIcons.shield_fill,            l.t('nav_admin')),
      _NavItem(CupertinoIcons.gear,               CupertinoIcons.gear_alt_fill,          l.t('nav_settings')),
    ];

    // Локальная переменная вместо мутации поля прямо в build(): роль могла
    // смениться (админ вышел) и вкладок стало меньше.
    final idx = _idx >= screens.length ? 0 : _idx;

    // Навбар вынесен из layout-дерева экранов в отдельный слой Stack: он стоит
    // у истинного низа и просто перекрывается клавиатурой как оверлеем.
    // Здесь намеренно Material, а не Scaffold: свой Scaffold есть у каждой
    // вкладки, и второй давал бы два «менеджера» клавиатуры вразнобой.
    return Stack(children: [
      Material(
        color: Theme.of(context).scaffoldBackgroundColor,
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
                      title: l.t('no_connection'),
                      onDismiss: () => setState(() => _bannerDismissed = true),
                    ),
            ),
          ),
        ]),
      ),
      const Positioned(left: 0, right: 0, bottom: 0, child: _BottomContentScrim()),
      Positioned(
        // Снаружи нет Scaffold/SafeArea: отступ снизу отмеряется от истинного
        // края экрана вручную, safe-area добавляется явно через MediaQuery.
        left: 16, right: 16,
        bottom: (MediaQuery.paddingOf(context).bottom - 8).clamp(0.0, double.infinity),
        child: RepaintBoundary(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _navAnim,
              curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
            ),
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 1.2), end: Offset.zero)
                  .animate(CurvedAnimation(parent: _navAnim, curve: Curves.easeOutCubic)),
              child: LayoutBuilder(builder: (context, constraints) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: cardShadow(isDark),
                  ),
                  child: LiquidGlassBottomNavBar(
                    items: items
                        .map((it) => LiquidGlassTabBarItem(
                              icon: it.inactive,
                              selectedIcon: it.active,
                              label: it.label,
                            ))
                        .toList(),
                    selectedIndex: idx,
                    onChanged: _onTap,
                    width: constraints.maxWidth,
                    height: 64,
                    itemPadding: 6,
                    style: LiquidGlassStyle(
                      shape: const LiquidGlassShape.roundedRectangle(
                        cornerRadius: 32,
                        borderWidth: 1.0,
                        lightIntensity: 0.35,
                        borderType: OpticalBorder(
                          borderSaturation: 1.0,
                          ambientIntensity: 0.30,
                          borderSolidity: 0.25,
                          lightSpread: 0.35,
                        ),
                      ),
                      appearance: LiquidGlassAppearance(
                        color: isDark ? const Color(0x26000000) : const Color(0x26FFFFFF),
                        blur: const LiquidGlassBlur(sigmaX: 6, sigmaY: 6),
                      ),
                      refraction: const LiquidGlassRefraction(
                        distortion: 0.06,
                        distortionWidth: 24,
                        chromaticAberration: 0.0,
                      ),
                    ),
                    itemStyle: LiquidGlassNavItemStyle(
                      selectedColor: Theme.of(context).colorScheme.primary,
                      unselectedColor: isDark
                          ? Colors.white.withValues(alpha: 0.80)
                          : const Color(0xFF3C4043),
                      iconSize: 23,
                      labelFontSize: 10.5,
                      selectedFontWeight: FontWeight.w700,
                      unselectedFontWeight: FontWeight.w500,
                    ),
                    pillStyle: LiquidGlassNavPillStyle(
                      mode: LiquidGlassPillMode.none,
                      animated: true,
                      animationDuration: const Duration(milliseconds: 240),
                      animationCurve: Curves.easeOutCubic,
                      color: isDark ? const Color(0x33FFFFFF) : const Color(0x59FFFFFF),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _BottomContentScrim extends StatelessWidget {
  const _BottomContentScrim();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Container(
        height: bottomBarClearance(context) + 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: isDark ? 0.30 : 0.14),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData inactive, active;
  final String label;
  _NavItem(this.inactive, this.active, this.label);
}

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
    final glass = isDark
        ? const Color(0xFF1C1C1E).withValues(alpha: 0.72)
        : Colors.white.withValues(alpha: 0.80);

    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -80) onDismiss();
        },
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              boxShadow: cardShadow(isDark),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                  decoration: BoxDecoration(
                    color: glass,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
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
                            color: adaptiveText1(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      CupertinoActivityIndicator(
                        radius: 7,
                        color: isDark ? C.darkText2 : C.text3,
                      ),
                    ],
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
