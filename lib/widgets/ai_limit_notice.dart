import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/l10n_provider.dart';
import '../theme/app_theme.dart';
import '../utils/ai_quota.dart';

/// Сообщение «дневной лимит исчерпан» над полем ввода — показывается вместо
/// возможности писать, пока квота не обнулится.
class AiLimitNotice extends StatelessWidget {
  final AiQuota quota;
  const AiLimitNotice({super.key, required this.quota});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: adaptiveBorder(context).withValues(alpha: 0.6), width: 0.5),
        boxShadow: softShadow(isDark),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: C.amber.withValues(alpha: isDark ? 0.22 : 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(CupertinoIcons.clock_fill, size: 15, color: C.amberDk),
        ),
        const SizedBox(width: 11),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('ai_limit_reached_title'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: adaptiveText1(context), height: 1.3)),
          const SizedBox(height: 2),
          Text(_subtitle(l),
            style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4)),
        ])),
      ]),
    );
  }

  String _subtitle(L10n l) {
    final base = l.t('ai_limit_reached_sub').replaceAll('{limit}', '${quota.limit}');
    final d = quota.untilReset;
    if (d == null) return '$base ${l.t('ai_reset_daily')}.';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final left = h > 0
        ? '$h${l.t('hour_short')} $m${l.t('minute_short')}'
        : '$m${l.t('minute_short')}';
    return '$base ${l.t('ai_reset_in')} $left.';
  }
}
