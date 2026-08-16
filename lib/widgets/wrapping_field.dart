import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Поле для значения, однострочного по смыслу (тема лекции, название класса,
/// критерий оценивания, имя чата), но с текстом произвольной длины.
///
/// `TextField` с `maxLines: 1` прокручивается горизонтально и прячет начало
/// строки; здесь текст переносится, а поле растёт вниз до [maxLines].
/// Значение при этом остаётся однострочным: Return — кнопка действия,
/// вставленные переносы схлопываются в пробелы.
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
