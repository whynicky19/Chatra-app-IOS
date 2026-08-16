/// Оформление обложек предметов: палитра, предметные иконки, локальное превью.
///
/// Набор цветов и иконок приходит с бэкенда (GET /classes/cover/options,
/// см. services/cover_art.py) — он же рисует готовую обложку, поэтому зашивать
/// свой список в приложении нельзя: пользователь выбрал бы вариант, которого
/// сервер не знает. Здесь только кэш ответа, запасной набор на случай
/// отсутствия сети и SVG-глифы для превью и пикера.
library;

import 'package:flutter/material.dart';

class CoverColorOption {
  final String id;

  /// Акцент бренда: свотч в пикере и цвет выделения.
  final Color hex;

  /// Основной насыщенный тон композиции — из него строится превью до генерации.
  final Color base;

  final Color ink;

  const CoverColorOption(this.id, this.hex, this.base, this.ink);
}

class CoverIconOption {
  final String id;
  final String subject;

  final String group;
  final String groupLabel;

  const CoverIconOption(this.id, this.subject, {this.group = '', this.groupLabel = ''});
}

class CoverIconGroup {
  final String id;
  final String label;
  const CoverIconGroup(this.id, this.label);
}

class CoverOptions {
  final List<CoverColorOption> colors;
  final List<CoverIconOption> icons;

  final List<CoverIconGroup> groups;
  final String defaultColor;
  final String defaultIcon;
  final bool aiAvailable;

  const CoverOptions({
    required this.colors,
    required this.icons,
    required this.defaultColor,
    required this.defaultIcon,
    required this.aiAvailable,
    this.groups = const [],
  });

