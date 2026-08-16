import 'package:flutter/material.dart';

/// Выделение текста лекции с заметкой. Серверная сущность (общая с сайтом):
/// пометка, сделанная в приложении, открывается в вебе и наоборот.
///
/// Позиция описана только текстом — смещения в потоке текста поверхности плюс
/// якорь prefix/suffix. Пиксельных координат нет намеренно: экран телефона и
/// страница PDF на сайте — разные системы координат (см. backend
/// models.Annotation).
class Annotation {
  final int id;
  final int lectureId;
  final int classId;

  /// -1 — текст самой лекции (так их создаёт приложение), иначе индекс вложения.
  final int fileIndex;

  /// Страница PDF (1..N); 0 — документ без страниц.
  final int page;
  final String selectedText;
  final String prefix;
  final String suffix;
  final int startOffset;
  final int endOffset;
  final String color;
  final String? comment;
  final String? lectureTitle;
  final DateTime? updatedAt;

  const Annotation({
    required this.id,
    required this.lectureId,
    required this.classId,
    required this.fileIndex,
    required this.page,
    required this.selectedText,
    required this.prefix,
    required this.suffix,
    required this.startOffset,
    required this.endOffset,
    required this.color,
    this.comment,
    this.lectureTitle,
    this.updatedAt,
  });

  bool get isLectureText => fileIndex < 0;

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: (j['id'] as num).toInt(),
        lectureId: (j['lecture_id'] as num).toInt(),
        classId: (j['class_id'] as num?)?.toInt() ?? 0,
        fileIndex: (j['file_index'] as num?)?.toInt() ?? -1,
        page: (j['page'] as num?)?.toInt() ?? 0,
        selectedText: (j['selected_text'] ?? '').toString(),
        prefix: (j['prefix'] ?? '').toString(),
        suffix: (j['suffix'] ?? '').toString(),
        startOffset: (j['start_offset'] as num?)?.toInt() ?? 0,
        endOffset: (j['end_offset'] as num?)?.toInt() ?? 0,
        color: (j['color'] ?? 'yellow').toString(),
        comment: (j['comment'] as String?)?.trim().isEmpty ?? true ? null : j['comment'] as String,
        lectureTitle: j['lecture_title'] as String?,
        updatedAt: DateTime.tryParse((j['updated_at'] ?? '').toString()),
      );

  Annotation copyWith({String? color, String? comment, bool clearComment = false}) => Annotation(
        id: id,
        lectureId: lectureId,
        classId: classId,
        fileIndex: fileIndex,
        page: page,
        selectedText: selectedText,
        prefix: prefix,
        suffix: suffix,
        startOffset: startOffset,
        endOffset: endOffset,
        color: color ?? this.color,
        comment: clearComment ? null : (comment ?? this.comment),
        lectureTitle: lectureTitle,
        updatedAt: updatedAt,
      );
}

/// Палитра выделений — те же четыре цвета, что и на сайте, чтобы одна и та же
/// пометка выглядела одинаково на обоих клиентах.
const highlightColors = <String>['yellow', 'green', 'blue', 'red'];

const _swatches = <String, Color>{
  'yellow': Color(0xFFFFD84D),
  'green': Color(0xFF7BDCA0),
  'blue': Color(0xFF7CC5F5),
  'red': Color(0xFFFF9A9A),
};

Color highlightSwatch(String color) => _swatches[color] ?? _swatches['yellow']!;

/// Заливка под текстом: на светлой теме — пастель, на тёмной тот же тон гасим,
/// иначе жёлтый по белому тексту слепит и текст перестаёт читаться.
Color highlightFill(String color, Brightness brightness) {
  final base = highlightSwatch(color);
  return brightness == Brightness.dark
      ? base.withValues(alpha: 0.30)
      : base.withValues(alpha: 0.45);
}
