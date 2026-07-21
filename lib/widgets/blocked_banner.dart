import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/l10n_provider.dart';
import '../theme/app_theme.dart';

/// Панель «вы заблокировали собеседника» вместо поля ввода. Живёт внизу
/// вкладки, поэтому отступает на плавающий таб-бар (bottomBarInset) — иначе
/// уезжает под навбар.
class BlockedBanner extends StatelessWidget {
  final VoidCallback onUnblock;
  const BlockedBanner({super.key, required this.onUnblock});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottomBarInset(context)),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
          blurRadius: 12, offset: const Offset(0, -2))],
      ),
      child: Row(children: [
        const Icon(CupertinoIcons.nosign, size: 18, color: C.text4),
        const SizedBox(width: 10),
        Expanded(child: Text(l.t('you_blocked_user'),
          style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w600))),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onUnblock,
          child: Text(l.t('unblock_user_action'),
            style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
