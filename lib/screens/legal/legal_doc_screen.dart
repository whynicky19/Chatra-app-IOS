import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/inset_group.dart' show hairline;

/// Общий макет юридического документа (политика конфиденциальности, условия
/// использования): крупный заголовок в духе iOS, который сворачивается в
/// строку навигации при скролле, лид-абзац и список разделов.
///
/// Раньше шапка (иконка, дата, вступление) была россыпью голого текста над
/// карточками разделов: вступление читалось как «карточка, у которой потеряли
/// фон», а не как осознанный лид. Теперь у него своя тихая подложка, отличная
/// от карточек разделов, — иерархия «обложка → лид → разделы» видна сразу.
class LegalDocScreen extends StatefulWidget {
  const LegalDocScreen({
    super.key,
    required this.titleKey,
    required this.headerIcon,
    required this.updated,
    required this.introKey,
    required this.sections,
  });

  final String titleKey;
  final IconData headerIcon;
  final String updated;
  final String introKey;

  /// (иконка, ключ заголовка, ключ текста) для каждой карточки.
  final List<(IconData, String, String)> sections;

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  final _scroll = ScrollController();

  /// Крупный заголовок уехал под навбар — показываем компактный.
  bool _collapsed = false;

  /// Порог переключения. Меньше высоты блока с крупным заголовком, чтобы
  /// компактный проявлялся ровно в момент, когда крупный уходит за край, а не
  /// раньше и не позже.
  static const _collapseAt = 52.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final collapsed = _scroll.hasClients && _scroll.offset > _collapseAt;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final title = l.t(widget.titleKey);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // extendBodyBehindAppBar-подход вручную: контент проезжает ПОД матовой
      // строкой навигации (см. §«Материалы» HIG) — только тогда у стекла есть
      // что размывать, и вместо жёсткого разделителя получается край,
      // проявляющийся сам собой.
      body: Stack(children: [
        Positioned.fill(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(20, topInset + 52, 20, 48),
            children: [
              // ── Обложка ──────────────────────────────────────────────
              Container(
                width: 52, height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Icon(widget.headerIcon, size: 26, color: primary),
              ),
              const SizedBox(height: 16),
              // Крупный заголовок: отрицательный трекинг и плотная интерлиньяж
              // — по мере роста кегля буквы читаются слишком раскинутыми, а
              // строки — слишком разъехавшимися.
              Text(title,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    height: 1.08,
                    letterSpacing: -0.9,
                    color: adaptiveText1(context),
                  )),
              const SizedBox(height: 10),
              _updatedPill(context, l),
              const SizedBox(height: 22),

              // ── Лид ──────────────────────────────────────────────────
              // Тихая заливка акцентом без рамки и тени: явно не одна из
              // карточек-разделов ниже, но и не безнадзорный текст.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: isDark ? 0.10 : 0.07),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Text(l.t(widget.introKey),
                    style: TextStyle(
                      fontSize: 16.5,
                      height: 1.55,
                      letterSpacing: -0.2,
                      color: adaptiveTextSoft(context),
                    )),
              ),
              const SizedBox(height: 22),

              // ── Разделы ──────────────────────────────────────────────
              for (var i = 0; i < widget.sections.length; i++) ...[
                _card(context, isDark, primary, widget.sections[i]),
                if (i != widget.sections.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),

        // ── Строка навигации поверх контента ───────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: _navBar(context, isDark, title, topInset),
        ),
      ]),
    );
  }

  Widget _updatedPill(BuildContext context, L10n l) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.clock, size: 12, color: adaptiveText4(context)),
          const SizedBox(width: 5),
          // Мелкий текст — трекинг около нуля: сжимать его, как крупный
          // заголовок, значит ухудшить разборчивость.
          Text('${l.t('pp_updated_label')}: ${widget.updated}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: adaptiveText3(context),
              )),
        ]),
      ),
    );
  }

  Widget _navBar(BuildContext context, bool isDark, String title, double topInset) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(top: topInset),
          decoration: BoxDecoration(
            // Пока крупный заголовок на месте, панель полностью прозрачна и
            // не отделена ничем: отделять нечего. Разделитель и матовая
            // заливка появляются ровно тогда, когда под панель заезжает текст.
            color: _collapsed ? bg.withValues(alpha: 0.80) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: _collapsed ? adaptiveBorder(context) : Colors.transparent,
                width: hairline(context),
              ),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                tooltip: 'Назад',
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: AnimatedOpacity(
                  opacity: _collapsed ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: adaptiveText1(context),
                      )),
                ),
              ),
              // Симметрия кнопке «назад», чтобы компактный заголовок не
              // выглядел сдвинутым влево относительно оптического центра.
              const SizedBox(width: 48),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, bool isDark, Color primary,
      (IconData, String, String) section) {
    final l = context.read<L10n>();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: isDark ? C.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.card),
        // Волосяная рамка вместо тени: сгруппированные списки iOS отделяются
        // краем на общем фоне, а не «приподнятостью» материала.
        border: Border.all(color: adaptiveBorder(context), width: hairline(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: isDark ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Icon(section.$1, size: 17, color: primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(l.t(section.$2),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: adaptiveText1(context),
                )),
          ),
        ]),
        const SizedBox(height: 12),
        Text(l.t(section.$3),
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              letterSpacing: -0.2,
              color: adaptiveText2(context),
            )),
      ]),
    );
  }
}
