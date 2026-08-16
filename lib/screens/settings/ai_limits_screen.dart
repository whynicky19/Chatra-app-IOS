import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ai_quota.dart';
import '../../widgets/app_button.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'settings_shared.dart';

/// Экран «AI лимит»: сколько сообщений осталось на сегодня и когда сброс.
class AiLimitsScreen extends StatefulWidget {
  const AiLimitsScreen({super.key});
  @override State<AiLimitsScreen> createState() => _AiLimitsScreenState();
}

class _AiLimitsScreenState extends State<AiLimitsScreen> {
  AiQuota? _quota;
  bool _loading = true;
  bool _refreshing = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // Обратный отсчёт до сброса пересчитываем раз в минуту.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _ticker?.cancel(); super.dispose(); }

  Future<void> _load() async {
    try {
      final q = AiQuota.fromJson(await context.read<ApiService>().getAiLimits());
      if (!mounted) return;
      if (q == null) { _fail(); return; }
      setState(() { _quota = q; _loading = false; _refreshing = false; });
    } catch (_) {
      if (mounted) _fail();
    }
  }

  void _fail() {
    final hadData = _quota != null;
    setState(() { _loading = false; _refreshing = false; });
    // Если цифры на экране уже были, они остаются — но молча оставить их
    // значит соврать, что обновление прошло. Тост сообщает, что показано
    // старое значение.
    if (hadData) showToast(context, context.read<L10n>().t('connection_error'), error: true);
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final quota = _quota;

    return SettingsSubScreen(
      title: l.t('ai_limit_section'),
      subtitle: l.t('ai_limit_section_sub'),
      action: _RefreshAction(busy: _refreshing || _loading, onTap: _refresh),
      children: [
        if (_loading)
          const _QuotaSkeleton()
        else if (quota == null)
          _ErrorCard(text: l.t('connection_error'), onRetry: _refresh)
        else ...[
          _QuotaHero(quota: quota),
          const SizedBox(height: 22),
          _StatGroup(quota: quota),
          SettingsFooter(l.t('ai_limit_footer')),
        ],
      ],
    );
  }
}

class _RefreshAction extends StatelessWidget {
  const _RefreshAction({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final l = context.watch<L10n>();
    return Tappable(
      onTap: busy ? null : onTap,
      label: l.t('refresh'),
      child: SizedBox(
        width: 44, height: 44,
        child: Center(
          child: busy
              ? CupertinoActivityIndicator(radius: 9, color: primary)
              : Icon(CupertinoIcons.arrow_clockwise, size: 20, color: primary),
        ),
      ),
    );
  }
}

/// Карточка-герой: кольцо остатка и, если остаток на исходе, строка-предупреждение.
class _QuotaHero extends StatelessWidget {
  const _QuotaHero({required this.quota});

  final AiQuota quota;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    final exhausted = quota.exhausted;
    final low = !exhausted && !quota.unlimited &&
        (quota.left <= 5 || (quota.limit > 0 && quota.left / quota.limit <= 0.15));
    final accent = exhausted ? C.red : low ? C.amberDk : primary;

    return _Card(
      child: Column(children: [
        if (quota.unlimited)
          _RingFrame(
            painter: _RingPainter(
              value: 1,
              track: adaptiveSurface2(context),
              gradient: [secondary, primary],
              full: true,
            ),
            child: _UnlimitedCenter(accent: primary),
          )
        else
          _AnimatedRing(quota: quota, accent: accent, gradient: [secondary, primary], flat: exhausted || low),

        if (quota.unlimited) ...[
          const SizedBox(height: 18),
          _Note(text: l.t('ai_unlimited_note'), color: primary, icon: CupertinoIcons.sparkles),
        ] else if (exhausted) ...[
          const SizedBox(height: 18),
          _Note(text: l.t('ai_exhausted_note'), color: C.red, icon: CupertinoIcons.exclamationmark_circle_fill),
        ] else if (low) ...[
          const SizedBox(height: 18),
          _Note(text: l.t('ai_low_note'), color: C.amberDk, icon: CupertinoIcons.exclamationmark_triangle_fill),
        ],
      ]),
    );
  }
}

/// Кольцо и число оживают одним общим прогрессом `t` — иначе дуга и цифра
/// приходят к финалу вразнобой.
class _AnimatedRing extends StatelessWidget {
  const _AnimatedRing({required this.quota, required this.accent, required this.gradient, required this.flat});

  final AiQuota quota;
  final Color accent;
  final List<Color> gradient;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final fraction = quota.limit > 0 ? (quota.left / quota.limit).clamp(0.0, 1.0) : 0.0;
    final track = quota.exhausted
        ? C.red.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.12)
        : adaptiveSurface2(context);

    Widget ring(double t) => _RingFrame(
      painter: _RingPainter(
        value: fraction * t,
        track: track,
        gradient: flat ? null : gradient,
        solid: flat ? accent : null,
      ),
      child: _RingCenter(
        value: (quota.left * t).round(),
        label: l.t('ai_messages_left'),
        color: flat ? accent : adaptiveText1(context),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return ring(1);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => ring(t),
    );
  }
}

class _RingFrame extends StatelessWidget {
  const _RingFrame({required this.painter, required this.child});

  final CustomPainter painter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 178, height: 178,
      child: CustomPaint(
        painter: painter,
        child: Center(child: child),
      ),
    );
  }
}

