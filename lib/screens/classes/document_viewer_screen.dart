import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:provider/provider.dart';

import '../../models/annotation.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../utils/ai_ask.dart';
import '../../utils/file_opener.dart';
import '../../utils/haptics.dart';
import '../../utils/highlight_anchor.dart';
import '../../utils/pdf_highlight_geometry.dart';
import '../../widgets/toast.dart';
import 'widgets/detail_page_theme.dart';
import 'widgets/highlight_menu.dart';
import 'widgets/highlights_section.dart';
import 'widgets/selection_handle.dart';

/// Просмотрщик материала лекции внутри приложения: PDF, Word и презентации.
///
/// Ради него подключён pdfrx: системный вьюер iOS показывает документ, но не
/// отдаёт ни текстового слоя, ни событий выделения — без них выделения,
/// заметки и «Спросить AI» на страницах материала невозможны. Word и
/// презентации бэкенд отдаёт как PDF (LibreOffice, результат кэшируется),
/// поэтому у всех форматов один экран и одинаковый набор функций.
class DocumentViewerScreen extends StatefulWidget {
  final String url;
  final String name;
  final int lectureId;
  final int classId;
  final int fileIndex;
  final String lectureTitle;

  /// Открыть выделение сразу при запуске (переход из «Моих выделений»).
  final int? focusAnnotationId;

