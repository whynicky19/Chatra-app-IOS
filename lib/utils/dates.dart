// Бэкенд отдаёт naive ISO-строки (без 'Z'/offset), которые по факту UTC
// (см. utils/time.py::utcnow() на бэкенде). DateTime.parse() без явной зоны
// трактует такую строку как ЛОКАЛЬНОЕ время — отсюда расхождение на величину
// UTC-offset пользователя. Все даты с сервера должны идти через этот парсер,
// а не через "голый" DateTime.parse/tryParse.
DateTime? parseServerDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  var s = iso;
  final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
  if (!hasTz) s = '${s}Z';
  try {
    return DateTime.parse(s).toLocal();
  } catch (_) {
    return null;
  }
}

// Обратная операция: локальное время, выбранное пользователем (например, в
// date/time picker), нужно перевести в UTC перед отправкой на сервер — иначе
// сервер запишет цифры "как есть" в naive-UTC поле и время сдвинется на
// величину offset (см. is_late в routers/assignments.py на бэкенде).
String toServerDateString(DateTime dt) => dt.toUtc().toIso8601String();

String fmtDateTimeLocal(String iso) {
  final dt = parseServerDate(iso);
  if (dt == null) return iso;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(dt.day)}.${p(dt.month)}.${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
}
