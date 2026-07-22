import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/screens/classes/class_detail_utils.dart';

/// Ссылки на файлы приходят подписанными (?exp=...&sig=...) и с абсолютным
/// адресом сервера из APP_BASE_URL (по умолчанию localhost). И то и другое
/// ломало отправку фото в чат: картинка не грузилась, а хвост подписи
/// печатался в сообщении как текст.
void main() {
  final api = ApiService(baseUrl: 'http://192.168.10.13:8000');

  // Та же регулярка, что в _buildMessageContent.
  final imgRegex = RegExp(
      r'https?://\S+?\.(jpg|jpeg|png|gif|webp)(\?\S*)?',
      caseSensitive: false);

  group('регулярка картинки', () {
    test('захватывает подпись целиком, а не обрывается на .jpg', () {
      const url =
          'http://192.168.10.13:8000/uploads/e4bf20e9.jpg?exp=1784631632&sig=990f483f';
      final m = imgRegex.firstMatch(url);
      expect(m, isNotNull);
      expect(m!.group(0), url,
          reason: 'без query сервер не отдаст файл — нужна вся подпись');
    });

    test('после вырезания ссылки не остаётся хвоста подписи', () {
      const content =
          'http://192.168.10.13:8000/uploads/a.jpg?exp=1&sig=abc';
      final url = imgRegex.firstMatch(content)!.group(0)!;
      final textPart = content.replaceAll(url, '').trim();
      expect(textPart, isEmpty,
          reason: 'именно этот остаток и показывался пользователю');
    });

    test('работает и без query, и с текстом рядом', () {
      expect(imgRegex.firstMatch('http://h/a.png')?.group(0), 'http://h/a.png');
      final m = imgRegex.firstMatch('смотри http://h/b.jpeg?sig=1 вот');
      expect(m?.group(0), 'http://h/b.jpeg?sig=1');
    });

    test('не-картинки не матчатся', () {
      expect(imgRegex.firstMatch('http://h/doc.pdf?sig=1'), isNull);
    });
  });

  group('fixUrlsInText', () {
    test('подменяет localhost на актуальный baseUrl вместе с подписью', () {
      const content =
          'http://localhost:8000/uploads/x.jpg?exp=1784631632&sig=990f';
      expect(
        api.fixUrlsInText(content),
        'http://192.168.10.13:8000/uploads/x.jpg?exp=1784631632&sig=990f',
      );
    });

    test('подменяет 127.0.0.1', () {
      expect(api.fixUrlsInText('http://127.0.0.1:9000/uploads/y.png'),
          'http://192.168.10.13:8000/uploads/y.png');
    });

    test('делает относительный путь абсолютным', () {
      expect(api.fixUrlsInText('/uploads/z.jpg?sig=1'),
          'http://192.168.10.13:8000/uploads/z.jpg?sig=1');
    });

    test('не трогает посторонние ссылки и обычный текст', () {
      expect(api.fixUrlsInText('привет'), 'привет');
      expect(api.fixUrlsInText('https://example.com/a.jpg'),
          'https://example.com/a.jpg');
    });
  });

  group('toRelativeUploadUrl', () {
    test('срезает origin', () {
      expect(
        api.toRelativeUploadUrl(
            'http://localhost:8000/uploads/x.jpg?exp=1&sig=2'),
        '/uploads/x.jpg?exp=1&sig=2',
      );
    });

    test('уже относительный путь не портит', () {
      expect(api.toRelativeUploadUrl('/uploads/x.jpg'), '/uploads/x.jpg');
    });
  });

  test('сквозной путь: загрузка → хранение → отрисовка', () {
    // Что вернул бэкенд
    const fromServer =
        'http://localhost:8000/uploads/e4bf20e9.jpg?exp=1784631632&sig=990f483f';
    // Что кладём в сообщение
    final stored = api.toRelativeUploadUrl(fromServer);
    expect(stored, startsWith('/uploads/'));
    // Что видит рендер
    final rendered = api.fixUrlsInText(stored);
    final matched = imgRegex.firstMatch(rendered);
    expect(matched, isNotNull);
    expect(matched!.group(0), rendered,
        reason: 'ссылка должна съесться целиком, без текстового остатка');
    expect(rendered, contains('sig=990f483f'));
    expect(rendered, isNot(contains('localhost')));
  });

  // Бэкенд переподписывает ссылки в каждом JSON-ответе, поэтому exp/sig у одного
  // и того же файла меняются от запроса к запросу. Ключ кэша обязан это
  // игнорировать — иначе скачанная копия никогда не переиспользуется и каждое
  // открытие плодит новый файл во временной папке.
  group('ключ кэша файла', () {
    test('не зависит от подписи', () {
      const a = 'http://localhost:8000/uploads/abc.pdf?exp=1784636643&sig=7c0baf4b';
      const b = 'http://localhost:8000/uploads/abc.pdf?exp=1784636645&sig=a85957dd';
      expect(fileCacheKey(a), fileCacheKey(b));
    });

    test('не зависит от #fragment с исходным именем', () {
      const a = 'http://localhost:8000/uploads/abc.pdf?exp=1&sig=x';
      const b = 'http://localhost:8000/uploads/abc.pdf?exp=2&sig=y#Отчёт по практике.pdf';
      expect(fileCacheKey(a), fileCacheKey(b));
    });

    test('разные файлы получают разные ключи', () {
      const a = 'http://localhost:8000/uploads/abc.pdf?exp=1&sig=x';
      const b = 'http://localhost:8000/uploads/def.pdf?exp=1&sig=x';
      expect(fileCacheKey(a), isNot(fileCacheKey(b)));
    });
  });
}
