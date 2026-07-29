import 'dates.dart';

/// Дневная квота сообщений ИИ. Считается на сервере (GET /ai/limits) и общая
/// для приложения и сайта — локально её считать нельзя.
class AiQuota {
  final int limit;
  final int used;
  final int? remaining; // null — безлимит
  final bool unlimited;
  final DateTime? resetsAt; // момент обнуления счётчика (UTC)

  const AiQuota({
    required this.limit,
    required this.used,
    this.remaining,
    required this.unlimited,
    this.resetsAt,
  });

  static AiQuota? fromJson(dynamic json) {
    if (json is! Map) return null;
    final limit = json['limit'];
    if (limit is! int) return null;
    return AiQuota(
      limit: limit,
      used: json['used'] is int ? json['used'] as int : 0,
      remaining: json['remaining'] is int ? json['remaining'] as int : null,
      unlimited: json['unlimited'] == true,
      resetsAt: parseServerDate('${json['resets_at']}'),
    );
  }

  int get left => remaining ?? (limit - used).clamp(0, limit);
  bool get exhausted => !unlimited && left <= 0;
  double get progress => limit <= 0 ? 0 : (used / limit).clamp(0.0, 1.0);

  /// Сколько осталось до обнуления счётчика; null — сервер не прислал время.
  Duration? get untilReset {
    final at = resetsAt;
    if (at == null) return null;
    final d = at.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}
