import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../providers/auth_provider.dart';
import '../providers/chats_provider.dart';
import '../providers/l10n_provider.dart';
import '../theme/app_theme.dart';
import 'home/home_screen.dart';
import 'chats/chats_screen.dart';
import 'ai/ai_screen.dart';
import 'admin/admin_screen.dart';
import 'settings/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  static const _chatsTabIndex = 1;

  int _idx = 0;
  late AnimationController _navAnim;

  bool _isOnline = true;
  bool _bannerDismissed = false; // юзер смахнул баннер вручную
  StreamSubscription<List<ConnectivityResult>>? _connectSub;
  Timer? _offlineDebounce;
  Timer? _recheckTimer; // пока оффлайн — периодически перепроверяем сеть

  @override
  void initState() {
    super.initState();
    _navAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    _navAnim.forward();
    context.read<ChatsProvider>().isScreenVisible = _idx == _chatsTabIndex;

    Connectivity().checkConnectivity().then(_applyConnectivity);
    _connectSub = Connectivity().onConnectivityChanged.listen(_applyConnectivity);
  }

  // connectivity_plus can briefly report `none` (or an empty list) right after a
  // screen (re)mounts — e.g. logging into a second account tears down and rebuilds
  // MainShell — even when the network is perfectly fine. To avoid a false
  // "no connection" banner: treat an empty result as online, flip to ONLINE
  // immediately, but only flip to OFFLINE if it stays offline for a few seconds
  // (a transient `none` is cancelled before the banner ever shows).
  void _applyConnectivity(List<ConnectivityResult> results) {
    final online = results.isEmpty || results.any((v) => v != ConnectivityResult.none);
    _offlineDebounce?.cancel();
    if (online) {
      _recheckTimer?.cancel();
      _recheckTimer = null;
      if (!_isOnline && mounted) {
        setState(() {
          _isOnline = true;
          _bannerDismissed = false;
        });
      }
    } else {
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
  }

  // Поток onConnectivityChanged иногда «пропускает» возврат сети (особенно в
  // эмуляторе), из-за чего баннер зависал. Пока мы оффлайн — сами опрашиваем
  // connectivity раз в 2 сек, так что при возврате интернета баннер уходит сам.
  void _startRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      Connectivity().checkConnectivity().then(_applyConnectivity);
    });
  }

  @override
  void dispose() {
    _offlineDebounce?.cancel();
    _recheckTimer?.cancel();
    _connectSub?.cancel();
    _navAnim.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    if (_idx == i) return;
    HapticFeedback.lightImpact();
    context.read<ChatsProvider>().isScreenVisible = i == _chatsTabIndex;
    setState(() => _idx = i);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final l = context.watch<L10n>();
    final isAdmin = auth.isAdmin;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final screens = <Widget>[
      const HomeScreen(), const ChatsScreen(), const AiScreen(),
      if (isAdmin) const AdminScreen(),
      const SettingsScreen(),
    ];

    final items = <_NavItem>[
      _NavItem(CupertinoIcons.book,               CupertinoIcons.book_fill,              l.t('nav_classes')),
      _NavItem(CupertinoIcons.bubble_left,        CupertinoIcons.bubble_left_fill,       l.t('nav_chats')),
      _NavItem(CupertinoIcons.sparkles,           CupertinoIcons.sparkles,               l.t('nav_ai')),
      if (isAdmin)
        _NavItem(CupertinoIcons.shield,           CupertinoIcons.shield_fill,            l.t('nav_admin')),
      _NavItem(CupertinoIcons.gear,               CupertinoIcons.gear_alt_fill,          l.t('nav_settings')),
    ];

    if (_idx >= screens.length) _idx = 0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        // Ленивый IndexedStack: экран строится только при первом заходе на
        // вкладку (быстрый старт — не инициализируем все 5 экранов разом),
        // после этого остаётся смонтированным (state сохраняется), но
        // скрытые экраны offstage — без GPU-затрат.
        Positioned.fill(
          child: _LazyIndexedStack(
            index: _idx,
            children: screens,
          ),
        ),
        // Баннер всегда в дереве — переключаем banner↔пусто через
        // AnimatedSwitcher, поэтому карточка плавно съезжает сверху при
        // появлении и так же плавно уезжает вверх при восстановлении сети.
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
                    subtitle: l.t('checking_connection'),
                    onDismiss: () => setState(() => _bannerDismissed = true),
                  ),
          ),
        ),
        // Нижний navbar — стекло рендерит пакет. Виджет .withImpeller сам
        // растягивается на весь экран (прозрачное тело) и ставит бар снизу
        // через alignment/margin, поэтому кладём его в Positioned.fill.
        // Появление: fade + короткий подъём (без пружины), не завязано на
        // размер бара, поэтому не ломает self-layout пакета.
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _navAnim,
              builder: (context, child) {
                final t = Curves.easeOutCubic.transform(_navAnim.value.clamp(0.0, 1.0));
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.translate(offset: Offset(0, 44 * (1 - t)), child: child),
                );
              },
              child: LiquidGlassBottomNavBar.withImpeller(
                items: items
                    .map((it) => LiquidGlassTabBarItem(
                          icon: it.inactive,
                          selectedIcon: it.active,
                          label: it.label,
                        ))
                    .toList(),
                selectedIndex: _idx,
                onChanged: _onTap,
                width: MediaQuery.of(context).size.width - 32,
                height: 64,
                margin: const EdgeInsets.only(bottom: 16),
                alignment: Alignment.bottomCenter,
                itemPadding: 6,
                // Стекло бара: приглушённое краевое свечение (низкий lightIntensity
                // + мягкий OpticalBorder) и более плотный фрост, чтобы иконки и
                // подписи читались на любом фоне.
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
                    // Прозрачное стекло — прозрачность НЕ глушим: лишь лёгкий тинт
                    // и subtle blur (он же чуть помогает читаемости фона).
                    color: isDark ? const Color(0x26000000) : const Color(0x26FFFFFF),
                    blur: const LiquidGlassBlur(sigmaX: 6, sigmaY: 6),
                  ),
                  refraction: const LiquidGlassRefraction(
                    distortion: 0.06,
                    distortionWidth: 24,
                    chromaticAberration: 0.0,
                  ),
                ),
                // Иконки: активная — контрастный акцент, неактивные приглушены.
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
                // Стеклянная капсула выбора: морфинг+рефракция пакета (Impeller),
                // плавное пружинное перемещение, деликатная дисторшн.
                pillStyle: LiquidGlassNavPillStyle(
                  mode: LiquidGlassPillMode.impellerOnly,
                  animated: true,
                  animationDuration: const Duration(milliseconds: 320),
                  animationCurve: Curves.easeOutCubic,
                  distortion: 0.06,
                  distortionWidth: 10,
                  // Чуть плотнее материал капсулы выбора → активный контент
                  // всегда читаем, но капсула остаётся стеклянной (не заливка).
                  color: isDark ? const Color(0x33FFFFFF) : const Color(0x59FFFFFF),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NavItem {
  final IconData inactive, active;
  final String label;
  _NavItem(this.inactive, this.active, this.label);
}

// ─────────────────────────────────────────────────────────
//  Lazy IndexedStack — строит вкладку при первом открытии
// ─────────────────────────────────────────────────────────
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
    // Список вкладок может измениться (например, появилась вкладка админа)
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

// ─────────────────────────────────────────────────────────
//  Offline Banner
// ─────────────────────────────────────────────────────────
class _OfflineBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDismiss;
  const _OfflineBanner({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topPad = MediaQuery.of(context).padding.top;
    // A calm liquid-glass pill instead of a harsh full-bleed red bar — matches
    // the app's nav-bar language (frosted blur, soft shadow, subtle red accent).
    // Slide/fade in-and-out is driven by the parent AnimatedSwitcher; a swipe-up
    // gesture dismisses it manually (onDismiss triggers the same exit animation).
    final glass = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.72);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topPad + 8, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Смахивание вверх — скрыть; вниз игнорируем.
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -80) onDismiss();
        },
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: cardShadow(isDark),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.card),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 11),
                  decoration: BoxDecoration(
                    color: glass,
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(
                      color: C.red.withValues(alpha: isDark ? 0.32 : 0.20),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Grabber — намёк, что окно можно смахнуть вверх.
                      Container(
                        width: 34, height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? C.darkText2 : C.text3)
                              .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: C.red.withValues(alpha: isDark ? 0.22 : 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(CupertinoIcons.wifi_slash,
                              size: 16, color: C.red),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: adaptiveText1(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Row(children: [
                                _PulsingDot(),
                                const SizedBox(width: 6),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: isDark ? C.darkText2 : C.text3,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        // Явная кнопка-крестик для тех, кто не догадается про свайп.
                        GestureDetector(
                          onTap: onDismiss,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              CupertinoIcons.xmark,
                              size: 15,
                              color: (isDark ? C.darkText2 : C.text3),
                            ),
                          ),
                        ),
                      ]),
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

// Мягко пульсирующая точка рядом с «Проверяем подключение…» — живой индикатор.
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(
          color: C.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}