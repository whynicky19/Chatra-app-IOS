import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/utils/message_attachment.dart';

void main() {
  const signed =
      'http://localhost:8000/uploads/d1e2.png?exp=1784713270&sig=d1575f8d85';

  test('markdown-вложение с сайта: подпись не уезжает в URL', () {
    final att = parseMessageAttachment('🖼️ [Фото]($signed) — ceo.png');
    expect(att, isNotNull);
    expect(att!.url, signed);          // без хвостовой ')'
    expect(att.isImage, isTrue);
    expect(att.name, 'ceo.png');
    expect(att.caption, '');
  });

  test('markdown-файл с сайта', () {
    final att = parseMessageAttachment(
        '📎 [Файл](http://h/uploads/x.pdf?sig=1) — отчёт.pdf');
    expect(att!.isImage, isFalse);
    expect(att.name, 'отчёт.pdf');
    expect(att.url, 'http://h/uploads/x.pdf?sig=1');
  });

  test('голая ссылка из приложения', () {
    final att = parseMessageAttachment('/uploads/abc.jpg');
    expect(att!.isImage, isTrue);
    expect(att.url, '/uploads/abc.jpg');
    expect(att.name, 'abc.jpg');
  });

  test('оригинальное имя во fragment', () {
    final att = parseMessageAttachment('/uploads/abc.png#%D1%84%D0%BE%D1%82%D0%BE.png');
    expect(att!.name, 'фото.png');
  });

  test('обычный текст вложением не считается', () {
    expect(parseMessageAttachment('привет, как дела?'), isNull);
    expect(parseMessageAttachment('https://ya.ru'), isNull);
  });

  test('превью для списка чатов и цитат', () {
    expect(messagePreviewText('🖼️ [Фото]($signed) — ceo.png'), '📷 ceo.png');
    expect(messagePreviewText('просто текст'), 'просто текст');
  });
}
