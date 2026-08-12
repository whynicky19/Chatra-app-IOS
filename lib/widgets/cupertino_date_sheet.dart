import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

/// Единая шторка выбора даты/времени в стиле iOS.
///
/// Раньше `assignment_editor_screen.dart` и `rollover_screen.dart` открывали
/// Material `showDatePicker`/`showTimePicker` (сеточный календарь + аналоговый
/// циферблат) — единственный по-настоящему заметный разрыв Cupertino-языка
/// во всём приложении (везде рядом `CupertinoIcons`, `CupertinoPageTransitionsBuilder`,
/// `CupertinoActionSheet`). Эта шторка — колесо `CupertinoDatePicker` внутри
/// стандартной для Chatra bottom-sheet рамки (тот же `AppRadii.sheet`,
/// drag-handle и `AppButton.text` для Отмена/Готово, что и в `SheetScaffold`).
///
/// Формат даты/времени и то, что делает вызывающий код с результатом —
/// не меняются: функция просто возвращает выбранный `DateTime?` (`null`,
/// если отменили), как и `showDatePicker`.
Future<DateTime?> showCupertinoDateTimeSheet(
  BuildContext context, {
  required DateTime initialDateTime,
  DateTime? minimumDate,
  DateTime? maximumDate,
  CupertinoDatePickerMode mode = CupertinoDatePickerMode.dateAndTime,
  String? title,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CupertinoDateTimeSheet(
      initialDateTime: initialDateTime,
      minimumDate: minimumDate,
      maximumDate: maximumDate,
      mode: mode,
      title: title,
    ),
  );
}

class _CupertinoDateTimeSheet extends StatefulWidget {
  final DateTime initialDateTime;
  final DateTime? minimumDate;
  final DateTime? maximumDate;
  final CupertinoDatePickerMode mode;
  final String? title;

  const _CupertinoDateTimeSheet({
    required this.initialDateTime,
    this.minimumDate,
    this.maximumDate,
    required this.mode,
    this.title,
  });

  @override
  State<_CupertinoDateTimeSheet> createState() => _CupertinoDateTimeSheetState();
}

class _CupertinoDateTimeSheetState extends State<_CupertinoDateTimeSheet> {
  late DateTime _value = widget.initialDateTime;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Padding(
      // Шторка без текстовых полей — клавиатура не открывается, но паддинг
      // остаётся на случай системных a11y-оверлеев поверх safe area.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 2),
                decoration: BoxDecoration(
                  color: adaptiveText4(context).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Row(children: [
                Expanded(
                  child: AppButton.text(
                    label: 'Отмена',
                    color: adaptiveText3(context),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (widget.title != null)
                  Expanded(
                    flex: 2,
                    child: Text(widget.title!,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
                  ),
                Expanded(
                  child: AppButton.text(
                    label: 'Готово',
                    onPressed: () => Navigator.pop(context, _value),
                  ),
                ),
              ]),
            ),
            SizedBox(
              height: 216,
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: isDark ? Brightness.dark : Brightness.light,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(fontSize: 20, color: adaptiveText1(context)),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: widget.mode,
                  initialDateTime: widget.initialDateTime,
                  minimumDate: widget.minimumDate,
                  maximumDate: widget.maximumDate,
                  use24hFormat: true,
                  onDateTimeChanged: (d) => _value = d,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}
