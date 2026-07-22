/// Тред (чат) главного ИИ-ассистента. Бэкенд отдаёт список тредов,
/// отсортированный pinned DESC, updated_at DESC.
class AiThread {
  final int id;
  String title;
  bool pinned;
  final DateTime createdAt;
  DateTime updatedAt;

  AiThread({
    required this.id,
    required this.title,
    required this.pinned,
    required this.createdAt,
    required this.updatedAt,
  });

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    try {
      var s = v.toString();
      final hasTz = s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s);
      if (!hasTz) s = '${s}Z';
      return DateTime.parse(s).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  factory AiThread.fromJson(Map<String, dynamic> json) => AiThread(
        id: (json['id'] as num).toInt(),
        title: (json['title'] ?? '').toString(),
        pinned: json['pinned'] == true,
        createdAt: _parseDate(json['created_at']),
        updatedAt: _parseDate(json['updated_at']),
      );
}
