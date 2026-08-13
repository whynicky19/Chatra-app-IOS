/// Оформление обложек предметов: палитра, предметные иконки, локальное превью.
///
/// Набор цветов и иконок приходит с бэкенда (GET /classes/cover/options,
/// см. services/cover_art.py) — он же рисует готовую обложку, поэтому зашивать
/// свой список в приложении нельзя: пользователь выбрал бы вариант, которого
/// сервер не знает. Здесь только кэш ответа, запасной набор на случай
/// отсутствия сети и SVG-глифы для превью и пикера.
///
/// Глифы повторяют пути из composables/useCoverArt.ts (веб), поэтому выбор
/// иконки выглядит одинаково на обоих клиентах.
///
/// Иконка НЕ входит в сохранённую картинку: бэкенд генерирует только фон и
/// специально оставляет центр кадра пустым. Рисует иконку виджет
/// widgets/subject_cover.dart — он и есть единственное место, где обложка
/// собирается для показа.
library;

import 'package:flutter/material.dart';

class CoverColorOption {
  final String id;

  /// Акцент бренда: свотч в пикере и цвет выделения.
  final Color hex;

  /// Заливка фона обложки — из неё строится превью до генерации.
  final Color base;

  const CoverColorOption(this.id, this.hex, this.base);
}

class CoverIconOption {
  final String id;
  final String subject;
  const CoverIconOption(this.id, this.subject);
}

class CoverOptions {
  final List<CoverColorOption> colors;
  final List<CoverIconOption> icons;
  final String defaultColor;
  final String defaultIcon;
  final bool aiAvailable;

  const CoverOptions({
    required this.colors,
    required this.icons,
    required this.defaultColor,
    required this.defaultIcon,
    required this.aiAvailable,
  });

