import 'package:flutter/cupertino.dart';
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

    return SettingsSubScreen(
      title: l.t('security_section'),
      subtitle: l.t('security_section_sub'),
      children: [
        // Оба пункта — одной группой с разделителем, как «Условия» и
        // «Конфиденциальность» в about_settings_screen или блок «Разделы» в
        // настройках. Отступ в 26 pt в этом экране разделял две одиночные
        // карточки и читался как пустой провал, хотя везде он отбивает
        // секции по несколько строк. Необратимость удаления по-прежнему видна
        // по красной плитке и красному заголовку.
        SettingsGroup(children: [
          SettingsRow(
            pos: GroupPos.middle,
            icon: CupertinoIcons.lock_rotation,
            iconBg: C.settingsTile,
            title: l.t('change_password'),
            sub: l.t('change_password_sub'),
            onTap: () => openChangePassword(context),
          ),
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
