import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/errors.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import '../../widgets/telegram_logo.dart';
import '../legal/privacy_policy_screen.dart';
import '../legal/terms_of_service_screen.dart';
import 'contact_screen.dart';
import 'settings_shared.dart';
import '../../utils/nav_guard.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;

    return SettingsSubScreen(
      title: l.t('about_section'),
      subtitle: l.t('about_section_sub'),
      footer: const _VersionLabel(),
      children: [
        SettingsGroup(children: [
          SettingsRow(
            pos: GroupPos.middle,
            icon: CupertinoIcons.doc_plaintext,
            iconBg: primary,
            title: l.t('tos_title'),
            sub: l.t('tos_view'),
            onTap: () => guardedPush(context,
              MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
          ),
          SettingsRow(
            pos: GroupPos.last,
            icon: CupertinoIcons.lock_shield,
            iconBg: primary,
            title: l.t('pp_title'),
            sub: l.t('pp_view'),
            onTap: () => guardedPush(context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
          ),
        ]),
        const SizedBox(height: 26),
        // Телеграм-логотип рисуется своим виджетом (фирменный цвет и глиф),
        // поэтому эта строка не через SettingsRow, но метрики те же.
        InsetGroup(children: [
          GroupRow(
            pos: GroupPos.last,
            color: Colors.transparent,
            separatorInset: 60,
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            onTap: () => guardedPush(context,
              MaterialPageRoute(builder: (_) => const ContactScreen())),
            child: Row(children: [
              const TelegramLogo(size: 30),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('contact_developer'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.4, color: adaptiveText1(context))),
                const SizedBox(height: 1),
                Text(l.t('contact_developer_sub'),
                  style: TextStyle(fontSize: 13, height: 1.3, color: adaptiveText3(context))),
              ])),
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(context).withValues(alpha: 0.8)),
            ]),
          ),
        ]),
      ],
    );
  }
}

class _VersionLabel extends StatefulWidget {
  const _VersionLabel();
  @override State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = info.version);
    } catch (e) {
      logError('AboutSettings.version', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final text = _version == null ? '' : 'Chatra $_version';
    return SizedBox(
      height: 20,
      child: Center(
        child: Tappable(
          onTap: _version == null
              ? null
              : () {
                  Clipboard.setData(ClipboardData(text: text));
                  showToast(context, l.t('copied'));
                },
          child: Text(text,
              style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
        ),
      ),
    );
  }
}
