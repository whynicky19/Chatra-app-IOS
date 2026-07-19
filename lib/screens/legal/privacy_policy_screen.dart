import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';

/// Дата последнего изменения политики. Обновляй при правках текста.
const String _kPrivacyUpdated = '19.07.2026';

/// Политика конфиденциальности. Реальные разделы (что собираем, зачем, кому
/// передаём, права, дети, контакты) — требование App Store для метаданных и
/// экрана в приложении. Оформление в стиле приложения (карточки + иконки).
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(IconData, String, String)>[
    (CupertinoIcons.doc_text, 'pp_collect_title', 'pp_collect_body'),
    (CupertinoIcons.gear_alt, 'pp_use_title', 'pp_use_body'),
    (CupertinoIcons.arrow_2_squarepath, 'pp_share_title', 'pp_share_body'),
    (CupertinoIcons.lock_shield, 'pp_store_title', 'pp_store_body'),
    (CupertinoIcons.checkmark_seal, 'pp_rights_title', 'pp_rights_body'),
    (CupertinoIcons.person_crop_circle, 'pp_children_title', 'pp_children_body'),
    (CupertinoIcons.mail, 'pp_contact_title', 'pp_contact_body'),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // ── Back + title ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(child: Text(l.t('pp_title'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: adaptiveText1(context), letterSpacing: -0.3))),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              // Hero
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(CupertinoIcons.lock_shield_fill, size: 28, color: primary),
              ),
              const SizedBox(height: 14),
              Text('${l.t('pp_updated_label')}: $_kPrivacyUpdated',
                style: const TextStyle(fontSize: 12.5, color: C.text4, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(l.t('pp_intro'),
                style: TextStyle(fontSize: 15, height: 1.55, color: adaptiveText1(context))),
              const SizedBox(height: 20),

              // Sections
              for (final s in _sections) ...[
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
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800,
              color: adaptiveText1(context), letterSpacing: -0.2))),
        ]),
        const SizedBox(height: 12),
        Text(body, style: const TextStyle(fontSize: 14, height: 1.55, color: C.text3)),
      ]),
    );
  }
}
