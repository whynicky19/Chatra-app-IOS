import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Поле для значения, однострочного по смыслу (тема лекции, название класса,
/// критерий оценивания, имя чата), но с текстом произвольной длины.
///
/// Обычный `TextField` с `maxLines: 1` при длинном значении прокручивается
/// горизонтально: видно хвост строки, а начало уезжает за левый край, и
/// проверить написанное можно только промотав поле пальцем. Здесь текст
/// переносится и поле растёт вниз до [maxLines] строк (дальше — вертикальный
/// скролл), поэтому начало всегда на месте.
///
/// Само значение при этом остаётся однострочным: клавиша Return работает как
/// кнопка действия, а не как перевод строки (для этого явно задан
/// `keyboardType: text` — с `maxLines > 1` Flutter иначе включил бы
/// multiline-клавиатуру), а вставленный многострочный текст схлопывается в
/// пробелы. Без этого в заголовках лекций и названиях классов появлялись бы
/// переносы, которые списки и `Text(maxLines: 1)` всё равно не показывают.
class WrappingField extends StatelessWidget {
  final TextEditingController controller;

  /// Подсказка. Игнорируется, если передан [decoration] целиком.
  final String? hintText;

  /// Готовая декорация для полей с нестандартными отступами/иконками.
  final InputDecoration? decoration;

  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  /// До скольких строк поле растёт, прежде чем начать скроллиться.
  final int maxLines;

  final bool autofocus;
  final bool enabled;
  final TextStyle? style;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;

  const WrappingField({
    super.key,
    required this.controller,
    this.hintText,
    this.decoration,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 3,
    this.autofocus = false,
    this.enabled = true,
    this.style,
    this.textInputAction = TextInputAction.done,
    this.textCapitalization = TextCapitalization.sentences,
  });

  /// Переносы строк (в том числе из буфера обмена) заменяются пробелом, а не
  /// вырезаются: иначе при вставке двух строк последнее слово первой слиплось
  /// бы с первым словом второй.
  static final _noNewlines = FilteringTextInputFormatter.deny(
    RegExp(r'\s*[\r\n]+\s*'),
    replacementString: ' ',
  );

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      style: style,
      decoration: decoration ?? InputDecoration(hintText: hintText),
      minLines: 1,
      maxLines: maxLines,
      keyboardType: TextInputType.text,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: [_noNewlines],
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
    );
  }
}
