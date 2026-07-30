import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';

/// Shared layout for legal documents (privacy policy, terms of service):
/// header icon, "updated" line, intro paragraph and a list of section cards.
class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({
    super.key,
    required this.titleKey,
    required this.headerIcon,
    required this.updated,
    required this.introKey,
    required this.sections,
  });

  final String titleKey;
  final IconData headerIcon;
  final String updated;
  final String introKey;

  /// (icon, title key, body key) for each card.
  final List<(IconData, String, String)> sections;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(child: Text(l.t(titleKey),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                  color: adaptiveText1(context), letterSpacing: -0.3))),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(headerIcon, size: 28, color: primary),
              ),
              const SizedBox(height: 14),
              Text('${l.t('pp_updated_label')}: $updated',
                style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(l.t(introKey),
                style: TextStyle(fontSize: 15, height: 1.55, color: adaptiveText1(context))),
              const SizedBox(height: 20),

              for (final s in sections) ...[
                _card(context, isDark, primary, s.$1, l.t(s.$2), l.t(s.$3)),
                const SizedBox(height: 12),
              ],
            ],
          )),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, bool isDark, Color primary,
      IconData icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? C.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
              color: adaptiveText1(context), letterSpacing: -0.2))),
        ]),
        const SizedBox(height: 12),
        Text(body, style: TextStyle(fontSize: 15, height: 1.55, color: adaptiveText2(context))),
      ]),
    );
  }
}
