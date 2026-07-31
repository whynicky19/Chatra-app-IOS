import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../providers/org_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tappable.dart';
import '../../widgets/brand_gradient.dart';
import '../../utils/haptics.dart';

class OrgSelectScreen extends StatefulWidget {
  const OrgSelectScreen({super.key});
  @override
  State<OrgSelectScreen> createState() => _OrgSelectScreenState();
}

class _OrgSelectScreenState extends State<OrgSelectScreen> {
  OrgType? _picked;

  static const _tealGrad  = [Color(0xFF006475), Color(0xFF009AAF)];
  static const _amberGrad = [Color(0xFFB45309), Color(0xFFF59E0B)];

  Color get _accent => _picked == OrgType.school ? C.amber : C.teal;

  void _pick(OrgType type) {
    if (_picked == type) return;
    hapticSelection();
    setState(() => _picked = type);
  }

  Future<void> _continue() async {
    final picked = _picked;
    if (picked == null) return;
    hapticMedium();
    await context.read<OrgProvider>().select(picked);
  }

  Widget _reveal(int step, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 420 + step * 110),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final hasPick = _picked != null;
    final l = context.watch<L10n>();

    return Scaffold(
      backgroundColor: isDark ? C.darkBg : C.bg,
      body: Stack(children: [
        SafeArea(child: Column(children: [
          Expanded(child: Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _reveal(1, SizedBox(
                  width: 108, height: 108,
                  child: BrandGradient.mask(
                    child: Image.asset(
                      'assets/logo-icon.png',
                      width: 108, height: 108,
                      fit: BoxFit.contain,
                    ),
                  ),
                )),
                const SizedBox(height: 28),

                _reveal(2, Column(children: [
                  Text(l.t('welcome'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.12, color: adaptiveText1(context))),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.12,
                      color: hasPick ? _accent : adaptiveText1(context)),
                    child: Text(l.t('org_brand_line'), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 10),
                  Text(l.t('org_subtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
                ])),
                const SizedBox(height: 36),

                _reveal(3, _OrgCard(
                  title: l.t('org_university'),
                  subtitle: l.t('org_uni_sub'),
                  asset: 'assets/uni-logo.png',
                  accent: C.teal,
                  gradient: _tealGrad,
                  selected: _picked == OrgType.university,
                  onTap: () => _pick(OrgType.university),
                )),
                const SizedBox(height: 14),
                _reveal(4, _OrgCard(
                  title: l.t('org_school'),
                  subtitle: l.t('org_school_sub'),
                  icon: CupertinoIcons.book_fill,
                  accent: C.amber,
                  gradient: _amberGrad,
                  selected: _picked == OrgType.school,
                  onTap: () => _pick(OrgType.school),
                )),
              ]),
            ),
          ))),

          _reveal(5, Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _GlassButton(
                  active: hasPick,
                  accent: _accent,
                  label: l.t('org_continue'),
                  onPressed: hasPick ? _continue : null,
                ),
                const SizedBox(height: 12),
                Text(l.t('org_change_hint'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: C.text4)),
              ]),
            ),
          )),
        ])),
      ]),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final bool active;
  final Color accent;
  final String label;
  final VoidCallback? onPressed;
  const _GlassButton({
    required this.active,
    required this.accent,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 320.0;
      return LiquidGlassButton(
        label: label,
        onPressed: onPressed,
        width: w,
        height: 54,
        foregroundColor: active ? Colors.white : C.text4,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        style: LiquidGlassStyle(
          shape: const LiquidGlassShape.roundedRectangle(cornerRadius: 16, borderWidth: 0),
          appearance: LiquidGlassAppearance(
            color: active
                ? accent.withValues(alpha: 0.88)
                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.5)),
            blur: const LiquidGlassBlur(sigmaX: 8, sigmaY: 8),
          ),
          refraction: const LiquidGlassRefraction(
            distortion: 0.08,
            distortionWidth: 20,
            chromaticAberration: 0.0,
          ),
        ),
      );
    });
  }
}

class _OrgCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  final String? asset;
  final Color accent;
  final List<Color> gradient;
  final bool selected;
  final VoidCallback onTap;

  const _OrgCard({
    required this.title,
    required this.subtitle,
    this.icon,
    this.asset,
    required this.accent,
    required this.gradient,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_OrgCard> createState() => _OrgCardState();
}

class _OrgCardState extends State<_OrgCard> {
  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final selected = widget.selected;
    final accent   = widget.accent;

    return Tappable(
      onTap: widget.onTap,
      scale: 0.975,
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(accent.withValues(alpha: isDark ? 0.10 : 0.05), Theme.of(context).colorScheme.surface)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
            boxShadow: cardShadow(isDark),
          ),
          child: Row(children: [
            Container(
              width: 54, height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: widget.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: widget.asset != null
                  ? Padding(padding: const EdgeInsets.all(13),
                      child: Image.asset(widget.asset!, color: Colors.white, fit: BoxFit.contain))
                  : Icon(widget.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: adaptiveText1(context))),
              const SizedBox(height: 2),
              Text(widget.subtitle, style: const TextStyle(fontSize: 13, color: C.text4)),
            ])),
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: 26, height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accent : Colors.transparent,
                border: selected ? null : Border.all(color: adaptiveBorder(context), width: 1.6),
              ),
              child: selected
                  ? const Icon(CupertinoIcons.checkmark_alt, size: 16, color: Colors.white)
                  : null,
            ),
          ]),
        ),
    );
  }
}