class _RingCenter extends StatelessWidget {
  const _RingCenter({required this.value, required this.label, required this.color});

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$value',
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.6, height: 1, color: color)),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w500, color: adaptiveText3(context))),
      ),
    ]);
  }
}

class _UnlimitedCenter extends StatelessWidget {
  const _UnlimitedCenter({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('∞', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700, height: 1, color: accent)),
      const SizedBox(height: 6),
      Text(l.t('ai_unlimited_badge'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: adaptiveText3(context))),
    ]);
  }
}

/// Кольцо остатка: серая дорожка на весь круг и поверх неё дуга остатка.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    this.gradient,
    this.solid,
    this.full = false,
  });

  /// Доля ОСТАТКА, 0..1.
  final double value;
  final Color track;
  final List<Color>? gradient;
  final Color? solid;

  /// Замкнутое кольцо (безлимит) — рисуется целиком, без скруглённых торцов.
  final bool full;

  static const double _stroke = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(center, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = track);

    if (value <= 0) return;

    final sweep = 2 * math.pi * value.clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = full ? StrokeCap.butt : StrokeCap.round;

    final g = gradient;
    if (g != null) {
      // ЛИНЕЙНЫЙ, а не SweepGradient. У кругового градиента цвет — функция
      // угла, поэтому на 12 часах, где начало дуги встречается с её концом,
      // сходятся два РАЗНЫХ конца шкалы: у замкнутого кольца это давало
      // видимый стык, а у почти полной дуги — заметный перепад между
      // сближающимися торцами. Симметричные стопы стык не убирают: цвет
      // сходится, но производная ломается, и глаз всё равно ловит полосу
      // (эффект Маха). У линейного градиента цвет — функция ТОЧКИ, а не угла:
      // в месте встречи это буквально одна и та же точка, разрыв невозможен
      // ни при каком заполнении.
      paint.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: g,
      ).createShader(rect);
    } else {
      paint.color = solid ?? track;
    }

    canvas.drawArc(rect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.solid != solid || old.gradient != gradient;
}

/// Цифры под кольцом: расход, потолок и время сброса — по строке на факт.
class _StatGroup extends StatelessWidget {
  const _StatGroup({required this.quota});

  final AiQuota quota;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final rows = <({String label, String value})>[
      (label: l.t('ai_used_label'), value: '${quota.used}'),
      // Потолок и время сброса имеют смысл только там, где лимит есть:
      // безлимитному аккаунту «Сброс через 6ч» ничего не сообщает.
      if (!quota.unlimited) ...[
        (label: l.t('ai_daily_limit_label'), value: '${quota.limit}'),
        _resetRow(l),
      ],
    ];

    return InsetGroup(children: [
      for (var i = 0; i < rows.length; i++)
        _StatRow(
          pos: innerPos(i, rows.length),
          label: rows[i].label,
          value: rows[i].value,
        ),
    ]);
  }

  ({String label, String value}) _resetRow(L10n l) {
    final d = quota.untilReset;
    if (d == null) {
      return (label: l.t('ai_reset_label'), value: l.t('ai_reset_daily_short'));
    }
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0 && m == 0) {
      return (label: l.t('ai_reset_row'), value: l.t('ai_reset_less_minute'));
    }
    final value = h > 0
        ? '$h${l.t('hour_short')} $m${l.t('minute_short')}'
        : '$m${l.t('minute_short')}';
    return (label: l.t('ai_reset_row'), value: value);
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.pos, required this.label, required this.value});

  final GroupPos pos;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 16,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4,
                color: adaptiveTextSoft(context)))),
        const SizedBox(width: 12),
        Text(value,
            style: TextStyle(fontSize: 17, letterSpacing: -0.4, color: adaptiveText3(context))),
      ]),
    );
  }
}

/// Строка-статус под кольцом (кончается лимит / исчерпан / безлимит).
class _Note extends StatelessWidget {
  const _Note({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 9),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: color))),
      ]),
    );
  }
}

class _QuotaSkeleton extends StatefulWidget {
  const _QuotaSkeleton();
  @override State<_QuotaSkeleton> createState() => _QuotaSkeletonState();
}

class _QuotaSkeletonState extends State<_QuotaSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fill = adaptiveSurface2(context);
    final content = Column(children: [
      _Card(child: SizedBox(
        width: 178, height: 178,
        child: CustomPaint(painter: _RingPainter(value: 0, track: fill)),
      )),
      const SizedBox(height: 22),
      InsetGroup(children: [
        for (var i = 0; i < 3; i++)
          GroupRow(
            pos: innerPos(i, 3),
            color: Colors.transparent,
            separatorInset: 16,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              Container(width: 120, height: 12,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadii.chip))),
              const Spacer(),
              Container(width: 34, height: 12,
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadii.chip))),
            ]),
          ),
      ]),
    ]);

    if (MediaQuery.disableAnimationsOf(context)) return content;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.8)
          .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: content,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return _Card(
      child: Column(children: [
        Icon(CupertinoIcons.wifi_slash, size: 30, color: adaptiveText4(context)),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveTextSoft(context))),
        const SizedBox(height: 16),
        AppButton.secondary(label: l.t('retry'), expand: false, onPressed: onRetry),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: groupSeparator(context), width: hairline(context)),
      ),
      child: Column(children: [child]),
    );
  }
}
