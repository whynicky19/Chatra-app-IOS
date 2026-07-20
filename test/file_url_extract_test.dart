import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/screens/classes/class_detail_utils.dart';

/// Ссылки на файлы лежат прямо в тексте (описание задания, тело поста) и
/// приходят подписанными: ?exp=...&sig=... Разбор ломался двумя способами —
/// подписанные ссылки не находились вовсе, а из markdown-ссылки в sig утекала
/// закрывающая скобка, из-за чего сервер отдавал 403 на валидный файл.
void main() {
  const host = 'http://192.168.10.13:8000';
  const signed = '$host/uploads/9c966ec5.pptx?exp=1784638628&sig=cfd792ba';
  const bare = '$host/uploads/9c966ec5.pptx';

  group('находит ссылку', () {
    test('подписанную, отдельно стоящую', () {
      expect(extractFileUrls('Лекция $signed'), [signed]);
    });

    test('без подписи', () {
      expect(extractFileUrls('Лекция $bare'), [bare]);
    });

    test('с #именем файла', () {
      const u = '$signed#Отчёт.pptx';
      expect(extractFileUrls('Лекция $u'), [u]);
    });

    test('несколько ссылок в одном тексте', () {
      final r = extractFileUrls('$bare и ещё $host/uploads/b.pdf');
      expect(r, [bare, '$host/uploads/b.pdf']);
    });

    test('.docx не срезается до .doc', () {
      const u = '$host/uploads/a.docx?exp=1&sig=2';
      expect(extractFileUrls(u), [u]);
    });
  });

  group('не тащит лишнюю пунктуацию', () {
    test('markdown-ссылка в скобках', () {
      expect(extractFileUrls('Лекция ([скачать]($signed))'), [signed]);
    });

    test('ссылка в конце предложения', () {
      expect(extractFileUrls('Материал тут $signed.'), [signed]);
    });

    test('ссылка через запятую в перечислении', () {
      expect(extractFileUrls('Файлы: $bare, и всё'), [bare]);
    });

    test('парность скобок в самом имени сохраняется', () {
      const u = '$host/uploads/a.pdf?name=(1)';
      expect(extractFileUrls('см. $u'), [u]);
    });
  });

  group('trimUrlPunctuation', () {
    test('срезает только непарные закрывающие', () {
      expect(trimUrlPunctuation('http://x/a.pdf))'), 'http://x/a.pdf');
      expect(trimUrlPunctuation('http://x/a.pdf?n=(1)'), 'http://x/a.pdf?n=(1)');
    });

    test('срезает точку и запятую', () {
      expect(trimUrlPunctuation('http://x/a.pdf.'), 'http://x/a.pdf');
      expect(trimUrlPunctuation('http://x/a.pdf,'), 'http://x/a.pdf');
    });
  });
}
