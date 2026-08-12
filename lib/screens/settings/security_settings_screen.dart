import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/inset_group.dart';
import 'settings_shared.dart';

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
        SettingsGroup(children: [
          SettingsRow(
            pos: GroupPos.last,
            icon: CupertinoIcons.lock_rotation,
            iconBg: primary,
            title: l.t('change_password'),
            sub: l.t('change_password_sub'),
            onTap: () => openChangePassword(context),
          ),
        ]),
        const SizedBox(height: 26),
        // Необратимое действие — отдельной группой снизу, как «Удалить» в
        // системных настройках: не соседствует с обычными пунктами.
        SettingsGroup(children: [
          SettingsRow(
            pos: GroupPos.last,
            icon: CupertinoIcons.trash,
            iconBg: C.red,
            title: l.t('delete_account'),
            sub: l.t('delete_account_sub'),
            titleColor: C.red,
            onTap: () => openDeleteAccount(context),
          ),
        ]),
      ],
    );
  }
}
