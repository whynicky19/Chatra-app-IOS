import 'package:flutter/material.dart';

import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/dates.dart';

/// Общее форматирование и палитра админ-панели.

/// Разделитель разрядов — узкий неразрывный пробел, как в системных числах iOS.
String fmtInt(num? value) {
  final v = (value ?? 0).round();
  final digits = v.abs().toString();
  final buf = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(' ');
    buf.write(digits[i]);
  }
  return buf.toString();
}

/// Компактная запись для тесных мест (плитки, оси): 1,2 млн / 12 тыс.
String fmtCompact(num? value, L10n l) {
  final v = (value ?? 0).round();
  if (v >= 1000000) {
    final s = (v / 1000000).toStringAsFixed(v >= 10000000 ? 0 : 1).replaceAll('.', ',');
    return '$s ${l.t('unit_million')}';
  }
  if (v >= 10000) return '${(v / 1000).round()} ${l.t('unit_thousand')}';
  return fmtInt(v);
}

/// «Сегодня, 14:32» / «Вчера, 09:10» / «12 авг., 18:00» — как в списках Mail.
String fmtRelativeDate(String? iso, L10n l) {
  final d = parseServerDate(iso)?.toLocal();
  if (d == null) return l.t('no_activity');
  final now = DateTime.now();
  final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(d, now)) return '${l.t('today')}, $time';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return '${l.t('yesterday')}, $time';
  final months = _months(l.lang);
  final date = '${d.day} ${months[d.month - 1]}';
  return d.year == now.year ? '$date, $time' : '$date ${d.year}, $time';
}

/// Полная дата: «12 августа 2026».
String fmtLongDate(String? iso, L10n l) {
  final d = parseServerDate(iso)?.toLocal();
  if (d == null) return l.t('unknown_date');
  return '${d.day} ${_monthsGenitive(l.lang)[d.month - 1]} ${d.year}';
}

List<String> _months(String lang) => switch (lang) {
  'EN' => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
  'KZ' => const ['қаң.', 'ақп.', 'нау.', 'сәу.', 'мам.', 'мау.', 'шіл.', 'там.', 'қыр.', 'қаз.', 'қар.', 'жел.'],
  _ => const ['янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'],
};

List<String> _monthsGenitive(String lang) => switch (lang) {
  'EN' => const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
  'KZ' => const ['қаңтар', 'ақпан', 'наурыз', 'сәуір', 'мамыр', 'маусым', 'шілде', 'тамыз', 'қыркүйек', 'қазан', 'қараша', 'желтоқсан'],
  _ => const ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'],
};

/// Инициалы для аватара: одна-две буквы имени, иначе первая буква почты.
String initialsOf(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '—';
  final letters = parts.take(2).map((p) => p.substring(0, 1).toUpperCase()).join();
  return letters.isEmpty ? '—' : letters;
}

const _avatarTints = [
  Color(0xFF5E5CE6), Color(0xFF0A84FF), Color(0xFF30B0C7), Color(0xFF32A852),
  Color(0xFFFF9F0A), Color(0xFFFF6482), Color(0xFFBF5AF2), Color(0xFF64748B),
];
Color avatarColorOf(int id) => _avatarTints[id.abs() % _avatarTints.length];

/// Цвета видов расхода ИИ (group из /admin/ai-usage/*). Проверены валидатором
/// на светлой (#FFFFFF) и тёмной (#1C1C1E) поверхностях: худшая пара по CVD
/// ΔE 11.8 / 11.2, по обычному зрению 20.4 / 17.9.
const _kindLight = {
  'chat': Color(0xFF00B1C9),
  'grade': Color(0xFFAF52DE),
  'cover': Color(0xFFFF9500),
  'title': Color(0xFFFF2D55),
  'other': Color(0xFF8E8E93),
};
const _kindDark = {
  'chat': Color(0xFF1BA4B9),
  'grade': Color(0xFF9D41CA),
  'cover': Color(0xFFD17A05),
  'title': Color(0xFFD31E43),
  'other': Color(0xFF8E8E93),
};

Color kindColor(BuildContext context, String? group) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final table = isDark ? _kindDark : _kindLight;
  return table[group] ?? table['other']!;
}

IconData kindIcon(String? group) => switch (group) {
  'chat' => Icons.chat_bubble_outline_rounded,
  'grade' => Icons.assignment_turned_in_outlined,
  'cover' => Icons.image_outlined,
  'title' => Icons.title_rounded,
  _ => Icons.auto_awesome_outlined,
};

/// Русские/казахские склонения: «3 записи», а не «3 записей».
String plural(int n, String one, String few, String many) {
  final a = n.abs() % 100;
  if (a > 10 && a < 20) return many;
  final b = a % 10;
  if (b == 1) return one;
  if (b >= 2 && b <= 4) return few;
  return many;
}

/// Полоса-заполнение одной строки (доля от максимума в списке).
class MiniBar extends StatelessWidget {
  const MiniBar({super.key, required this.value, required this.color, this.height = 6, this.track});

  final double value;
  final Color color;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth * value.clamp(0.0, 1.0);
          return Stack(children: [
            Positioned.fill(child: ColoredBox(color: track ?? adaptiveSurface2(context))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              width: w,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(100)),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Круглый аватар с инициалами — тот же в списке пользователей, в карточке и
/// в составе предмета.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.id, required this.name, this.size = 38, this.radius = 12});

  final int id;
  final String? name;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatarColorOf(id), borderRadius: BorderRadius.circular(radius)),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
      ),
    );
  }
}
