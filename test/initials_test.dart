import 'package:chatra_app/utils/initials.dart';
import 'package:flutter_test/flutter_test.dart';

/// Регрессия на RangeError в инициалах.
///
/// Прежняя реализация делала `fullName.split(' ')[0][0]` и падала на любом
/// имени с двойным/ведущим/хвостовым пробелом — а такие имена приходят из
/// админки, с веб-версии и из старых записей БД.
void main() {
  group('initialsFrom', () {
    test('обычное ФИО', () {
      expect(initialsFrom('Иван Петров'), 'ИП');
      expect(initialsFrom('John Smith'), 'JS');
    });

    test('двойной пробел между словами не роняет', () {
      expect(initialsFrom('Иван  Петров'), 'ИП');
    });

    test('ведущий и хвостовой пробелы не роняют', () {
      expect(initialsFrom('  Иван Петров  '), 'ИП');
      expect(initialsFrom('Иван Петров '), 'ИП');
      expect(initialsFrom(' Иван'), 'ИВ');
    });

    test('табуляция и перевод строки', () {
      expect(initialsFrom('Иван\tПетров'), 'ИП');
      expect(initialsFrom('Иван\nПетров'), 'ИП');
    });

    test('одно слово', () {
      expect(initialsFrom('Иван'), 'ИВ');
      expect(initialsFrom('X'), 'X');
    });

    test('три слова — берём первые два', () {
      expect(initialsFrom('Иван Петрович Сидоров'), 'ИП');
    });

    test('пустое имя — падаем на email', () {
      expect(initialsFrom('', email: 'test@example.com'), 'T');
      expect(initialsFrom('   ', email: 'test@example.com'), 'T');
      expect(initialsFrom(null, email: 'test@example.com'), 'T');
    });

    test('нет ни имени, ни почты', () {
      expect(initialsFrom(null), '?');
      expect(initialsFrom(''), '?');
      expect(initialsFrom('  ', email: '  '), '?');
    });

    test('подставленный id вместо имени', () {
      expect(initialsFrom('#42'), '#4');
    });
  });
}
