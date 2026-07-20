import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/moderation_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/moderation_actions.dart';

/// Список заблокированных пользователей с возможностью разблокировать.
/// App Store Guideline 1.2 требует, чтобы блокировка была не только доступна,
/// но и обратима — до этого экрана метод unblock() нигде не вызывался.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  static const _avatarColors = [
    C.teal,
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFF0891B2),
    Color(0xFFEC4899),
    Color(0xFF059669),
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final mod = context.watch<ModerationService>();
    final entries = mod.blockedUsers.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));

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
              Expanded(
                child: Text(l.t('blocked_users_title'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: adaptiveText1(context),
                        letterSpacing: -0.3)),
              ),
            ]),
          ),
          Expanded(
            child: entries.isEmpty
                ? _empty(context, l)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _row(context, l, entries[i]),
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _empty(BuildContext context, L10n l) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.checkmark_shield,
                size: 44, color: C.text4.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text(l.t('blocked_users_empty'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: C.text4, height: 1.5)),
          ]),
        ),
      );

  Widget _row(BuildContext context, L10n l, MapEntry<int, String> e) {
    final name = e.value.isNotEmpty ? e.value : '${l.t('user')} #${e.key}';
    final color = _avatarColors[e.key.abs() % _avatarColors.length];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(name[0].toUpperCase(),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 15)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: adaptiveText1(context))),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => unblockUser(context, userId: e.key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(l.t('unblock'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary)),
          ),
        ),
      ]),
    );
  }
}
