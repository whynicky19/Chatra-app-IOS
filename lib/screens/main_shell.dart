import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _navAnim = AnimationController(vsync: this, duration: Duration(milliseconds: 600));
    _navAnim.forward();
  }

  @override
  void dispose() { _navAnim.dispose(); super.dispose(); }

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
    final navBg = isDark ? Color(0xFF111B1E) : Colors.white;
    final shadow = isDark ? Colors.black38 : Colors.black12;

    final screens = <Widget>[
      HomeScreen(), ChatsScreen(), AiScreen(),
      if (isAdmin) AdminScreen(),
      SettingsScreen(),
    ];

    final items = <_NavItem>[
      _NavItem(Icons.school_outlined, Icons.school_rounded, l.t('nav_classes')),
      _NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, l.t('nav_chats')),
      _NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome, l.t('nav_ai')),
      if (isAdmin) _NavItem(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, l.t('nav_admin')),
      _NavItem(Icons.settings_outlined, Icons.settings_rounded, l.t('nav_settings')),
    ];

    if (_idx >= screens.length) _idx = 0;

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: IndexedStack(index: _idx, children: screens)),
        // Floating nav bar
        Positioned(left: 16, right: 16, bottom: 16,
          child: SlideTransition(
            position: Tween<Offset>(begin: Offset(0, 2), end: Offset.zero)
                .animate(CurvedAnimation(parent: _navAnim, curve: Curves.elasticOut)),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: navBg,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [BoxShadow(color: shadow, blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(items.length, (i) {
                  final sel = _idx == i;
                  return GestureDetector(
                    onTap: () => _onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: sel ? 0.0 : 1.0, end: sel ? 1.0 : 0.0),
                      duration: Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, __) => Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 + 14 * t, vertical: 10),
                        decoration: BoxDecoration(
                          color: Color.lerp(Colors.transparent, C.teal, t),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(sel ? items[i].active : items[i].inactive,
                            color: Color.lerp(isDark ? C.text4 : C.text4, Colors.white, t),
                            size: 22),
                          if (t > 0.5) ...[
                            SizedBox(width: 6 * t),
                            Opacity(opacity: (t - 0.5) * 2,
                              child: Text(items[i].label,
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700))),
                          ],
                        ]),
                      ),
                    ),
                  );
                }),
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
