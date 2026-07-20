import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import 'blocked_users_screen.dart';
import 'settings_shared.dart';

/// Раздел «Аккаунт и безопасность»: смена пароля, блок-лист, удаление аккаунта.
/// Раньше всё это лежало плоским списком на главном экране настроек.
class SecuritySettingsScreen extends StatelessWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;

    return SettingsSubScreen(
      title: l.t('security_section'),
      subtitle: l.t('security_section_sub'),
      children: [
        SettingsActionCard(
          icon: CupertinoIcons.lock_rotation,
          iconBg: primary,
          title: l.t('change_password'),
          sub: l.t('change_password_sub'),
          onTap: () => openChangePassword(context),
        ),
        const SizedBox(height: 16),
        SettingsActionCard(
          icon: CupertinoIcons.nosign,
          iconBg: primary,
          title: l.t('blocked_users_title'),
          sub: l.t('blocked_users_sub'),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
        ),
        const SizedBox(height: 16),
        // Удаление аккаунта — деструктивное, поэтому в конце и красным.
        SettingsActionCard(
          icon: CupertinoIcons.trash,
          iconBg: C.red,
          title: l.t('delete_account'),
          sub: l.t('delete_account_sub'),
          titleColor: C.red,
          onTap: () => openDeleteAccount(context),
        ),
      ],
    );
  }
}
