import 'package:flutter/material.dart';

import 'detail_page_theme.dart';

/// Линейный результат без круговой диаграммы: число остаётся главным,
/// а тонкая шкала даёт быстрый визуальный контекст.
class ScoreSummary extends StatelessWidget {
  const ScoreSummary({
    super.key,
    required this.score,
    required this.maxScore,
    required this.accentColor,
  });

  final num score;
  final num maxScore;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fraction = maxScore <= 0
        ? 0.0
        : (score.toDouble() / maxScore.toDouble()).clamp(0.0, 1.0);
    final percent = (fraction * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: isDark ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$score',
              style: TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w700,
                height: 0.95,
                letterSpacing: -1.2,
                color: detailText1(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(width: 5),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('/ $maxScore',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: detailText2(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
          const Spacer(),
          Text('$percent%',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: accentColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: accentColor.withValues(alpha: 0.16),
            color: accentColor,
          ),
        ),
      ]),
    );
  }
}