  const DocumentViewerScreen({
    super.key,
    required this.url,
    required this.name,
    required this.lectureId,
    required this.classId,
    required this.fileIndex,
    required this.lectureTitle,
    this.focusAnnotationId,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final _controller = PdfViewerController();
  List<Annotation> _annotations = [];

  /// Текст страниц, уже полученный от PDFium. Догружается ВНЕ кадра отрисовки
  /// (см. _ensureText): просить его прямо во время paint нельзя — это setState
  /// посреди построения кадра, и приложение падало бы на каждой странице
  /// с пометками.
  final Map<int, PdfPageText> _pageTexts = {};
  final Set<int> _textLoading = {};

  String? _pdfUrl;
  String? _error;
  bool _loading = true;
  int _page = 1;
  int _pageCount = 0;
  int? _flashId;

  /// Чип с номером страницы — подсказка при перелистывании, а не постоянный
  /// элемент: иначе он висит поверх первой строки документа.
  bool _pageChipVisible = false;
  Timer? _pageChipTimer;

  /// Текущее выделение — по нему показывается нижняя панель действий.
  PdfPageTextRange? _selection;
  String _selectionText = '';
  Annotation? _selectedSaved;

  /// Палец опустился на саму панель. Просмотрщик снимает выделение по любому
  /// касанию вне страницы, и без этого флага цвет/заметка применялись бы уже
  /// к пустому выделению — то есть ни к чему.
  bool _menuTouched = false;

  bool get _isOffice {
    final ext = widget.name.split('.').last.toLowerCase();
    return const {'ppt', 'pptx', 'doc', 'docx', 'rtf'}.contains(ext);
  }

  /// Overlay-панель нужна только для уже сохранённой пометки: у нового
  /// выделения её строит сам просмотрщик (см. _buildSelectionMenu).
  bool get _menuVisible => _selectedSaved != null;

  OverlayEntry? _dockEntry;

  /// Панель действий показываем через Overlay: свой слой выделения просмотрщик
  /// держит поверх содержимого экрана, и панель, положенная рядом в Stack,
  /// просто не получала бы касаний.
  void _syncDock() {
    if (!mounted) return;
    if (!_menuVisible) {
      _dockEntry?.remove();
      _dockEntry = null;
      return;
    }
    if (_dockEntry != null) {
      _dockEntry!.markNeedsBuild();
      return;
    }
    _dockEntry = OverlayEntry(builder: (ctx) {
      final l = context.read<L10n>();
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: SafeArea(
          top: false,
          child: Listener(
            onPointerDown: (_) => _menuTouched = true,
            child: HighlightMenuDock(
              visible: true,
              child: HighlightMenu(
                t: l.t,
                existing: _selectedSaved,
                onColor: _onColor,
                onNote: _onNote,
                onAskAi: _askAi,
                onCopy: _onCopy,
                onDelete: _selectedSaved != null
                    ? () {
                        final a = _selectedSaved!;
                        _closeMenu();
                        _delete(a);
                      }
                    : null,
              ),
            ),
          ),
        ),
      );
    });
    Overlay.of(context, rootOverlay: true).insert(_dockEntry!);
  }

  @override
  void initState() {
    super.initState();
    _prepare();
    _loadAnnotations();
    _controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChange);
    _pageChipTimer?.cancel();
    _dockEntry?.remove();
    _dockEntry = null;
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted || !_controller.isReady) return;
    final p = _controller.pageNumber ?? 1;
    final total = _controller.document.pages.length;
    if (p != _page || total != _pageCount) {
      final pageChanged = p != _page || _pageCount == 0;
      setState(() {
        _page = p;
        _pageCount = total;
      });
      if (pageChanged) _flashPageChip();
    }
  }

  /// Показать чип и убрать его через полторы секунды.
  void _flashPageChip() {
    _pageChipTimer?.cancel();
    if (!_pageChipVisible) setState(() => _pageChipVisible = true);
    _pageChipTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _pageChipVisible = false);
    });
  }

  /// Word и презентации бэкенд отдаёт в виде PDF. Конвертация кэшируется, но
  /// первый раз занимает несколько секунд — поэтому у ожидания свой текст.
  Future<void> _prepare() async {
    try {
      if (_isOffice) {
        final res = await context.read<ApiService>().previewPdf(widget.url);
        _pdfUrl = (res['pdf_url'] ?? '').toString();
        if (_pdfUrl!.isEmpty) throw StateError('empty pdf_url');
      } else {
        _pdfUrl = widget.url.split('#').first;
      }
    } catch (e) {
      if (mounted) {
        // Показываем ЧТО именно не так (истёкшая ссылка, нет конвертера на
        // сервере, старая версия API) — иначе на экране безликое «не удалось»,
        // по которому непонятно, чинить сервер или просто открыть заново.
        final detail = e is DioException && e.response?.data is Map
            ? (e.response!.data as Map)['detail']?.toString()
            : null;
        final code = e is DioException ? e.response?.statusCode : null;
        _error = [
          context.read<L10n>().t('preview_failed'),
          if (detail != null && detail.isNotEmpty) detail,
          if (detail == null && code != null) 'HTTP $code',
        ].join('\n');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAnnotations() async {
    try {
      final rows = await context
          .read<ApiService>()
          .getAnnotations(lectureId: widget.lectureId);
      if (!mounted) return;
      setState(() => _annotations = rows
          .map((e) => Annotation.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((a) => a.fileIndex == widget.fileIndex)
          .toList());
      if (widget.focusAnnotationId != null) {
        _goToAnnotation(widget.focusAnnotationId!);
      }
    } catch (_) {
      // Офлайн — документ всё равно читается, просто без пометок.
    }
  }

  List<Annotation> _onPage(int pageNumber) =>
      _annotations.where((a) => a.page == pageNumber).toList();

  // ── Текст страницы и геометрия пометок ─────────────────────────────────

  /// Просит текст страницы, если его ещё нет. Загрузка запускается ПОСЛЕ
  /// текущего кадра — _paintPage и pageOverlaysBuilder вызываются во время
  /// отрисовки.
  void _ensureText(int pageNumber) {
    if (_pageTexts.containsKey(pageNumber) || _textLoading.contains(pageNumber)) {
      return;
    }
    if (!_controller.isReady) return;
    final pages = _controller.document.pages;
    if (pageNumber < 1 || pageNumber > pages.length) return;
    _textLoading.add(pageNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final text = await pages[pageNumber - 1].loadStructuredText();
        if (!mounted) return;
        setState(() => _pageTexts[pageNumber] = text);
      } finally {
        _textLoading.remove(pageNumber);
      }
    });
  }

  List<({Annotation a, List<PdfRect> rects})> _geometryFor(int pageNumber) {
    final text = _pageTexts[pageNumber];
    if (text == null) {
      if (_onPage(pageNumber).isNotEmpty) _ensureText(pageNumber);
      return const [];
    }
    final out = <({Annotation a, List<PdfRect> rects})>[];
    for (final a in _onPage(pageNumber)) {
      final rects = highlightRects(text, a);
      if (rects.isNotEmpty) out.add((a: a, rects: rects));
    }
    return out;
  }

  void _paintPage(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    for (final item in _geometryFor(page.pageNumber)) {
      // Страница документа всегда светлая, поэтому тон пометки не зависит от
      // темы приложения — иначе на тёмной теме подсветка почти не видна.
      final base = highlightSwatch(item.a.color);
      final active = item.a.id == _flashId || item.a.id == _selectedSaved?.id;
      final paint = Paint()
        ..color = base.withValues(alpha: active ? 0.72 : 0.42);
      for (final r in item.rects) {
        final rect = r
            .toRect(page: page, scaledPageSize: pageRect.size)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(0.5), const Radius.circular(2)),
          paint,
        );
      }
    }
  }

  /// Прозрачные области поверх пометок — чтобы по ним можно было тапнуть.
  List<Widget> _pageOverlays(
      BuildContext context, Rect pageRect, PdfPage page) {
    final widgets = <Widget>[];
    for (final item in _geometryFor(page.pageNumber)) {
      for (final r in item.rects) {
        final rect = r.toRect(page: page, scaledPageSize: pageRect.size);
        widgets.add(Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: PdfOverlayInteractionRegion(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectSaved(item.a),
              child: const SizedBox.expand(),
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  // ── Выделение ──────────────────────────────────────────────────────────

  Future<void> _onSelectionChange(PdfTextSelection selection) async {
    if (!selection.hasSelectedText) {
      if (_menuTouched) return; // это касание самой панели, фрагмент помним
      _selection = null;
      _selectionText = '';
      return;
    }
    final ranges = await selection.getSelectedTextRanges();
    final text = await selection.getSelectedText();
    if (!mounted || ranges.isEmpty || text.trim().isEmpty) return;
    // Намеренно без setState: перерисовка всего экрана на каждое движение
    // пальца рвала перетаскивание маркеров. Панель действий строит сам
    // просмотрщик, ей наше состояние не нужно.
    _selection = ranges.first;
    _selectionText = text;
    if (_selectedSaved != null) {
      setState(() => _selectedSaved = null);
    }
  }

  void _selectSaved(Annotation a) {
    hapticSelection();
    _controller.textSelectionDelegate.clearTextSelection();
    setState(() {
      _selectedSaved = a;
      _selection = null;
      _selectionText = '';
    });
  }

  void _closeMenu() {
    _menuTouched = false;
    _controller.textSelectionDelegate.clearTextSelection();
    if (mounted) {
      setState(() {
        _selection = null;
        _selectionText = '';
        _selectedSaved = null;
      });
    }
  }

  // ── Создание и правка ──────────────────────────────────────────────────

  /// Доводит выделение до целых слов, когда палец отпустил маркер.
  ///
  /// Просмотрщик выделяет ровно те символы, до которых дотянулся палец, и
  /// выделение застывало на половине слова. В приложениях Apple оно всегда
  /// прилипает к словам — здесь то же самое, но в момент отпускания: делать
  /// это на каждое движение нельзя, перетаскивание сбивалось бы.
  Future<void> _snapSelectionToWords() async {
    final delegate = _controller.textSelectionDelegate;
    if (!delegate.hasSelectedText) return;
    final ranges = await delegate.getSelectedTextRanges();
    if (ranges.isEmpty) return;

    final first = ranges.first;
    final last = ranges.last;
    final start = snapToWords(first.pageText.fullText, first.start, first.end).start;
    // Конечная граница считается по своей странице (выделение может идти через
    // разворот), индекс у точки конца включительный — отсюда -1.
    final end = snapToWords(last.pageText.fullText, last.start, last.end).end;
    if (start == first.start && end == last.end) return;

    await delegate.setTextSelectionPointRange(PdfTextSelectionRange.fromPoints(
      PdfTextSelectionPoint(first.pageText, start),
      PdfTextSelectionPoint(last.pageText, (end - 1).clamp(0, last.pageText.charRects.length - 1)),
    ));
  }

  /// Высота строки, к которой прицеплен маркер, в экранных пикселях.
  double _anchorLineHeight(PdfTextSelectionAnchor anchor) {
    final zoom = _controller.isReady ? _controller.currentZoom : 1.0;
    return (anchor.rect.height * zoom).clamp(14.0, 30.0);
  }

  /// Маркер выделения (см. SelectionHandle): маленький шарик с широкой
  /// зоной захвата — просмотрщик вешает pan-жест на сам виджет.
  Widget _buildSelectionHandle(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) =>
      SelectionHandle(
        isStart: anchor.type == PdfTextSelectionAnchorType.a,
        lineHeight: _anchorLineHeight(anchor),
        color: detailAccent(context),
        dragging: state == PdfViewerTextSelectionAnchorHandleState.dragging,
      );

  /// Сдвиг зоны захвата: шарик стоит в её центре, поэтому виджет двигаем так,
  /// чтобы шарик оказался у самого края выделения, а запас под палец ушёл
  /// вокруг него, а не на текст.
  Offset _handleOffset(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) {
    const half = SelectionHandle.defaultTouchSize / 2;
    final lineHeight = _anchorLineHeight(anchor);
    // Начальный маркер прицеплен правым нижним углом к началу выделения,
    // конечный — левым верхним к его концу (см. pdfrx).
    return anchor.type == PdfTextSelectionAnchorType.a
        ? Offset(half, half - (lineHeight / 2 + SelectionHandle.ballSize / 2) + lineHeight)
        : Offset(-half, -half + (lineHeight / 2 + SelectionHandle.ballSize / 2) - lineHeight);
  }

  /// Панель действий для нового выделения — пришвартована к низу экрана: у
  /// самого выделения она перекрывала бы выделенный текст.
  Widget? _buildSelectionMenu(
      BuildContext context, PdfViewerContextMenuBuilderParams params) {
    final delegate = params.textSelectionDelegate;
    if (!params.isTextSelectionEnabled || !delegate.hasSelectedText) {
      return null;
    }
    final l = context.read<L10n>();

    Future<PdfPageTextRange?> firstRange() async {
      final ranges = await delegate.getSelectedTextRanges();
      // Выделение может пересечь границу страниц; пометка живёт на одной
      // странице, поэтому берём ту, где выделение началось.
      return ranges.isEmpty ? null : ranges.first;
    }

    void dismiss() {
      params.dismissContextMenu();
      delegate.clearTextSelection();
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: HighlightMenuDock(
          visible: true,
          child: HighlightMenu(
            t: l.t,
            onColor: (c) async {
              final range = await firstRange();
              dismiss();
              if (range != null) await _create(range, c);
            },
            onNote: () async {
              final range = await firstRange();
              dismiss();
              if (range == null) return;
              final note = await _askNote(null);
              if (note == null) return;
              await _create(range, 'yellow',
                  comment: note.isEmpty ? null : note);
            },
            onAskAi: () async {
              final text = await delegate.getSelectedText();
              final range = await firstRange();
              dismiss();
              if (mounted) _askAiWith(text, range?.pageNumber);
            },
            onCopy: () async {
              final text = await delegate.getSelectedText();
              dismiss();
              if (text.isNotEmpty) {
                await Clipboard.setData(ClipboardData(text: text));
              }
            },
          ),
        ),
      ),
    );
  }

  /// Вопрос по произвольному фрагменту (ещё не сохранённому выделению).
  void _askAiWith(String rawText, int? page) {
    final text = rawText.trim();
    if (text.isEmpty) return;
    Navigator.pop(
        context,
        AiAsk(
          text: buildQuotePrompt(
            lang: context.read<L10n>().lang,
            text: text,
            lectureTitle: widget.lectureTitle,
            page: page ?? _page,
          ),
          lectureId: widget.lectureId,
          page: page ?? _page,
          quote: text,
        ));
  }

  Future<Annotation?> _create(PdfPageTextRange range, String color,
      {String? comment}) async {
    final text = range.pageText.fullText;
    // Выделение прилипает к словам, как в приложениях Apple: просмотрщик
    // отдаёт ровно те символы, на которые попал палец, и пометка обрывалась
    // на половине слова.
    final snapped = snapToWords(text, range.start, range.end);
    final anchor = anchorAround(text, snapped.start, snapped.end);
    // Номер страницы у выделения бывает нулевым (текст страницы пришёл не из
    // нумерованного источника) — тогда берём страницу, которая сейчас открыта:
    // пометка без страницы не нашлась бы потом ни в списке, ни при переходе.
    final pageNumber = range.pageNumber > 0
        ? range.pageNumber
        : (_controller.pageNumber ?? _page);
    try {
      final row = await context.read<ApiService>().createAnnotation(
            lectureId: widget.lectureId,
            classId: widget.classId,
            fileIndex: widget.fileIndex,
            page: pageNumber,
            selectedText: text.substring(snapped.start, snapped.end),
            startOffset: snapped.start,
            endOffset: snapped.end,
            prefix: anchor.prefix,
            suffix: anchor.suffix,
            color: color,
            comment: comment,
          );
      final created = Annotation.fromJson(row);
      if (mounted) setState(() => _annotations = [..._annotations, created]);
      return created;
    } catch (_) {
      if (mounted) {
        showToast(context, context.read<L10n>().t('hl_save_failed'),
            error: true);
      }
      return null;
    }
  }

  Future<void> _patch(Annotation a, {String? color, String? comment}) async {
    final before = _annotations;
    setState(() => _annotations = _annotations
        .map((x) =>
            x.id == a.id ? x.copyWith(color: color, comment: comment) : x)
        .toList());
    try {
      final row = await context
          .read<ApiService>()
          .updateAnnotation(a.id, color: color, comment: comment);
      final updated = Annotation.fromJson(row);
      if (mounted) {
        setState(() {
          _annotations =
              _annotations.map((x) => x.id == a.id ? updated : x).toList();
          if (_selectedSaved?.id == a.id) _selectedSaved = updated;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _annotations = before);
        showToast(context, context.read<L10n>().t('hl_save_failed'),
            error: true);
      }
    }
  }

  Future<void> _delete(Annotation a) async {
    final before = _annotations;
    setState(() {
      _annotations = _annotations.where((x) => x.id != a.id).toList();
      if (_selectedSaved?.id == a.id) _selectedSaved = null;
    });
    try {
      await context.read<ApiService>().deleteAnnotation(a.id);
    } catch (_) {
      if (mounted) {
        setState(() => _annotations = before);
        showToast(context, context.read<L10n>().t('hl_save_failed'),
            error: true);
      }
    }
  }

  Future<String?> _askNote(String? initial) async {
    final ctrl = TextEditingController(text: initial ?? '');
    final l = context.read<L10n>();
    return showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l.t('hl_note')),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            placeholder: l.t('hl_note_hint'),
            style: const TextStyle(fontSize: 15),
          ),
        ),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx), child: Text(l.t('cancel'))),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l.t('save')),
          ),
        ],
      ),
    );
  }

  void _askAi() {
    final saved = _selectedSaved;
    final text = (saved?.selectedText ?? _selectionText).trim();
    if (text.isEmpty) return;
    final page = saved?.page ?? _selection?.pageNumber ?? _page;
    // Отдельного ИИ-экрана нет: вопрос возвращается на экран класса и уходит
    // в существующий тред его вкладки «ИИ».
    Navigator.pop(
        context,
        AiAsk(
          text: buildQuotePrompt(
            lang: context.read<L10n>().lang,
            text: text,
            lectureTitle: widget.lectureTitle,
            page: page,
          ),
          annotationId: saved?.id,
          lectureId: widget.lectureId,
          page: page,
          quote: saved == null ? text : null,
        ));
  }

  Future<void> _onColor(String color) async {
    final saved = _selectedSaved;
    if (saved != null) {
      _closeMenu();
      await _patch(saved, color: color);
      return;
    }
    final range = _selection;
    _closeMenu();
    if (range != null) await _create(range, color);
  }

  Future<void> _onNote() async {
    final saved = _selectedSaved;
    final range = _selection;
    final note = await _askNote(saved?.comment);
    if (note == null) return;
    _closeMenu();
    if (saved != null) {
      await _patch(saved, comment: note);
    } else if (range != null) {
      await _create(range, 'yellow', comment: note.isEmpty ? null : note);
    }
  }

  Future<void> _onCopy() async {
    final text = _selectedSaved?.selectedText ?? _selectionText;
    _closeMenu();
    if (text.isNotEmpty) await Clipboard.setData(ClipboardData(text: text));
  }

  // ── Переходы и списки ──────────────────────────────────────────────────

  Future<void> _goToAnnotation(int id) async {
    final a = _annotations.where((x) => x.id == id).firstOrNull;
    if (a == null) return;
    if (_controller.isReady && a.page > 0) {
      await _controller.goToPage(pageNumber: a.page);
    }
    if (!mounted) return;
    setState(() => _flashId = a.id);
    await Future.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _flashId = null);
  }

  void _showHighlights() {
    final l = context.read<L10n>();
    hapticSelection();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _Sheet(
        title: l.t('hl_section'),
        child: _annotations.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(32, 30, 32, 40),
                child: Text(l.t('hl_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: detailText2(context))),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                    HighlightsSection(
                      items: _annotations,
                      t: l.t,
                      hideHeader: true,
                      onTap: (a) {
                        Navigator.pop(ctx);
                        _goToAnnotation(a.id);
                      },
                      onDelete: _delete,
                    ),
                  ]),
      ),
    );
  }

  void _showPages() {
    if (!_controller.isReady) return;
    final l = context.read<L10n>();
    hapticSelection();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => _Sheet(
        title: l.t('pages'),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 0.7,
          ),
          itemCount: _pageCount,
          itemBuilder: (_, i) {
            final n = i + 1;
            final marks = _onPage(n).length;
            final current = n == _page;
            return GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                _controller.goToPage(pageNumber: n);
              },
              child: Column(children: [
                Expanded(
                    child: Container(
                  decoration: BoxDecoration(
                    color: CupertinoColors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: current
                          ? detailAccent(context)
                          : detailBorder(context),
                      width: current ? 2 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: PdfPageView(
                      document: _controller.document, pageNumber: n),
                )),
                const SizedBox(height: 5),
                Text(marks > 0 ? '$n · $marks' : '$n',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      color: current
                          ? detailAccent(context)
                          : detailText2(context),
                    )),
              ]),
            );
          },
        ),
      ),
    );
  }

  void _showMore() {
    final l = context.read<L10n>();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(widget.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showHighlights();
            },
            child: Text(l.t('hl_section')),
          ),
          if (_pageCount > 1)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showPages();
              },
              child: Text(l.t('pages')),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.t('cancel')),
        ),
      ),
    );
  }

  // ── Вёрстка ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDock());
    final l = context.read<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B0B0B) : const Color(0xFFF2F2F7);

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: detailAccent(context),
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: Stack(children: [
          Positioned.fill(child: _content(l)),
          // Матовая шапка поверх страницы — как в Books.
          Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _NavBar(
                title: widget.lectureTitle.isNotEmpty
                    ? widget.lectureTitle
                    : widget.name,
                subtitle: widget.name,
                onBack: () => Navigator.pop(context),
                onMore: _showMore,
              )),
          if (_pageCount > 0)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 54,
              left: 0,
              right: 0,
              child: Center(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _pageChipVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _PageChip(text: '$_page ${l.t('of')} $_pageCount'),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _content(L10n l) {
    if (_loading) {
      return _Centered(children: [
        const CupertinoActivityIndicator(radius: 14),
        const SizedBox(height: 14),
        // Конвертация Word/презентации занимает несколько секунд — честно
        // говорим, чего ждём, вместо безмолвного спиннера.
        Text(_isOffice ? l.t('preview_preparing') : l.t('loading'),
            style: TextStyle(fontSize: 14, color: detailText2(context))),
      ]);
    }
    if (_error != null) {
      return _Centered(children: [
        Icon(CupertinoIcons.doc_text, size: 34, color: detailText2(context)),
        const SizedBox(height: 14),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: detailText2(context))),
        const SizedBox(height: 18),
        // Конвертация Word/презентации может быть недоступна (старая версия
        // сервера, сбой LibreOffice) — не оставляем человека в тупике: файл
        // читается системным просмотрщиком, просто без выделений.
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          color: detailAccent(context),
          borderRadius: BorderRadius.circular(100),
          onPressed: () => openRemoteFile(
              context, context.read<ApiService>(), widget.url, widget.name),
          child: Text(l.t('open_in_system_viewer'),
              style: const TextStyle(fontSize: 15, color: CupertinoColors.white)),
        ),
      ]);
    }

    // Шапка (48) + чип страницы (26) + просветы: страница начинается ниже.
    final topInset = MediaQuery.paddingOf(context).top + 96;
    return PdfViewer.uri(
      Uri.parse(_pdfUrl!),
      controller: _controller,
      params: PdfViewerParams(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0B0B0B)
            : const Color(0xFFF2F2F7),
        margin: 10,
        // Верх и низ заняты матовой шапкой и панелью — отводим страницы
        // из-под них, чтобы текст не оказывался под управлением.
        layoutPages: (pages, params) {
          var y = topInset;
          var width = 0.0;
          for (final p in pages) {
            if (p.width > width) width = p.width;
          }
          final rects = <Rect>[];
          for (final p in pages) {
            rects.add(Rect.fromLTWH(
                (width - p.width) / 2 + params.margin, y, p.width, p.height));
            y += p.height + params.margin;
          }
          return PdfPageLayout(
            pageLayouts: rects,
            documentSize: Size(width + params.margin * 2, y + 96),
          );
        },
        textSelectionParams: PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: true,
          onTextSelectionChange: _onSelectionChange,
          // Свои маркеры вместо стандартных синих треугольников 30×30: как в
          // iOS — тонкая ножка и небольшой шарик с большой зоной захвата.
          buildSelectionHandle: _buildSelectionHandle,
          calcSelectionHandleOffset: _handleOffset,
          onSelectionHandlePanStart: (_) => hapticSelection(),
          onSelectionHandlePanEnd: (_) {
            hapticLight();
            _snapSelectionToWords();
          },
        ),
        // Панель действий отдаём просмотрщику как его контекстное меню: свой
        // слой выделения он держит поверх содержимого, и панель, положенная
        // рядом в Stack, касаний бы не получала.
        buildContextMenu: _buildSelectionMenu,
        pagePaintCallbacks: [_paintPage],
        pageOverlaysBuilder: _pageOverlays,
        loadingBannerBuilder: (context, downloaded, total) =>
            const Center(child: CupertinoActivityIndicator(radius: 14)),
        errorBannerBuilder: (context, error, stack, docRef) =>
            _Centered(children: [
          Icon(CupertinoIcons.doc_text, size: 34, color: detailText2(context)),
          const SizedBox(height: 14),
          Text(l.t('preview_failed'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: detailText2(context))),
        ]),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final List<Widget> children;
  const _Centered({required this.children});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      );
}

