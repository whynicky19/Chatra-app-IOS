/// Инициалы для аватарок. Разбиение по `\s+` с отбрасыванием пустых частей:
/// имена приходят из админки и старых записей БД, «Иван  Петров» с двойным
/// пробелом роняет наивный `split(' ')` по RangeError.
final _wsRe = RegExp(r'\s+');

String initialsFrom(String? fullName, {String? email}) {
  final parts = (fullName ?? '')
      .split(_wsRe)
      .where((s) => s.isNotEmpty)
      .toList();

  if (parts.length >= 2) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  if (parts.length == 1) {
    // Одно слово — берём две первые буквы, если они есть.
    final w = parts[0];
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }

  final e = (email ?? '').trim();
  return e.isNotEmpty ? e[0].toUpperCase() : '?';
}