  factory CoverOptions.fromJson(Map<String, dynamic> json) {
    List<CoverColorOption> colors = [];
    for (final raw in (json['colors'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final hex = parseHex(m['hex'] as String?);
      final base = parseHex(m['base'] as String?);
      final ink = parseHex(m['ink'] as String?);
      if (hex == null || base == null || ink == null) continue;
      colors.add(CoverColorOption(m['id'] as String, hex, base, ink));
    }
    final icons = [
      for (final raw in (json['icons'] as List? ?? const []))
        CoverIconOption(
          (raw as Map)['id'] as String,
          (raw['subject'] as String?) ?? '',
          group: (raw['group'] as String?) ?? '',
          groupLabel: (raw['group_label'] as String?) ?? '',
        ),
    ];
    final groups = [
      for (final raw in (json['groups'] as List? ?? const []))
        CoverIconGroup((raw as Map)['id'] as String, (raw['label'] as String?) ?? ''),
    ];
    if (colors.isEmpty || icons.isEmpty) return kFallbackCoverOptions;
    return CoverOptions(
      colors: colors,
      icons: icons,
      groups: groups,
      defaultColor: (json['default_color'] as String?) ?? colors.first.id,
      defaultIcon: (json['default_icon'] as String?) ?? icons.first.id,
      aiAvailable: json['ai_available'] as bool? ?? true,
    );
  }

  CoverColorOption colorFor(String? id) => colors.firstWhere(
        (c) => c.id == id,
        orElse: () => colors.firstWhere((c) => c.id == defaultColor,
            orElse: () => colors.first),
      );
}

Color? parseHex(String? value) {
  if (value == null) return null;
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6) return null;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(0xFF000000 | parsed);
}

/// Значения совпадают с PALETTE в services/cover_art.py.
const kFallbackCoverOptions = CoverOptions(
  colors: [
    CoverColorOption('blue', Color(0xFF0A84FF), Color(0xFF3B82F6), Color(0xFF1D4ED8)),
    CoverColorOption('purple', Color(0xFF8B5CF6), Color(0xFF7C5CE6), Color(0xFF6D28D9)),
    CoverColorOption('green', Color(0xFF22C55E), Color(0xFF12A970), Color(0xFF047857)),
    CoverColorOption('orange', Color(0xFFF97316), Color(0xFFF4842B), Color(0xFFC2410C)),
    CoverColorOption('red', Color(0xFFEF4444), Color(0xFFE4534F), Color(0xFFB91C1C)),
    CoverColorOption('pink', Color(0xFFEC4899), Color(0xFFE8559C), Color(0xFFBE185D)),
    CoverColorOption('teal', Color(0xFF00B1C9), Color(0xFF12A2B5), Color(0xFF0E7490)),
    CoverColorOption('indigo', Color(0xFF6366F1), Color(0xFF5A5FE0), Color(0xFF4338CA)),
    CoverColorOption('gold', Color(0xFFEAB308), Color(0xFFB38C22), Color(0xFF854D0E)),
    CoverColorOption('lime', Color(0xFF84CC16), Color(0xFF6FA81B), Color(0xFF3F6212)),
    CoverColorOption('bronze', Color(0xFFC2763A), Color(0xFFB4703C), Color(0xFF7C2D12)),
    CoverColorOption('slate', Color(0xFF7C8BA5), Color(0xFF64748B), Color(0xFF334155)),
  ],
  icons: [
    CoverIconOption('sigma', 'Mathematics', group: 'exact'),
    CoverIconOption('cube', 'Geometry', group: 'exact'),
    CoverIconOption('dice', 'Statistics', group: 'exact'),
    CoverIconOption('atom', 'Physics', group: 'natural'),
    CoverIconOption('flask', 'Chemistry', group: 'natural'),
    CoverIconOption('dna', 'Biology', group: 'natural'),
    CoverIconOption('microscope', 'Microbiology', group: 'natural'),
    CoverIconOption('leaf', 'Ecology', group: 'natural'),
    CoverIconOption('telescope', 'Astronomy', group: 'natural'),
    CoverIconOption('globe', 'Geography', group: 'natural'),
    CoverIconOption('code', 'Programming', group: 'tech'),
    CoverIconOption('browser', 'Web Development', group: 'tech'),
    CoverIconOption('database', 'Databases', group: 'tech'),
    CoverIconOption('network', 'Networks', group: 'tech'),
    CoverIconOption('shield', 'Cybersecurity', group: 'tech'),
    CoverIconOption('chip', 'Electronics', group: 'tech'),
    CoverIconOption('gear', 'Mechanical Engineering', group: 'tech'),
    CoverIconOption('compass', 'Architecture', group: 'tech'),
    CoverIconOption('building', 'Construction', group: 'tech'),
    CoverIconOption('column', 'History', group: 'humanities'),
    CoverIconOption('scroll', 'Philosophy', group: 'humanities'),
    CoverIconOption('book', 'Literature', group: 'humanities'),
    CoverIconOption('brain', 'Psychology', group: 'humanities'),
    CoverIconOption('people', 'Social Studies', group: 'humanities'),
    CoverIconOption('letter', 'English', group: 'language'),
    CoverIconOption('chat', 'Communication', group: 'language'),
    CoverIconOption('chart', 'Economics', group: 'business'),
    CoverIconOption('coins', 'Finance', group: 'business'),
    CoverIconOption('briefcase', 'Management', group: 'business'),
    CoverIconOption('scale', 'Law', group: 'business'),
    CoverIconOption('palette', 'Art', group: 'arts'),
    CoverIconOption('pen', 'Graphic Design', group: 'arts'),
    CoverIconOption('note', 'Music', group: 'arts'),
    CoverIconOption('camera', 'Photography', group: 'arts'),
    CoverIconOption('mic', 'Journalism', group: 'arts'),
    CoverIconOption('pulse', 'Medicine', group: 'health'),
    CoverIconOption('stethoscope', 'Nursing', group: 'health'),
    CoverIconOption('pill', 'Pharmacy', group: 'health'),
    CoverIconOption('wrench', 'Technology & Crafts', group: 'applied'),
    CoverIconOption('chef', 'Culinary Arts', group: 'applied'),
    CoverIconOption('scissors', 'Fashion & Sewing', group: 'applied'),
    CoverIconOption('car', 'Automotive', group: 'applied'),
    CoverIconOption('plane', 'Aviation', group: 'applied'),
    CoverIconOption('sprout', 'Agriculture', group: 'applied'),
    CoverIconOption('ball', 'Physical Education', group: 'sport'),
  ],
  groups: [
    CoverIconGroup('exact', 'Exact sciences'),
    CoverIconGroup('natural', 'Natural sciences'),
    CoverIconGroup('tech', 'Technology & engineering'),
    CoverIconGroup('humanities', 'Humanities'),
    CoverIconGroup('language', 'Languages'),
    CoverIconGroup('business', 'Business & law'),
    CoverIconGroup('arts', 'Arts & media'),
    CoverIconGroup('health', 'Health & medicine'),
    CoverIconGroup('applied', 'Applied & vocational'),
    CoverIconGroup('sport', 'Sport'),
  ],
  defaultColor: 'teal',
  defaultIcon: 'book',
  aiAvailable: true,
);

/// Кэш набора на процесс: он меняется только с деплоем бэкенда, дёргать его
/// при каждом открытии формы создания предмета незачем.
class CoverOptionsCache {
  CoverOptionsCache._();

