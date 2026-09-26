import 'dart:async';
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
  @override
  State<AiLimitsScreen> createState() => _AiLimitsScreenState();
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
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q =
          AiQuota.fromJson(await context.read<ApiService>().getAiLimits());
      if (!mounted) return;
      if (q == null) {
        _fail();
        return;
      }
      setState(() {
        _quota = q;
        _loading = false;
        _refreshing = false;
      });
    } catch (_) {
      if (mounted) _fail();
    }
  }

  void _fail() {
    final hadData = _quota != null;
    setState(() {
      _loading = false;
      _refreshing = false;
    });
    // Если цифры на экране уже были, они остаются — но молча оставить их
    // значит соврать, что обновление прошло. Тост сообщает, что показано
    // старое значение.
    if (hadData)
      showToast(context, context.read<L10n>().t('connection_error'),
          error: true);
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
      icon: CupertinoIcons.sparkles,
      accent: Theme.of(context).colorScheme.primary,
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
        width: 44,
        height: 44,
        child: Center(
          child: busy
              ? CupertinoActivityIndicator(radius: 9, color: primary)
              : Icon(CupertinoIcons.arrow_clockwise, size: 20, color: primary),
        ),
      ),
    );
  }
}

/// Карточка лимита в духе Screen Time: крупное число и линейная шкала без
/// круговой диаграммы.
class _QuotaHero extends StatelessWidget {
  const _QuotaHero({required this.quota});

  final AiQuota quota;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final exhausted = quota.exhausted;
    final low = !exhausted &&
        !quota.unlimited &&
        (quota.left <= 5 ||
            (quota.limit > 0 && quota.left / quota.limit <= 0.15));
    final accent = exhausted
        ? C.red
        : low
            ? C.amberDk
            : primary;
    final fraction = quota.unlimited || quota.limit <= 0
        ? 1.0
        : (quota.left / quota.limit).clamp(0.0, 1.0);

    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            quota.unlimited
                ? l.t('ai_unlimited_badge')
                : l.t('ai_messages_left'),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: adaptiveText3(context),
                letterSpacing: -0.1)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(quota.unlimited ? '∞' : '${quota.left}',
              style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w700,
                  height: 0.95,
                  letterSpacing: -1.5,
                  color: quota.unlimited ? primary : accent,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (!quota.unlimited) ...[
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('/ ${quota.limit}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: adaptiveText3(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
          const Spacer(),
          Icon(
              quota.unlimited
                  ? CupertinoIcons.sparkles
                  : CupertinoIcons.bolt_fill,
              size: 22,
              color: accent),
        ]),
        const SizedBox(height: 18),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            backgroundColor: adaptiveSurface2(context),
            color: accent,
          ),
        ),
        if (quota.unlimited) ...[
          const SizedBox(height: 18),
          _Note(
              text: l.t('ai_unlimited_note'),
              color: primary,
              icon: CupertinoIcons.sparkles),
        ] else if (exhausted) ...[
          const SizedBox(height: 18),
          _Note(
              text: l.t('ai_exhausted_note'),
              color: C.red,
              icon: CupertinoIcons.exclamationmark_circle_fill),
        ] else if (low) ...[
          const SizedBox(height: 18),
          _Note(
              text: l.t('ai_low_note'),
              color: C.amberDk,
              icon: CupertinoIcons.exclamationmark_triangle_fill),
        ],
      ]),
    );
  }
}

/// Расход, потолок и время сброса — по строке на факт.
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
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.4,
                    color: adaptiveTextSoft(context)))),
        const SizedBox(width: 12),
        Text(value,
            style: TextStyle(
                fontSize: 17,
                letterSpacing: -0.4,
                color: adaptiveText3(context))),
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
        Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 9),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: color))),
      ]),
    );
  }
}

class _QuotaSkeleton extends StatefulWidget {
  const _QuotaSkeleton();
  @override
  State<_QuotaSkeleton> createState() => _QuotaSkeletonState();
}

class _QuotaSkeletonState extends State<_QuotaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = adaptiveSurface2(context);
    final content = Column(children: [
      _Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 108,
              height: 12,
              decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadii.chip))),
          const SizedBox(height: 14),
          Container(
              width: 92,
              height: 42,
              decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadii.tile))),
          const SizedBox(height: 20),
          Container(
              width: double.infinity,
              height: 7,
              decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(AppRadii.chip))),
        ]),
      ),
      const SizedBox(height: 22),
      InsetGroup(children: [
        for (var i = 0; i < 3; i++)
          GroupRow(
            pos: innerPos(i, 3),
            color: Colors.transparent,
            separatorInset: 16,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(children: [
              Container(
                  width: 120,
                  height: 12,
                  decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(AppRadii.chip))),
              const Spacer(),
              Container(
                  width: 34,
                  height: 12,
                  decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(AppRadii.chip))),
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
        Icon(CupertinoIcons.wifi_slash,
            size: 30, color: adaptiveText4(context)),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: adaptiveTextSoft(context))),
        const SizedBox(height: 16),
        AppButton.secondary(
            label: l.t('retry'), expand: false, onPressed: onRetry),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
            color: groupSeparator(context), width: hairline(context)),
        boxShadow: softShadow(isDark),
      ),
      child: Column(children: [child]),
    );
  }
}
