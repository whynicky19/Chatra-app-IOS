import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tappable.dart';
import '../../widgets/telegram_logo.dart';
import '../../widgets/toast.dart';

const String kDeveloperTelegramUrl = 'https://t.me/whynickyy';

String? get _telegramHandle {
  final path = Uri.parse(kDeveloperTelegramUrl).pathSegments;
  if (path.length != 1) return null;
  return RegExp(r'^[A-Za-z0-9_]{5,32}$').hasMatch(path.first) ? path.first : null;
}

String get _telegramLabel {
  final handle = _telegramHandle;
  if (handle != null) return '@$handle';
  final uri = Uri.parse(kDeveloperTelegramUrl);
  return '${uri.host}${uri.path}';
}

const _telegramBlue = Color(0xFF229ED9);

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});
  @override State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> with SingleTickerProviderStateMixin {
  late AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() { _entry.dispose(); super.dispose(); }

  Widget _animated(Widget child, double start, double end) {
    final anim = CurvedAnimation(parent: _entry, curve: Interval(start, end, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  Future<void> _openTelegram() async {
    HapticFeedback.lightImpact();
    final handle = _telegramHandle;
    for (final uri in [
      if (handle != null) Uri.parse('tg://resolve?domain=$handle'),
      Uri.parse(kDeveloperTelegramUrl),
    ]) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (!mounted) return;
    showToast(context, context.read<L10n>().t('telegram_open_error'));
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final l = context.watch<L10n>();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 40), children: [

          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
            ]),
          ),

          _animated(Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 28),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: primaryGlow(_telegramBlue, opacity: 0.30),
                ),
                child: const TelegramLogo(size: 76),
              ),
              const SizedBox(height: 18),
              Text(l.t('contact_developer'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700,
                  color: adaptiveText1(context), letterSpacing: -0.4, height: 1.15)),
              const SizedBox(height: 6),
              Text(
                l.t('contact_page_desc'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
            ]),
          ), 0.0, 0.5),

          _animated(Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: cardShadow(isDark),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const TelegramLogo(size: 32),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Telegram',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
                  const SizedBox(height: 1),
                  Text(_telegramLabel, style: const TextStyle(fontSize: 13, color: C.text4)),
                ])),
              ]),
              const SizedBox(height: 16),

              Tappable(
                onTap: _openTelegram,
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: _telegramBlue,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: primaryGlow(_telegramBlue, opacity: 0.30),
                  ),
                  child: Center(child: Text(l.t('write_telegram'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
              ),
            ]),
          ), 0.15, 0.7),
        ]),
      ),
    );
  }
}
