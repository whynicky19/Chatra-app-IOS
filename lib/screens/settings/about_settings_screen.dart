import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/telegram_logo.dart';
import '../legal/privacy_policy_screen.dart';
import '../legal/terms_screen.dart';
import 'contact_screen.dart';
import 'settings_shared.dart';

/// Раздел «О приложении»: правовые документы и связь с разработчиком.
/// Правила сообщества и политика конфиденциальности обязаны быть доступны из
/// приложения (App Store Guideline 1.2 / 5.1.1), поэтому раздел не прячем
/// глубже одного уровня.
class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SettingsSubScreen(
      title: l.t('about_section'),
      subtitle: l.t('about_section_sub'),
      children: [
        SettingsActionCard(
          icon: CupertinoIcons.checkmark_shield,
          iconBg: primary,
          title: l.t('terms_title'),
          sub: l.t('terms_view'),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TermsScreen())),
        ),
        const SizedBox(height: 16),
        SettingsActionCard(
          icon: CupertinoIcons.lock_shield,
          iconBg: primary,
          title: l.t('pp_title'),
          sub: l.t('pp_view'),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
        ),
        const SizedBox(height: 16),
        // Связь с разработчиком — с фирменной иконкой Telegram, поэтому
        // собственная карточка, а не SettingsActionCard.
        GestureDetector(
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ContactScreen())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: cardShadow(isDark),
            ),
            child: Row(children: [
              const TelegramLogo(size: 32),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('contact_developer'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
                const SizedBox(height: 1),
                Text(l.t('contact_developer_sub'),
                  style: const TextStyle(fontSize: 13, color: C.text4)),
              ])),
              const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
            ]),
          ),
        ),
      ],
    );
  }
}
