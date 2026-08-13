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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../providers/l10n_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/cover_art.dart';
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

class _CoverAppearanceState extends State<CoverAppearance> {
  CoverOptions _options = CoverOptionsCache.current;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    if (CoverOptionsCache.isLoaded) return;
    final api = context.read<ApiService>();
    final loaded = await CoverOptionsCache.load(api.getCoverOptions);
    if (mounted) setState(() => _options = loaded);
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
        _iconGrid(context, l, selected),
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

  /// Превью: сохранённая обложка, если она уже сгенерирована, иначе локальный
  /// градиент с иконкой в том же визуальном языке.
  Widget _preview(BuildContext context, L10n l, CoverColorOption color) {
    final url = widget.coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(gradient: coverPreviewGradient(color)),
        child: Stack(fit: StackFit.expand, children: [
          if (url != null && url.isNotEmpty)
            CachedNetworkImage(
              imageUrl: context.read<ApiService>().fixUrl(url),
              fit: BoxFit.cover,
              memCacheWidth: 900,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => const SizedBox.shrink(),
              // Обложка не загрузилась — молча показываем локальное превью,
              // а не пустой прямоугольник.
              errorWidget: (_, __, ___) => _glyph(),
            )
          else
            _glyph(),
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

  Widget _glyph() => Center(
        child: SvgPicture.string(
          coverIconSvg(widget.icon),
          width: 66,
          height: 66,
        ),
      );

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
                  gradient: coverPreviewGradient(c),
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

  Widget _iconGrid(BuildContext context, L10n l, CoverColorOption selected) => GridView.count(
        crossAxisCount: 6,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final i in _options.icons)
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
