/// Выбор оформления обложки предмета: цвет + превью.
/// Тематику обложки бэкенд выводит из названия курса; выбранный цвет задаёт палитру.
/// При classId == null (предмет ещё не создан) кнопки генерации нет.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

  /// 'ai_hero' | 'ai' (legacy) | 'fallback' | 'upload' | null — см. classes.cover_source.
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
          Text(widget.error!,
              style: const TextStyle(fontSize: 12, color: C.red)),
        ],
        const SizedBox(height: 18),
        _label(context, l.t('cover_color')),
        _colorRow(context, selected),
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
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: adaptiveText3(context))),
      );

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
            icon: null,
            color: color.id,
            coverSource: widget.coverSource,
            iconSize: 60,
            memCacheWidth: 900,
          ),
          if (widget.generating)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white)),
                    const SizedBox(height: 12),
                    Text(l.t('cover_generating'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    // Генерация занимает до пары минут — без объяснения долгий
                    // спиннер выглядит как зависание.
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(l.t('cover_generating_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 12,
                              height: 1.35)),
                    ),
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
              onTap:
                  widget.generating ? null : () => widget.onColorChanged(c.id),
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
                    ? const Icon(CupertinoIcons.check_mark,
                        size: 16, color: Colors.white)
                    : null,
              ),
            ),
        ],
      );

  Widget _generateButton(
      BuildContext context, L10n l, CoverColorOption selected) {
    final hasCover = widget.coverUrl != null && widget.coverUrl!.isNotEmpty;
    return OutlinedButton(
      onPressed: widget.generating ? null : widget.onGenerate,
      style: OutlinedButton.styleFrom(
        // Ровная кнопка на всю ширину с фиксированной высотой и радиусом
        // кнопок приложения: OutlinedButton.icon до этого жил своей жизнью —
        // сжимался под контент и разъезжался по вертикали.
        minimumSize: const Size.fromHeight(48),
        fixedSize: const Size.fromHeight(48),
        padding: EdgeInsets.zero,
        backgroundColor: selected.hex.withValues(alpha: 0.08),
        side:
            BorderSide(color: selected.hex.withValues(alpha: 0.5), width: 1.4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button)),
      ),
      child: widget.generating
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2.2)),
              const SizedBox(width: 10),
              Text(l.t('cover_generating'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected.hex)),
            ])
          : Text(
              hasCover ? l.t('cover_regenerate') : l.t('cover_generate'),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: selected.hex),
            ),
    );
  }
}