/// Матовая шапка в духе Books: название материала по центру, «‹» и «⋯» по краям.
class _NavBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onMore;
  const _NavBar({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (isDark ? const Color(0xFF0B0B0B) : CupertinoColors.white)
        .withValues(alpha: 0.82);
    final text1 = detailText1(context);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          color: bg,
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          child: SizedBox(
            height: 48,
            child: Row(children: [
              _BarButton(
                  icon: CupertinoIcons.chevron_left,
                  color: text1,
                  onTap: onBack),
              Expanded(
                  child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: text1,
                      )),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: detailText2(context))),
                ],
              )),
              _BarButton(
                  icon: CupertinoIcons.ellipsis, color: text1, onTap: onMore),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BarButton(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
            width: 48, height: 48, child: Icon(icon, size: 22, color: color)),
      );
}

/// «12 из 47» — маленькая капсула над страницей.
class _PageChip extends StatelessWidget {
  final String text;
  const _PageChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF2A2A2E) : CupertinoColors.white)
            .withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: detailBorder(context),
          width: 1 / MediaQuery.devicePixelRatioOf(context),
        ),
        boxShadow: [
          BoxShadow(
              color: CupertinoColors.black.withValues(alpha: 0.06),
              blurRadius: 8)
        ],
      ),
      child: Text(text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: detailText1(context),
          )),
    );
  }
}

/// Шторка в стиле iOS: ручка, заголовок, содержимое.
class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _Sheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * 0.62,
      decoration: BoxDecoration(
        color: detailBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          width: 36,
          height: 5,
          margin: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: detailText2(context).withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: detailText1(context),
              )),
        ),
        Expanded(child: child),
      ]),
    );
  }
}
