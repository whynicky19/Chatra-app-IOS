import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/telegram_logo.dart';
import '../../widgets/toast.dart';
import '../../utils/haptics.dart';
import 'settings_shared.dart';

const String kDeveloperTelegramUrl = 'https://t.me/whynickyy';

String? get _telegramHandle {
  final path = Uri.parse(kDeveloperTelegramUrl).pathSegments;
  if (path.length != 1) return null;
  return RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(path.first)
      ? path.first
      : null;
}

String get _telegramLabel {
  final handle = _telegramHandle;
  if (handle != null) return '@$handle';
  final uri = Uri.parse(kDeveloperTelegramUrl);
  return '${uri.host}${uri.path}';
}

const _telegramBlue = Color(0xFF229ED9);

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  Future<void> _openTelegram(BuildContext context) async {
    hapticLight();
    final handle = _telegramHandle;
    for (final uri in [
      if (handle != null) Uri.parse('tg://resolve?domain=$handle'),
      Uri.parse(kDeveloperTelegramUrl),
    ]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (!context.mounted) return;
    showToast(context, context.read<L10n>().t('telegram_open_error'));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return SettingsSubScreen(
      title: l.t('contact_developer'),
      subtitle: l.t('contact_page_desc'),
      children: [
        SettingsGroup(children: [
          GroupRow(
            pos: GroupPos.last,
            color: Colors.transparent,
            onTap: () => _openTelegram(context),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(children: [
              const TelegramLogo(size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Telegram',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.4,
                              color: adaptiveTextSoft(context))),
                      const SizedBox(height: 2),
                      Text(_telegramLabel,
                          style: TextStyle(
                              fontSize: 13, color: adaptiveText3(context))),
                    ]),
              ),
              Text(l.t('write_telegram'),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _telegramBlue)),
            ]),
          ),
        ]),
      ],
    );
  }
}
