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
