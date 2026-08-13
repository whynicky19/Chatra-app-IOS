/// Выбор оформления обложки предмета: цвет + предметная иконка + превью.
///
/// Загрузки своей фотографии здесь нет: обложку рисует бэкенд по паре
/// «цвет + иконка» (POST /classes/{id}/cover/generate). Тот же виджет
/// используется и при создании, и при редактировании предмета, поэтому выбор
/// выглядит одинаково в обоих местах — и совпадает с вебом
/// (components/classes/CoverAppearance.vue).
///
/// Пока предмет ещё не создан (classId == null) кнопки генерации нет:
/// показывается локальное превью, а генерацию запускает вызывающий экран
/// сразу после создания.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../providers/l10n_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/cover_art.dart';
import 'subject_cover.dart';
import 'tappable.dart';

class CoverAppearance extends StatefulWidget {
  final String color;
  final String icon;

  /// Сохранённая обложка предмета; null, пока предмет не создан.
  final String? coverUrl;

  /// 'ai' | 'fallback' | 'upload' | null — см. classes.cover_source.
  final String? coverSource;

  /// null — предмет ещё не создан, кнопки генерации нет.
  final int? classId;

  final bool generating;
  final String? error;

  final ValueChanged<String> onColorChanged;
  final ValueChanged<String> onIconChanged;
  final VoidCallback onGenerate;

  const CoverAppearance({
    super.key,
    required this.color,
    required this.icon,
    required this.onColorChanged,
    required this.onIconChanged,
    required this.onGenerate,
    this.coverUrl,
    this.coverSource,
    this.classId,
    this.generating = false,
    this.error,
  });

  @override
  State<CoverAppearance> createState() => _CoverAppearanceState();
}

/// Сколько символов помещается в одну полоску пикера — она же ширина сетки.
const _kIconsPerRow = 6;

class _CoverAppearanceState extends State<CoverAppearance> {
  CoverOptions _options = CoverOptionsCache.current;

