import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/haptics.dart';

/// Пункт кастомной шторки действий (см. [showAppActionSheet]).
class AppActionSheetAction {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const AppActionSheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });
}

/// Шторка действий в стиле приложения — замена системного
/// CupertinoActionSheet, чей нативный дизайн выбивался из остального UI.
///
/// Тот же язык форм, что и у highlight_actions_sheet: карточка на
/// `colorScheme.surface` с радиусом AppRadii.card и cardShadow, внутри —
/// ручка, опциональный заголовок и строки «иконка + подпись»; ниже —
/// отдельная карточка «Отмена».
Future<T?> showAppActionSheet<T>(
  BuildContext context, {
  String? title,
  required List<AppActionSheetAction> actions,
  required String cancelLabel,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(isDark),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Ручка — как в _Sheet и highlight_actions_sheet.
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: adaptiveBorder(context),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
              ),
            ),
            if (title != null && title.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: adaptiveText2(context),
                  ),
                ),
              ),
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: adaptiveBorder(context)),
              _Tile(action: actions[i]),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            hapticSelection();
            Navigator.pop(ctx);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: cardShadow(isDark),
            ),
            child: Text(cancelLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.primary,
                )),
          ),
        ),
      ]),
    ),
  );
}

class _Tile extends StatelessWidget {
  final AppActionSheetAction action;

  const _Tile({required this.action});

  @override
  Widget build(BuildContext context) {
    final color =
        action.destructive ? C.red : Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        hapticSelection();
        Navigator.pop(context);
        action.onTap();
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Icon(action.icon, size: 19, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Text(action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: action.destructive ? color : adaptiveText1(context),
                )),
          ),
        ]),
      ),
    );
  }
}
