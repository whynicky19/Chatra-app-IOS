/// Formats a backend timestamp as local "dd.MM.yyyy HH:mm".
///
/// The backend stores naive UTC (`datetime.utcnow()`), so its ISO strings
/// carry no timezone marker. `DateTime.parse` would treat them as local time
/// and the shown time would be off by the UTC offset — appending 'Z' first
/// makes the UTC origin explicit, then we convert to the device timezone.
String fmtDateTimeLocal(String iso) {
  if (iso.isEmpty) return '';
  try {
    var s = iso;
    final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (!hasTz) s = '${s}Z';
    final dt = DateTime.parse(s).toLocal();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(dt.day)}.${p(dt.month)}.${dt.year} ${p(dt.hour)}:${p(dt.minute)}';
  } catch (_) {
    return iso;
  }
}
