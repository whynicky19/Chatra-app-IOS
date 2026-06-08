import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/org_provider.dart';

class OrgSelectScreen extends StatefulWidget {
  const OrgSelectScreen({super.key});
  @override
  State<OrgSelectScreen> createState() => _OrgSelectScreenState();
}

class _OrgSelectScreenState extends State<OrgSelectScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _select(OrgType type) async {
    await context.read<OrgProvider>().select(type);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(children: [
        Container(decoration: BoxDecoration(gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0A0A0F), const Color(0xFF12121A)]
              : [const Color(0xFF1E293B), const Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ))),

        SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: FadeTransition(opacity: _fade, child: SlideTransition(position: _slide,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Добро пожаловать',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text('Выберите тип вашей организации',
                  style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 48),

              _OrgCard(
                title: 'Университет',
                subtitle: 'Высшее образование',
                icon: Icons.school_rounded,
                primaryColor: const Color(0xFF00B1C9),
                gradientColors: const [Color(0xFF006475), Color(0xFF009AAF)],
                onTap: () => _select(OrgType.university),
              ),
              const SizedBox(height: 16),

              _OrgCard(
                title: 'Школа',
                subtitle: 'Среднее образование',
                icon: Icons.menu_book_rounded,
                primaryColor: const Color(0xFFF59E0B),
                gradientColors: const [Color(0xFFB45309), Color(0xFFF59E0B)],
                onTap: () => _select(OrgType.school),
              ),
            ]),
          )),
        ))),
      ]),
    );
  }
}

class _OrgCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color primaryColor;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _OrgCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryColor,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: primaryColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: primaryColor.withOpacity(0.15), blurRadius: 24, offset: const Offset(0, 8)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradientColors),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.6))),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, color: primaryColor, size: 18),
        ]),
      ),
    );
  }
}
