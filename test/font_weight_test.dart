import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регрессия на «в разных местах разная толщина шрифта».
///
/// Веса в приложении разъезжались: заголовки строк были и w400, и w500, и w600,
/// а отдельные подписи доходили до w800/w900 — одинаковые по смыслу строки на
/// разных экранах выглядели по-разному. Шкала весов описана в
/// lib/theme/app_theme.dart; этот тест сторожит две её границы.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('в lib нет весов тяжелее w700', () {
    final offenders = <String>[];
    for (final f in dartFiles) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('FontWeight.w800') ||
            lines[i].contains('FontWeight.w900') ||
            lines[i].contains('FontWeight.black') ||
            lines[i].contains('FontWeight.w1000')) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'вес тяжелее w700 не входит в шкалу (см. app_theme.dart)');
  });

  test('bold (w700) не используется на кегле 17pt и мельче', () {
    // Именно из-за bold на мелком кегле «толщина» и плавала: на одних экранах
    // 15pt-подписи были bold, на других — medium.
    final weightRe = RegExp(r'FontWeight\.w700');
    final sizeRe = RegExp(r'fontSize:\s*([0-9.]+)');
    final offenders = <String>[];
    for (final f in dartFiles) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!weightRe.hasMatch(lines[i])) continue;
        // Кегль объявляют в той же строке или в соседней — стиль часто разбит.
        final around = [
          if (i > 0) lines[i - 1],
          lines[i],
          if (i + 1 < lines.length) lines[i + 1],
        ].join(' ');
        final m = sizeRe.firstMatch(around);
        if (m == null) continue;
        if (double.parse(m.group(1)!) <= 17) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'на мелком кегле вместо w700 нужен w600 (см. шкалу в app_theme.dart)');
  });

  test('на 16-17pt нет явного w400 — это вес только длинного текста', () {
    // `fontSize: 17, fontWeight: FontWeight.w400` в строке списка и есть та
    // «тонкость», из-за которой настройки выбивались из остальных экранов.
    // Сам body-стиль (bodyLarge и т.п.) объявлен в теме осознанно, поэтому
    // файл темы пропускаем.
    final re = RegExp(r'fontSize:\s*1[67](\.\d+)?,\s*fontWeight:\s*FontWeight\.w400');
    final offenders = <String>[];
    for (final f in dartFiles) {
      if (f.path.endsWith('theme/app_theme.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) offenders.add('${f.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty,
        reason: 'заголовок строки должен быть w600 (см. шкалу в app_theme.dart)');
  });
}