  factory CoverOptions.fromJson(Map<String, dynamic> json) {
    List<CoverColorOption> colors = [];
    for (final raw in (json['colors'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final hex = parseHex(m['hex'] as String?);
      final base = parseHex(m['base'] as String?);
      if (hex == null || base == null) continue;
      colors.add(CoverColorOption(m['id'] as String, hex, base));
    }
    final icons = [
      for (final raw in (json['icons'] as List? ?? const []))
        CoverIconOption(
          (raw as Map)['id'] as String,
          (raw['subject'] as String?) ?? '',
        ),
    ];
    // Пустой ответ (старый бэкенд, обрезанный прокси) не должен оставить
    // пикер без единого варианта — тогда предмет вообще нельзя было бы создать.
    if (colors.isEmpty || icons.isEmpty) return kFallbackCoverOptions;
    return CoverOptions(
      colors: colors,
      icons: icons,
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
    CoverColorOption('blue', Color(0xFF0A84FF), Color(0xFF1C5FC4)),
    CoverColorOption('purple', Color(0xFF8B5CF6), Color(0xFF6D45CE)),
    CoverColorOption('green', Color(0xFF22C55E), Color(0xFF1E9B54)),
    CoverColorOption('orange', Color(0xFFF97316), Color(0xFFD2600F)),
    CoverColorOption('red', Color(0xFFEF4444), Color(0xFFC93A3A)),
    CoverColorOption('pink', Color(0xFFEC4899), Color(0xFFC43B80)),
    CoverColorOption('teal', Color(0xFF00B1C9), Color(0xFF0891A6)),
    CoverColorOption('indigo', Color(0xFF6366F1), Color(0xFF4B4ECC)),
  ],
  icons: [
    CoverIconOption('sigma', 'Mathematics'),
    CoverIconOption('atom', 'Physics'),
    CoverIconOption('flask', 'Chemistry'),
    CoverIconOption('dna', 'Biology'),
    CoverIconOption('code', 'Computer Science'),
    CoverIconOption('column', 'History'),
    CoverIconOption('globe', 'Geography'),
    CoverIconOption('letter', 'English'),
    CoverIconOption('book', 'Literature'),
    CoverIconOption('chart', 'Economics'),
    CoverIconOption('palette', 'Art'),
    CoverIconOption('note', 'Music'),
  ],
  defaultColor: 'teal',
  defaultIcon: 'book',
  aiAvailable: true,
);

/// Кэш набора на процесс: он меняется только с деплоем бэкенда, дёргать его
/// при каждом открытии формы создания предмета незачем.
///
/// Живёт здесь, а не в виджете, чтобы пикер не ходил в сеть из initState в
/// тестах (висящий таймер роняет flutter_test) и чтобы набор переиспользовался
/// между экраном создания и листом редактирования.
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
    // Без сети пикер всё равно обязан открыться — иначе предмет вообще
    // нельзя создать.
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
  'sigma': 'M18.5 4.5H6l7 7.5-7 7.5h12.5',
  'atom': 'M12 12m-1.6 0a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0 -3.2 0'
      ' M12 12m-10.5 0a10.5 4.6 0 1 0 21 0a10.5 4.6 0 1 0 -21 0',
  'flask': 'M9 2.5h6M10 2.5v6.5L3.5 21h17L14 9V2.5',
  'dna': 'M8.6 3c0 6 6.8 12 6.8 18M15.4 3c0 6-6.8 12-6.8 18'
      'M9.6 7h4.8M8.2 10.5h7.6M8.2 13.5h7.6M9.6 17h4.8',
  'code': 'M8.5 6.5 3 12l5.5 5.5M15.5 6.5 21 12l-5.5 5.5M13.6 4.2l-3.2 15.6',
  'column': 'M12 2.5 22 8H2zM3.5 10.5h17M7 10.5v9M12 10.5v9M17 10.5v9M2.5 21.5h19',
  'globe': 'M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 1 0 0-19'
      'M12 2.5a5 9.5 0 1 0 0 19 5 9.5 0 1 0 0-19M2.5 12h19M4.4 7h15.2M4.4 17h15.2',
  'letter': 'M3.5 20.5 12 3l8.5 17.5M7 14.5h10',
  'book': 'M12 6.5v14M12 6.5 8 4.5 3 5.5v13l5-.7 4 2.2M12 6.5l4-2 5 1v13l-5-.7-4 2.2',
  'chart': 'M4 3v17.5h17M8 20.5v-6M12.5 20.5V10M17 20.5V6',
  'palette': 'M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 1 0 0-19'
      'M8 8.5h.01M12 6.8h.01M16 8.4h.01M7.4 12.5h.01M14.8 14.4a2.1 2.1 0 1 0 0 .01',
  'note': 'M8 19.5a3 2.4 0 1 0 0-4.8 3 2.4 0 1 0 0 4.8M11 17V3.5M11 3.5c3 1 5 2.5 5 5.5',
};

/// SVG-документ с глифом — flutter_svg рисует его через SvgPicture.string.
/// Обводкой (а не заливкой), как и на вебе: у всех иконок одна «весовая»
/// толщина, поэтому набор выглядит одной системой.
String coverIconSvg(String? icon, {Color color = Colors.white, double strokeWidth = 1.6}) {
  final path = kCoverIconPaths[icon] ?? kCoverIconPaths['book']!;
  final hex = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="#$hex" stroke-width="$strokeWidth" stroke-linecap="round" '
      'stroke-linejoin="round"><path d="$path"/></svg>';
}

/// Подложка превью — ровная заливка того же тона, что и фон обложки
/// (render_background() на бэкенде): выбор цвета не должен обманывать
/// ожидания. Именно заливка, а не градиент — обложка теперь плоский
/// графический баннер.
Color coverPreviewBackground(CoverColorOption color) => color.base;

/// Локализованные подписи иконок — предмет, для которого иконка предлагается.
const Map<String, Map<String, String>> kCoverIconLabels = {
  'sigma': {'RU': 'Математика', 'EN': 'Mathematics', 'KZ': 'Математика'},
  'atom': {'RU': 'Физика', 'EN': 'Physics', 'KZ': 'Физика'},
  'flask': {'RU': 'Химия', 'EN': 'Chemistry', 'KZ': 'Химия'},
  'dna': {'RU': 'Биология', 'EN': 'Biology', 'KZ': 'Биология'},
  'code': {'RU': 'Информатика', 'EN': 'Computer Science', 'KZ': 'Информатика'},
  'column': {'RU': 'История', 'EN': 'History', 'KZ': 'Тарих'},
  'globe': {'RU': 'География', 'EN': 'Geography', 'KZ': 'География'},
  'letter': {'RU': 'Языки', 'EN': 'Languages', 'KZ': 'Тілдер'},
  'book': {'RU': 'Литература', 'EN': 'Literature', 'KZ': 'Әдебиет'},
  'chart': {'RU': 'Экономика', 'EN': 'Economics', 'KZ': 'Экономика'},
  'palette': {'RU': 'Искусство', 'EN': 'Art', 'KZ': 'Өнер'},
  'note': {'RU': 'Музыка', 'EN': 'Music', 'KZ': 'Музыка'},
};

String coverIconLabel(String icon, String lang) =>
    kCoverIconLabels[icon]?[lang] ?? kCoverIconLabels[icon]?['EN'] ?? icon;
