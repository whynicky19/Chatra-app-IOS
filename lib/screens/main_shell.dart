import 'dart:async';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/auth_provider.dart';
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
  int _idx = 0;
  late AnimationController _navAnim;

  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  @override
  void initState() {
    super.initState();
    _navAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 950));
    _navAnim.forward();

    Connectivity().checkConnectivity().then((results) {
      if (mounted) setState(() => _isOnline = _online(results));
    });
    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      if (mounted) setState(() => _isOnline = _online(results));
    });
  }

  static bool _online(List<ConnectivityResult> r) =>
      r.any((v) => v != ConnectivityResult.none);

  @override
  void dispose() {
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
        // IndexedStack keeps all screens mounted (state preserved) but only
        // paints the active one — hidden screens are offstage (no GPU cost).
        Positioned.fill(
          child: IndexedStack(
            index: _idx,
            children: screens,
          ),
        ),
        if (!_isOnline) Positioned(
          top: 0, left: 0, right: 0,
          child: _OfflineBanner(message: l.t('no_connection')),
        ),
        Positioned(
          left: 16, right: 16, bottom: 16,
          child: RepaintBoundary(
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _navAnim,
                curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
              ),
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 1.8), end: Offset.zero)
                    .animate(CurvedAnimation(parent: _navAnim, curve: Curves.elasticOut)),
                child: _LiquidGlassNavBar(
                  items: items,
                  selectedIndex: _idx,
                  onTap: _onTap,
                  isDark: isDark,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Liquid Glass Nav Bar
// ─────────────────────────────────────────────────────────
class _LiquidGlassNavBar extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final void Function(int) onTap;
  final bool isDark;

  const _LiquidGlassNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    required this.isDark,
  });

  static final _blur = ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.mirror);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          // Main depth shadow
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.45 : 0.18),
            blurRadius: 36,
            spreadRadius: -6,
            offset: const Offset(0, 14),
          ),
          // Primary ambient glow
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.14 : 0.10),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: _blur,
          child: Container(
            decoration: BoxDecoration(
              // Glass tint — lighter on light, darker on dark
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.11),
                        Colors.white.withOpacity(0.05),
                      ]
                    : [
                        Colors.white.withOpacity(0.78),
                        Colors.white.withOpacity(0.56),
                      ],
              ),
              borderRadius: BorderRadius.circular(32),
              // Glass rim
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.16)
                    : Colors.white.withOpacity(0.88),
                width: 0.8,
              ),
            ),
            child: Stack(alignment: Alignment.center, children: [
              // ── Specular highlight — top edge ──
              Positioned(
                top: 1, left: 20, right: 20, height: 1,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(isDark ? 0.30 : 0.95),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              // ── Nav items ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(items.length, (i) {
                    final sel = selectedIndex == i;
                    return GestureDetector(
                      onTap: () => onTap(i),
                      behavior: HitTestBehavior.opaque,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: sel ? 0.0 : 1.0, end: sel ? 1.0 : 0.0),
                        duration: Duration(milliseconds: sel ? 380 : 120),
                        curve: Curves.easeOutBack,
                        builder: (_, t, __) {
                          final p = t.clamp(0.0, 1.0);
                          return Transform.scale(
                            scale: 1.0 + 0.055 * p,
                            child: _GlassTabPill(
                              item: items[i],
                              progress: p,
                              isDark: isDark,
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Glass Tab Pill  (active item)
// ─────────────────────────────────────────────────────────
class _GlassTabPill extends StatelessWidget {
  final _NavItem item;
  final double progress; // 0 = unselected → 1 = selected
  final bool isDark;

  const _GlassTabPill({
    required this.item,
    required this.progress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final sel = progress > 0.5;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8.0 + 12.0 * progress,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        // Active pill: primary glass gradient
        gradient: progress > 0.01
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withOpacity(0.82 * progress),
                  Theme.of(context).colorScheme.secondary.withOpacity(0.68 * progress),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(22),
        // Rim highlight on active pill
        border: progress > 0.01
            ? Border.all(
                color: Colors.white.withOpacity(0.32 * progress),
                width: 0.8,
              )
            : null,
        boxShadow: progress > 0.3
            ? [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.42 * progress),
                  blurRadius: 18,
                  spreadRadius: -3,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.20 * progress),
                  blurRadius: 8,
                  spreadRadius: -1,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          sel ? item.active : item.inactive,
          size: 22,
          color: progress > 0.01
              ? Color.lerp(
                  isDark ? Colors.white.withOpacity(0.45) : C.text4,
                  Colors.white,
                  progress,
                )
              : (isDark ? Colors.white.withOpacity(0.45) : C.text4),
        ),
        if (progress > 0.5) ...[
          SizedBox(width: 6 * progress),
          Opacity(
            opacity: ((progress - 0.5) * 2).clamp(0.0, 1.0),
            child: Text(
              item.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
//  Offline Banner
// ─────────────────────────────────────────────────────────
class _OfflineBanner extends StatelessWidget {
  final String message;
  const _OfflineBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        color: const Color(0xFFB71C1C),
        padding: EdgeInsets.fromLTRB(16, topPad + 6, 16, 8),
        child: Row(children: [
          const Icon(CupertinoIcons.wifi_slash, size: 16, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}