  static CoverOptions? _value;
  static Future<CoverOptions>? _inflight;

  /// Что показывать прямо сейчас: загруженный набор либо запасной.
  static CoverOptions get current => _value ?? kFallbackCoverOptions;

  static bool get isLoaded => _value != null;

  static Future<CoverOptions> load(Future<Map<String, dynamic>> Function() fetch) {
    final cached = _value;
    if (cached != null) return Future.value(cached);
    return _inflight ??= fetch()
        .then(CoverOptions.fromJson)
        .catchError((_) => kFallbackCoverOptions)
        .then((options) {
          _value = options;
          _inflight = null;
          return options;
        });
  }

  @visibleForTesting
  static void reset([CoverOptions? seeded]) {
    _value = seeded;
    _inflight = null;
  }
}

/// Пути глифов в viewBox 24×24 — те же, что в composables/useCoverArt.ts.
const Map<String, String> kCoverIconPaths = {
  // Точные науки
  'sigma': 'M18.5 4.5H6l7 7.5-7 7.5h12.5',
  'cube': 'M12 2.5 21 7.5v9L12 21.5 3 16.5v-9zM3 7.5l9 5 9-5M12 12.5v9',
  'dice': 'M4.5 4.5h15v15h-15zM9 9h.01M15 9h.01M9 15h.01M15 15h.01M12 12h.01',
  // Естественные науки
  'atom': 'M12 12m-1.6 0a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0 M12 12m-10.5 0'
      'a10.5 4.6 0 1 0 21 0a10.5 4.6 0 1 0 -21 0',
  'flask': 'M9 2.5h6M10 2.5v6.5L3.5 21h17L14 9V2.5',
  'dna': 'M8.6 3c0 6 6.8 12 6.8 18M15.4 3c0 6-6.8 12-6.8 18M9.6 7h4.8M8.2 10.5'
      'h7.6M8.2 13.5h7.6M9.6 17h4.8',
  'microscope': 'M9.5 3.5h3.5v8.5h-3.5zM11.2 12v2.5M7 14.5h8.5M4.5 21.5h15M7.5 21.5'
      'a4.5 4.5 0 0 1 4.5-4.5h.8a5.2 5.2 0 0 0 5.2-5.2V9.5',
  'leaf': 'M4 20c0-9.5 6.6-15.5 16-15.5C20 14 13.8 20 4 20zM4 20c4-6 8-9.2 12-10.6',
  'telescope': 'M3.5 13.5 14.5 4.5l3.5 4-11 9zM7 17l-2.5 4.5M12.5 12.5 16 21.5M2.5 11.5l2 2.5',
  'globe': 'M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 1 0 0-19M12 2.5'
      'a5 9.5 0 1 0 0 19 5 9.5 0 1 0 0-19M2.5 12h19M4.4 7h15.2M4.4 17h15.2',
  // IT и инженерия
  'code': 'M8.5 6.5 3 12l5.5 5.5M15.5 6.5 21 12l-5.5 5.5M13.6 4.2l-3.2 15.6',
  'browser': 'M3 5.5h18v13H3zM3 9.5h18M6 7.5h.01M8.5 7.5h.01M11 7.5h.01',
  'database': 'M12 3.5c4.4 0 8 1.2 8 2.75S16.4 9 12 9 4 7.8 4 6.25 7.6 3.5 12 3.5z'
      'M4 6.25v11.5c0 1.55 3.6 2.75 8 2.75s8-1.2 8-2.75V6.25M4 12'
      'c0 1.55 3.6 2.75 8 2.75s8-1.2 8-2.75',
  'network': 'M12 3.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5M5.5 15.5'
      'a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5M18.5 15.5'
      'a2.5 2.5 0 1 0 0 5 2.5 2.5 0 1 0 0-5M10.4 7.9 7.6 15.1M13.6 7.9'
      'l2.8 7.2M8 18h8',
  'shield': 'M12 2.5 4.5 5.5v6c0 4.6 3.1 8.3 7.5 10 4.4-1.7 7.5-5.4 7.5-10v-6z'
      'M9.3 12.2l1.9 1.9 3.5-3.9',
  'chip': 'M4.5 4.5h15v15h-15zM8.5 8.5h7v7h-7zM9.5 4.5V2M14.5 4.5V2M9.5 22v-2.5'
      'M14.5 22v-2.5M4.5 9.5H2M4.5 14.5H2M22 9.5h-2.5M22 14.5h-2.5',
  'gear': 'M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 1 0 0-7M12 5.5'
      'a6.5 6.5 0 1 0 0 13 6.5 6.5 0 1 0 0-13M12 2.5v3M12 18.5v3M2.5 12h3'
      'M18.5 12h3M5.2 5.2l2.1 2.1M16.7 16.7l2.1 2.1M5.2 18.8l2.1-2.1M16.7 7.3'
      'l2.1-2.1',
  'compass': 'M12 2.8a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 1 0 0-3.6M11.1 6.3 6.4 18'
      'M12.9 6.3 17.6 18M6.4 18l-1.2 3.2M17.6 18l1.2 3.2M7.4 14.6'
      'a9.5 9.5 0 0 0 9.2 0',
  'building': 'M4 21.5V7.5l8-5 8 5v14M3 21.5h18M9.5 21.5v-5h5v5M7.5 10.5h2M14.5 10.5'
      'h2M7.5 14h2M14.5 14h2',
  // Гуманитарные
  'column': 'M12 2.5 22 8H2zM3.5 10.5h17M7 10.5v9M12 10.5v9M17 10.5v9M2.5 21.5h19',
  'scroll': 'M8 3.5h9.5a2 2 0 0 1 2 2v12.5a2.5 2.5 0 0 1-2.5 2.5H7'
      'a2.5 2.5 0 0 1-2.5-2.5V16H8M8 3.5a2 2 0 0 0-2 2V16M11 8h5.5M11 12h5.5',
  'book': 'M12 6.5v14M12 6.5 8 4.5 3 5.5v13l5-.7 4 2.2M12 6.5l4-2 5 1v13l-5-.7-4 2.2',
  'brain': 'M12 4.6a3.3 3.3 0 0 0-6 1.7A2.9 2.9 0 0 0 4.2 9'
      'a2.9 2.9 0 0 0 1.1 2.3 3 3 0 0 0 1.4 5.2A3.1 3.1 0 0 0 12 18.2zM12 4.6'
      'a3.3 3.3 0 0 1 6 1.7A2.9 2.9 0 0 1 19.8 9'
      'a2.9 2.9 0 0 1-1.1 2.3 3 3 0 0 1-1.4 5.2A3.1 3.1 0 0 1 12 18.2zM12 4.6'
      'v13.6',
  'people': 'M9 11a3.2 3.2 0 1 0 0-6.4 3.2 3.2 0 1 0 0 6.4M2.5 20.5v-1.2'
      'c0-2.9 2.9-5.3 6.5-5.3s6.5 2.4 6.5 5.3v1.2M16.3 5.3a3.2 3.2 0 0 1 0 6'
      'M18 14.4c2 .8 3.5 2.6 3.5 4.9v1.2',
  // Языки
  'letter': 'M3.5 20.5 12 3l8.5 17.5M7 14.5h10',
  'chat': 'M20.5 15.5a1.5 1.5 0 0 1-1.5 1.5H8l-4 3.5V6.5A1.5 1.5 0 0 1 5.5 5H19'
      'a1.5 1.5 0 0 1 1.5 1.5zM8 9h8M8 12.5h5',
  // Экономика и право
  'chart': 'M4 3v17.5h17M8 20.5v-6M12.5 20.5V10M17 20.5V6',
  'coins': 'M9 4.5a5 5 0 1 0 0 10 5 5 0 1 0 0-10M15 9.5'
      'a5 5 0 1 0 0 10 5 5 0 1 0 0-10M9 6.8v5.4M7.7 8.3h2.2M7.8 10.7h2.2',
  'briefcase': 'M3.5 8.5h17v11h-17zM9 8.5V6.2a1.6 1.6 0 0 1 1.6-1.7h2.8'
      'A1.6 1.6 0 0 1 15 6.2v2.3M3.5 13.5h17M10.5 13.5h3',
  'scale': 'M12 3.5v17M7.5 20.5h9M4.5 7.5h15M12 7.5V4.8M6.5 7.5 3.5 14h6z'
      'M17.5 7.5 14.5 14h6z',
  // Искусство и медиа
  'palette': 'M12 3.5a8.5 8.5 0 1 0 0 17'
      'c1.2 0 2.1-.9 2.1-2 0-.5-.2-1-.5-1.4-.3-.4-.5-.8-.5-1.3 0-1.1.9-2 2-2'
      'h2A4.4 4.4 0 0 0 21.5 9c-.6-3.2-4.4-5.5-9.5-5.5zM7.6 8.6h.01M11.6 6.6'
      'h.01M15.6 8.1h.01M6.6 12.6h.01',
  'pen': 'M3 21l1-3.7L15.5 5.8l2.7 2.7L6.7 20zM14 7.3l2.7 2.7M18.2 3.1'
      'l2.7 2.7-2.4 2.4-2.7-2.7z',
  'note': 'M8 19.5a3 2.4 0 1 0 0-4.8 3 2.4 0 1 0 0 4.8M11 17V3.5M11 3.5c3 1 5 2.5 5 5.5',
  'camera': 'M3.5 7.5H7l1.8-2.5h6.4L17 7.5h3.5v12h-17zM12 17a4 4 0 1 0 0-8 4 4 0 1 0 0 8',
  'mic': 'M12 3a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V6a3 3 0 0 1 3-3M6 11v1'
      'a6 6 0 0 0 12 0v-1M12 18v3M9 21.5h6',
  // Медицина
  'pulse': 'M12 20.5S3.5 15.2 3.5 9.4A4.7 4.7 0 0 1 12 6.6a4.7 4.7 0 0 1 8.5 2.8'
      'c0 5.8-8.5 11.1-8.5 11.1zM6.6 11.4h2.6l1.4-2.6 2 4.6 1.4-2h3.4',
  'stethoscope': 'M6 3.5v4a4.5 4.5 0 0 0 9 0v-4M4.5 3.5h3M13.5 3.5h3M10.5 12v2.2'
      'a4.3 4.3 0 0 0 8.6 0v-1.4M19.1 8.4'
      'a2.2 2.2 0 1 0 0 4.4 2.2 2.2 0 1 0 0-4.4',
  'pill': 'M8.5 5.5h7a5.5 5.5 0 0 1 0 11h-7a5.5 5.5 0 0 1 0-11M12 5.5v11',
  // Прикладные
  'wrench': 'M15.5 3.5a5 5 0 0 0-6.3 6.3L3.6 15.4a2.1 2.1 0 0 0 3 3l5.6-5.6'
      'a5 5 0 0 0 6.3-6.3l-2.9 2.9-2.9-.7-.7-2.9z',
  'chef': 'M6.5 16.5h11v4h-11zM6.5 16.5a4 4 0 1 1 1.7-7.6A4.2 4.2 0 0 1 12 5.5'
      'a4.2 4.2 0 0 1 3.8 3.4 4 4 0 1 1 1.7 7.6M9.5 16.5v-4M14.5 16.5v-4',
  'scissors': 'M6 4.5 18 17M18 4.5 6 17M6.5 20.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 1 0 0 5'
      'M17.5 20.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 1 0 0 5',
  'car': 'M2.5 16.5h19v-4l-2-.6-2.2-4.1a2 2 0 0 0-1.8-1.1h-7a2 2 0 0 0-1.8 1.1'
      'L4.5 11.9l-2 .6zM7 11.9h10M4.5 16.5v3h3v-3M16.5 16.5v3h3v-3M6.5 14.2'
      'h.01M17.5 14.2h.01',
  'plane': 'M12 2.5c1.1 0 1.9 1.2 1.9 2.8v3.9l7.6 4.4v2.4l-7.6-2.2v3.8l2.4 1.8v1.6'
      'L12 20l-4.3 1v-1.6l2.4-1.8v-3.8L2.5 16v-2.4l7.6-4.4V5.3'
      'c0-1.6.8-2.8 1.9-2.8z',
  'sprout': 'M12 20.5v-8M12 12.5c0-3.6-2.6-6.2-6.2-6.2 0 3.6 2.6 6.2 6.2 6.2'
      'M12 12.5c0-3 2.2-5.5 5.2-5.5 0 3-2.2 5.5-5.2 5.5M8 20.5h8',
  // Спорт
  'ball': 'M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 1 0 0-19M12 7.4l4.4 3.2-1.7 5.2'
      'H9.3l-1.7-5.2zM12 2.5v4.9M16.4 10.6 21 9.1M14.7 15.8l2.9 3.9M9.3 15.8'
      'l-2.9 3.9M7.6 10.6 3 9.1',
};

/// SVG-документ с глифом — flutter_svg рисует его через SvgPicture.string.
String coverIconSvg(String? icon, {Color color = Colors.white, double strokeWidth = 1.6}) {
  final path = kCoverIconPaths[icon] ?? kCoverIconPaths['book']!;
  final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="#$hex" stroke-width="$strokeWidth" stroke-linecap="round" '
      'stroke-linejoin="round"><path d="$path"/></svg>';
}

Color coverPreviewBackground(CoverColorOption color) => color.base;

/// Локализованные подписи иконок — предмет, для которого иконка предлагается.
const Map<String, Map<String, String>> kCoverIconLabels = {
  'sigma': {'RU': 'Математика', 'EN': 'Mathematics', 'KZ': 'Математика'},
  'cube': {'RU': 'Геометрия', 'EN': 'Geometry', 'KZ': 'Геометрия'},
  'dice': {'RU': 'Статистика', 'EN': 'Statistics', 'KZ': 'Статистика'},
  'atom': {'RU': 'Физика', 'EN': 'Physics', 'KZ': 'Физика'},
  'flask': {'RU': 'Химия', 'EN': 'Chemistry', 'KZ': 'Химия'},
  'dna': {'RU': 'Биология', 'EN': 'Biology', 'KZ': 'Биология'},
  'microscope': {'RU': 'Микробиология', 'EN': 'Microbiology', 'KZ': 'Микробиология'},
  'leaf': {'RU': 'Экология', 'EN': 'Ecology', 'KZ': 'Экология'},
  'telescope': {'RU': 'Астрономия', 'EN': 'Astronomy', 'KZ': 'Астрономия'},
  'globe': {'RU': 'География', 'EN': 'Geography', 'KZ': 'География'},
  'code': {'RU': 'Программирование', 'EN': 'Programming', 'KZ': 'Бағдарламалау'},
  'browser': {'RU': 'Веб-разработка', 'EN': 'Web Development', 'KZ': 'Веб-әзірлеу'},
  'database': {'RU': 'Базы данных', 'EN': 'Databases', 'KZ': 'Дерекқорлар'},
  'network': {'RU': 'Сети', 'EN': 'Networks', 'KZ': 'Желілер'},
  'shield': {'RU': 'Кибербезопасность', 'EN': 'Cybersecurity', 'KZ': 'Киберқауіпсіздік'},
  'chip': {'RU': 'Электроника', 'EN': 'Electronics', 'KZ': 'Электроника'},
  'gear': {'RU': 'Механика', 'EN': 'Mechanical Eng.', 'KZ': 'Механика'},
  'compass': {'RU': 'Архитектура', 'EN': 'Architecture', 'KZ': 'Сәулет'},
  'building': {'RU': 'Строительство', 'EN': 'Construction', 'KZ': 'Құрылыс'},
  'column': {'RU': 'История', 'EN': 'History', 'KZ': 'Тарих'},
  'scroll': {'RU': 'Философия', 'EN': 'Philosophy', 'KZ': 'Философия'},
  'book': {'RU': 'Литература', 'EN': 'Literature', 'KZ': 'Әдебиет'},
  'brain': {'RU': 'Психология', 'EN': 'Psychology', 'KZ': 'Психология'},
  'people': {'RU': 'Обществознание', 'EN': 'Social Studies', 'KZ': 'Қоғамтану'},
  'letter': {'RU': 'Языки', 'EN': 'Languages', 'KZ': 'Тілдер'},
  'chat': {'RU': 'Речь и общение', 'EN': 'Communication', 'KZ': 'Сөйлеу мәдениеті'},
  'chart': {'RU': 'Экономика', 'EN': 'Economics', 'KZ': 'Экономика'},
  'coins': {'RU': 'Финансы', 'EN': 'Finance', 'KZ': 'Қаржы'},
  'briefcase': {'RU': 'Менеджмент', 'EN': 'Management', 'KZ': 'Менеджмент'},
  'scale': {'RU': 'Право', 'EN': 'Law', 'KZ': 'Құқық'},
  'palette': {'RU': 'Искусство', 'EN': 'Art', 'KZ': 'Өнер'},
  'pen': {'RU': 'Графический дизайн', 'EN': 'Graphic Design', 'KZ': 'Графикалық дизайн'},
  'note': {'RU': 'Музыка', 'EN': 'Music', 'KZ': 'Музыка'},
  'camera': {'RU': 'Фотография', 'EN': 'Photography', 'KZ': 'Фотография'},
  'mic': {'RU': 'Журналистика', 'EN': 'Journalism', 'KZ': 'Журналистика'},
  'pulse': {'RU': 'Медицина', 'EN': 'Medicine', 'KZ': 'Медицина'},
  'stethoscope': {'RU': 'Сестринское дело', 'EN': 'Nursing', 'KZ': 'Мейіргер ісі'},
  'pill': {'RU': 'Фармация', 'EN': 'Pharmacy', 'KZ': 'Фармация'},
  'wrench': {'RU': 'Технология', 'EN': 'Technology', 'KZ': 'Технология'},
  'chef': {'RU': 'Кулинария', 'EN': 'Culinary Arts', 'KZ': 'Аспаздық'},
  'scissors': {'RU': 'Швейное дело', 'EN': 'Fashion & Sewing', 'KZ': 'Тігін ісі'},
  'car': {'RU': 'Автодело', 'EN': 'Automotive', 'KZ': 'Автоісі'},
  'plane': {'RU': 'Авиация', 'EN': 'Aviation', 'KZ': 'Авиация'},
  'sprout': {'RU': 'Агрономия', 'EN': 'Agriculture', 'KZ': 'Агрономия'},
  'ball': {'RU': 'Физкультура', 'EN': 'Physical Education', 'KZ': 'Дене шынықтыру'},
};

const Map<String, Map<String, String>> kCoverGroupLabels = {
  'exact': {'RU': 'Точные науки', 'EN': 'Exact sciences', 'KZ': 'Нақты ғылымдар'},
  'natural': {'RU': 'Естественные науки', 'EN': 'Natural sciences', 'KZ': 'Жаратылыстану'},
  'tech': {'RU': 'IT и инженерия', 'EN': 'Technology', 'KZ': 'IT және инженерия'},
  'humanities': {'RU': 'Гуманитарные', 'EN': 'Humanities', 'KZ': 'Гуманитарлық'},
  'language': {'RU': 'Языки', 'EN': 'Languages', 'KZ': 'Тілдер'},
  'business': {'RU': 'Экономика и право', 'EN': 'Business & law', 'KZ': 'Экономика және құқық'},
  'arts': {'RU': 'Искусство и медиа', 'EN': 'Arts & media', 'KZ': 'Өнер және медиа'},
  'health': {'RU': 'Медицина', 'EN': 'Health', 'KZ': 'Медицина'},
  'applied': {'RU': 'Прикладные', 'EN': 'Applied', 'KZ': 'Қолданбалы'},
  'sport': {'RU': 'Спорт', 'EN': 'Sport', 'KZ': 'Спорт'},
};

String coverGroupLabel(String group, String lang, [String fallback = '']) =>
    kCoverGroupLabels[group]?[lang] ??
    kCoverGroupLabels[group]?['EN'] ??
    (fallback.isEmpty ? group : fallback);

String coverIconLabel(String icon, String lang) =>
    kCoverIconLabels[icon]?[lang] ?? kCoverIconLabels[icon]?['EN'] ?? icon;