  /// Символов больше сорока: по умолчанию видна только первая полоска, весь
  /// список открывается кнопкой. Развёрнутая сетка занимала восемь рядов и
  /// выталкивала за экран название предмета и кнопку сохранения.
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _syncExpanded();
    _loadOptions();
  }

  @override
  void didUpdateWidget(CoverAppearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon) _syncExpanded();
  }

  /// Выбранный символ обязан быть виден. Если он не попал в первую полоску
  /// (например «Кулинария» из последней секции), список открыт сразу — иначе
  /// при редактировании непонятно, что вообще выбрано.
  void _syncExpanded() {
    if (_expanded) return;
    final firstRow = _options.icons.take(_kIconsPerRow).map((i) => i.id);
    if (!firstRow.contains(widget.icon)) _expanded = true;
  }

  Future<void> _loadOptions() async {
    if (CoverOptionsCache.isLoaded) return;
    final api = context.read<ApiService>();
    final loaded = await CoverOptionsCache.load(api.getCoverOptions);
    if (mounted) {
      setState(() {
        _options = loaded;
        _syncExpanded();
      });
    }
  }

  /// Символы секциями; неизвестная или пустая группа — одним блоком в конец,
  /// чтобы ответ старого бэкенда без groups не потерял ни одного варианта.
  List<({String label, List<CoverIconOption> icons})> _sections(String lang) {
    final result = <({String label, List<CoverIconOption> icons})>[];
    final taken = <String>{};
    for (final g in _options.groups) {
      final icons = _options.icons.where((i) => i.group == g.id).toList();
      if (icons.isEmpty) continue;
      taken.addAll(icons.map((i) => i.id));
      result.add((label: coverGroupLabel(g.id, lang, g.label), icons: icons));
    }
    final rest = _options.icons.where((i) => !taken.contains(i.id)).toList();
    if (rest.isNotEmpty) result.add((label: '', icons: rest));
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final selected = _options.colorFor(widget.color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, l.t('cover_appearance')),
        _preview(context, l, selected),
        if (widget.error != null) ...[
          const SizedBox(height: 8),
          Text(widget.error!, style: const TextStyle(fontSize: 12, color: C.red)),
        ] else if (widget.coverSource == 'fallback' && widget.coverUrl != null) ...[
          const SizedBox(height: 8),
          Text(l.t('cover_fallback_note'),
              style: TextStyle(fontSize: 12, color: adaptiveText3(context))),
        ],
        const SizedBox(height: 18),
        _label(context, l.t('cover_color')),
        _colorRow(context, selected),
        const SizedBox(height: 18),
        _label(context, l.t('cover_icon')),
        _iconPicker(context, l, selected),
        if (widget.classId != null && _options.aiAvailable) ...[
          const SizedBox(height: 18),
          _generateButton(context, l, selected),
        ],
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: adaptiveText3(context))),
      );

  /// Превью — тот же виджет, что рисует обложку во всём остальном приложении,
  /// поэтому здесь видно ровно то, что получит пользователь: фон (сохранённый
  /// или ровная заливка цвета) + иконка поверх.
  Widget _preview(BuildContext context, L10n l, CoverColorOption color) {
    final url = widget.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          SubjectCover(
            url: (url == null || url.isEmpty)
                ? null
                : context.read<ApiService>().fixUrl(url),
            icon: widget.icon,
            color: color.id,
            iconSize: 60,
            memCacheWidth: 900,
          ),
          if (widget.generating)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                const SizedBox(height: 12),
                Text(l.t('cover_generating'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _colorRow(BuildContext context, CoverColorOption selected) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final c in _options.colors)
            Tappable(
              onTap: widget.generating ? null : () => widget.onColorChanged(c.id),
              label: c.id,
              minSize: 0,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.base,
                  shape: BoxShape.circle,
                  border: c.id == selected.id
                      ? Border.all(color: adaptiveText1(context), width: 2.5)
                      : null,
                ),
                child: c.id == selected.id
                    ? const Icon(CupertinoIcons.check_mark, size: 16, color: Colors.white)
                    : null,
              ),
            ),
        ],
      );

  Widget _iconPicker(BuildContext context, L10n l, CoverColorOption selected) {
    final all = _options.icons;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_expanded)
          _iconGrid(context, l, selected, all.take(_kIconsPerRow).toList())
        else
          // Развёрнутый список ограничен по высоте и скроллится внутри: иначе
          // он растягивает форму на несколько экранов.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in _sections(l.lang)) ...[
                    if (s.label.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6, left: 2),
                        child: Text(
                          s.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            // w600, а не w700: на мелком кегле шкала
                            // app_theme.dart жирный запрещает.
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: adaptiveText4(context),
                          ),
                        ),
                      ),
                    _iconGrid(context, l, selected, s.icons),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
        if (all.length > _kIconsPerRow)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Tappable(
              onTap: () => setState(() => _expanded = !_expanded),
              label: _expanded
                  ? l.t('cover_icons_less')
                  : '${l.t('cover_icons_all')} (${all.length})',
              minSize: 0,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _expanded
                      ? l.t('cover_icons_less')
                      : '${l.t('cover_icons_all')} (${all.length})',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: selected.hex),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                  size: 13,
                  color: selected.hex,
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _iconGrid(BuildContext context, L10n l, CoverColorOption selected,
          List<CoverIconOption> icons) =>
      GridView.count(
        crossAxisCount: _kIconsPerRow,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final i in icons)
            Tappable(
              onTap: widget.generating ? null : () => widget.onIconChanged(i.id),
              label: coverIconLabel(i.id, l.lang),
              minSize: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: adaptiveSurface2(context),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  border: Border.all(
                    color: i.id == widget.icon ? selected.hex : adaptiveBorder(context),
                    width: i.id == widget.icon ? 2 : 1.2,
                  ),
                ),
                child: Center(
                  child: SvgPicture.string(
                    coverIconSvg(i.id,
                        color: i.id == widget.icon ? selected.hex : adaptiveText3(context)),
                    width: 21,
                    height: 21,
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _generateButton(BuildContext context, L10n l, CoverColorOption selected) {
    final hasCover = widget.coverUrl != null && widget.coverUrl!.isNotEmpty;
    return OutlinedButton.icon(
      onPressed: widget.generating ? null : widget.onGenerate,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: BorderSide(color: selected.hex.withValues(alpha: 0.5), width: 1.4),
      ),
      icon: widget.generating
          ? const SizedBox(
              width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(CupertinoIcons.sparkles, size: 17, color: selected.hex),
      label: Text(widget.generating
          ? l.t('cover_generating')
          : (hasCover ? l.t('cover_regenerate') : l.t('cover_generate'))),
    );
  }
}
