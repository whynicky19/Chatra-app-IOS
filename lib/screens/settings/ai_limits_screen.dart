import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/ai_quota.dart';
import 'settings_shared.dart';

/// Экран «AI лимит»: сколько сообщений израсходовано за сутки и когда сброс.
class AiLimitsScreen extends StatefulWidget {
  const AiLimitsScreen({super.key});
  @override State<AiLimitsScreen> createState() => _AiLimitsScreenState();
}

class _AiLimitsScreenState extends State<AiLimitsScreen> {
  AiQuota? _quota;
  bool _loading = true;
  bool _failed = false;
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
      setState(() { _quota = q; _loading = false; _failed = q == null; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return SettingsSubScreen(
      title: l.t('ai_limit_section'),
      subtitle: l.t('ai_limit_section_sub'),
      children: [
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 60),
            child: Center(child: CupertinoActivityIndicator(radius: 12)))
        else if (_failed || _quota == null)
          _InfoCard(icon: CupertinoIcons.wifi_slash, text: l.t('connection_error'))
        else
          _QuotaCard(quota: _quota!),
      ],
    );
  }
}

class _QuotaCard extends StatelessWidget {
  final AiQuota quota;
  const _QuotaCard({required this.quota});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    final exhausted = quota.exhausted;
    final low = !exhausted && quota.left <= 5;
    final accent = exhausted ? C.red : low ? C.amberDk : primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [secondary, primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(CupertinoIcons.sparkles, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(l.t('ai_limit_section'),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context)))),
          if (quota.unlimited)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.card)),
              child: Text(l.t('ai_unlimited_badge'),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: primary)),
            ),
        ]),

        if (quota.unlimited) ...[
          const SizedBox(height: 16),
          Text(l.t('ai_unlimited_note'),
            style: const TextStyle(fontSize: 13, color: C.text4, height: 1.45)),
        ] else ...[
          const SizedBox(height: 20),

          // Шкала расхода
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: quota.progress),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LayoutBuilder(builder: (context, box) {
              return Stack(children: [
                Container(
                  height: 10, width: double.infinity,
                  decoration: BoxDecoration(
                    color: adaptiveSurface2(context),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                Container(
                  height: 10,
                  width: (box.maxWidth * value).clamp(value > 0 ? 10.0 : 0.0, box.maxWidth),
                  decoration: BoxDecoration(
                    gradient: exhausted || low
                      ? null
                      : LinearGradient(colors: [secondary, primary]),
                    color: exhausted || low ? accent : null,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ]);
            }),
          ),

          const SizedBox(height: 14),

          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text('${quota.used} / ${quota.limit}',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
                letterSpacing: -0.6, color: adaptiveText1(context))),
            const SizedBox(width: 7),
            Text(l.t('ai_used_suffix'),
              style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
          ]),

          const SizedBox(height: 3),
          Text('${l.t('ai_messages_left')}: ${quota.left}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: exhausted || low ? accent : C.text3)),

          const SizedBox(height: 16),
          Divider(height: 1, thickness: 0.5, color: adaptiveBorder(context).withValues(alpha: 0.6)),
          const SizedBox(height: 14),

          Row(children: [
            const Icon(CupertinoIcons.clock, size: 15, color: C.text4),
            const SizedBox(width: 8),
            Expanded(child: Text(
              _resetLabel(l),
              style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500),
            )),
          ]),
        ],
      ]),
    );
  }

  String _resetLabel(L10n l) {
    final d = quota.untilReset;
    if (d == null) return l.t('ai_reset_daily');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final left = h > 0 ? '$h${l.t('hour_short')} $m${l.t('minute_short')}' : '$m${l.t('minute_short')}';
    return '${l.t('ai_reset_in')} $left';
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: cardShadow(isDark),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: C.text4),
        const SizedBox(width: 10),
        Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13, color: C.text4, height: 1.45))),
      ]),
    );
  }
}
