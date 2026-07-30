/// Инициалы для аватарок.
///
/// Наивный `fullName.split(' ')[0][0]` падает с RangeError на реальных данных:
/// «Иван  Петров» (двойной пробел) → ['Иван', '', 'Петров'], и `parts[1][0]`
/// обращается к пустой строке. То же с ведущим/хвостовым пробелом и с
/// `split(' ').last[0]`. Имена приходят не только из формы регистрации (там
/// есть trim), но и из админки, с веб-версии и из старых записей БД —
/// рассчитывать на чистоту нельзя.
///
/// Разбиение идёт по `\s+`, пустые части отбрасываются, поэтому индексация
/// всегда безопасна.
String initialsFrom(String? fullName, {String? email}) {
  final parts = (fullName ?? '')
      .split(RegExp(r'\s+'))
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
