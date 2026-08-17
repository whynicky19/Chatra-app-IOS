import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/annotation.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../utils/ai_ask.dart';
import '../../utils/haptics.dart';
import '../../widgets/toast.dart';
import 'document_viewer_screen.dart';
import 'widgets/detail_page_theme.dart';
import 'widgets/file_card.dart';
import 'widgets/highlight_menu.dart';
import 'widgets/highlights_section.dart';

/// Полноэкранная страница лекции (замена модального bottom sheet).
/// Открывается через Navigator.push с нативным iOS push-переходом
/// (обеспечивается CupertinoPageTransitionsBuilder в AppTheme).
///
/// Текст лекции можно выделять: цвет, заметка и «Спросить AI». Выделения живут
/// на сервере (см. ApiService.getAnnotations) — те же, что на сайте.
class LectureDetailScreen extends StatefulWidget {
  final String title;
  final String dateLabel;
  final String content;
  final List<String> files;
  final void Function(BuildContext context, String url, String name) onOpenFile;

  /// Без id лекции/класса выделения выключены (страницу открывают и из мест,
  /// где поста как такового нет).
  final int? lectureId;
  final int? classId;

  const LectureDetailScreen({
    super.key,
    required this.title,
    required this.dateLabel,
    required this.content,
    required this.files,
    required this.onOpenFile,
    this.lectureId,
    this.classId,
  });

  @override
  State<LectureDetailScreen> createState() => _LectureDetailScreenState();
}

class _LectureDetailScreenState extends State<LectureDetailScreen> {
  /// Все выделения этой лекции — включая сделанные на сайте внутри PDF: они
  /// показываются в списке «Мои выделения», хотя в тексте их места нет.
  List<Annotation> _annotations = [];
  final _bodyKey = GlobalKey();
  final _scrollCtrl = ScrollController();
  // Смещения выделения относительно текста лекции даёт SelectionListener —
  // сам SelectableRegionState отдаёт только готовую строку, без позиции.
  final _selectionNotifier = SelectionListenerNotifier();
  int? _flashId;

  bool get _canAnnotate => widget.lectureId != null && widget.classId != null;

  @override
  void initState() {
    super.initState();
    if (_canAnnotate) _loadAnnotations();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _selectionNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadAnnotations() async {
    try {
      final rows = await context.read<ApiService>().getAnnotations(lectureId: widget.lectureId);
      if (!mounted) return;
      setState(() => _annotations = rows
          .map((e) => Annotation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList());
    } catch (_) {
      // Офлайн — страница остаётся читаемой, просто без пометок.
    }
  }

  /// Пометки, которые реально лежат в тексте лекции (в списке показываем все).
  List<Annotation> get _textAnnotations => _annotations
      .where((a) => a.isLectureText && a.endOffset <= widget.content.length && a.endOffset > a.startOffset)
      .toList()
    ..sort((a, b) => a.startOffset.compareTo(b.startOffset));

  // ── Создание и правка ──────────────────────────────────────────────────

  Future<Annotation?> _create(TextSelection sel, String color, {String? comment}) async {
    final text = widget.content.substring(sel.start, sel.end);
    try {
      final row = await context.read<ApiService>().createAnnotation(
        lectureId: widget.lectureId!,
        classId: widget.classId!,
        selectedText: text,
        startOffset: sel.start,
        endOffset: sel.end,
        // Якорь по соседнему тексту: по нему выделение находится на другом
        // клиенте, где смещения могут не совпасть (см. backend).
        prefix: widget.content.substring((sel.start - 60).clamp(0, sel.start), sel.start),
        suffix: widget.content.substring(sel.end, (sel.end + 60).clamp(sel.end, widget.content.length)),
        color: color,
        comment: comment,
      );
      final created = Annotation.fromJson(row);
      if (mounted) setState(() => _annotations = [..._annotations, created]);
      return created;
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('hl_save_failed'), error: true);
      return null;
    }
  }

  Future<void> _patch(Annotation a, {String? color, String? comment}) async {
    // Оптимистично: цвет и заметка меняются сразу, ошибка откатывает.
    final before = _annotations;
    setState(() => _annotations = _annotations
        .map((x) => x.id == a.id ? x.copyWith(color: color, comment: comment) : x)
        .toList());
    try {
      final row = await context.read<ApiService>().updateAnnotation(a.id, color: color, comment: comment);
      final updated = Annotation.fromJson(row);
      if (mounted) setState(() => _annotations = _annotations.map((x) => x.id == a.id ? updated : x).toList());
    } catch (_) {
      if (mounted) {
        setState(() => _annotations = before);
        showToast(context, context.read<L10n>().t('hl_save_failed'), error: true);
      }
    }
  }

  Future<void> _delete(Annotation a) async {
    final before = _annotations;
    setState(() => _annotations = _annotations.where((x) => x.id != a.id).toList());
    try {
      await context.read<ApiService>().deleteAnnotation(a.id);
    } catch (_) {
      if (mounted) {
        setState(() => _annotations = before);
        showToast(context, context.read<L10n>().t('hl_save_failed'), error: true);
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
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: Text(l.t('cancel'))),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l.t('save')),
          ),
        ],
      ),
    );
  }

  /// Материалы с текстовым слоем открываем своим просмотрщиком — там работают
  /// выделения и заметки. Остальное (таблицы, архивы, картинки) по-прежнему
  /// уходит в системный вьюер.
  static const _viewerExts = {'pdf', 'ppt', 'pptx', 'doc', 'docx', 'rtf'};

  Future<void> _openFile(int index, String url, String name) async {
    final ext = name.split('.').last.toLowerCase();
    if (!_canAnnotate || index < 0 || !_viewerExts.contains(ext)) {
      widget.onOpenFile(context, url, name);
      return;
    }
    final result = await Navigator.push<Object?>(context, MaterialPageRoute(
      builder: (_) => DocumentViewerScreen(
        url: url,
        name: name,
        lectureId: widget.lectureId!,
        classId: widget.classId!,
        fileIndex: index,
        lectureTitle: widget.title,
      ),
    ));
    // Вопрос из просмотрщика прокидываем дальше — на экран класса, который
    // переключится на вкладку «ИИ».
    if (result is AiAsk && mounted) {
      Navigator.pop(context, result);
      return;
    }
    // Вернулись обратно: в материале могли появиться новые пометки.
    if (mounted) await _loadAnnotations();
  }

  // ── «Спросить AI» ──────────────────────────────────────────────────────
  // Отдельного ИИ-экрана здесь нет: возвращаем вопрос на экран класса, он
  // переключается на свою вкладку «ИИ» и отправляет его в существующий тред.

  void _askAi({Annotation? saved, String? rawText, int page = 0}) {
    final text = (saved?.selectedText ?? rawText ?? '').trim();
    if (text.isEmpty) return;
    Navigator.pop(context, AiAsk(
      text: buildQuotePrompt(
        lang: context.read<L10n>().lang,
        text: text,
        lectureTitle: widget.title,
        page: saved?.page ?? page,
      ),
      annotationId: saved?.id,
      lectureId: widget.lectureId!,
      page: saved?.page ?? page,
      quote: saved == null ? text : null,
    ));
  }

  // ── Меню выделения ─────────────────────────────────────────────────────

  Widget _selectionMenu(BuildContext context, SelectableRegionState state) {
    final l = context.read<L10n>();
    final sel = _currentSelection();
    if (sel == null) return const SizedBox.shrink();
    final selectedText = widget.content.substring(sel.start, sel.end);

    void done() => state.hideToolbar(true);

    // Панель пришвартована к низу экрана, а не висит у выделения: всплывающее
    // меню перекрывает как раз выделенный текст (см. HighlightMenu).
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: HighlightMenuDock(
          visible: true,
          child: HighlightMenu(
            t: l.t,
            onColor: (c) async { done(); await _create(sel, c); },
            onNote: () async {
              done();
              final note = await _askNote(null);
              if (note == null) return;
              await _create(sel, 'yellow', comment: note.isEmpty ? null : note);
            },
            onAskAi: () { done(); _askAi(rawText: selectedText); },
            onCopy: () { done(); Clipboard.setData(ClipboardData(text: selectedText)); },
          ),
        ),
      ),
    );
  }

  /// Диапазон текущего выделения в координатах widget.content: под
  /// SelectionListener лежит только текст лекции, поэтому его смещения и есть
  /// индексы в content.
  TextSelection? _currentSelection() {
    if (!_selectionNotifier.registered) return null;
    final range = _selectionNotifier.selection.range;
    if (range == null) return null;
    final start = range.startOffset.clamp(0, widget.content.length);
    final end = range.endOffset.clamp(0, widget.content.length);
    if (end <= start) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  /// Карточка действий по уже сохранённому выделению (тап по пометке/строке).
  Future<void> _openSaved(Annotation a) async {
    final l = context.read<L10n>();
    hapticSelection();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(a.selectedText.trim(), maxLines: 3, overflow: TextOverflow.ellipsis),
        message: a.comment != null ? Text(a.comment!) : null,
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); _askAi(saved: a); },
            child: Text(l.t('hl_ask_ai')),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final note = await _askNote(a.comment);
              if (note != null) await _patch(a, comment: note);
            },
            child: Text(a.comment == null ? l.t('hl_note') : l.t('hl_note_edit')),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final color = await _pickColor(a.color);
              if (color != null) await _patch(a, color: color);
            },
            child: Text(l.t('hl_color')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () { Navigator.pop(ctx); _delete(a); },
            child: Text(l.t('delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.t('cancel')),
        ),
      ),
    );
  }

  Future<String?> _pickColor(String current) => showCupertinoModalPopup<String>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            for (final c in highlightColors)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, c),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 18, height: 18, decoration: BoxDecoration(
                    color: highlightSwatch(c), shape: BoxShape.circle,
                    border: c == current
                        ? Border.all(color: CupertinoColors.label.resolveFrom(ctx), width: 2)
                        : null,
                  )),
                  const SizedBox(width: 10),
                  Text(context.read<L10n>().t('hl_color_$c')),
                ]),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.read<L10n>().t('cancel')),
          ),
        ),
      );

  /// Прокрутка к фрагменту в тексте + короткая подсветка, чтобы глаз нашёл
  /// место (тап по строке списка «Мои выделения»).
  Future<void> _jumpTo(Annotation a) async {
    if (!a.isLectureText) {
      // Пометка внутри материала: открываем файл и сразу подсвечиваем место.
      final file = a.fileIndex >= 0 && a.fileIndex < widget.files.length
          ? widget.files[a.fileIndex]
          : null;
      if (file == null) { await _openSaved(a); return; }
      final result = await Navigator.push<Object?>(context, MaterialPageRoute(
        builder: (_) => DocumentViewerScreen(
          url: file,
          name: _fileDisplayName(file),
          lectureId: widget.lectureId!,
          classId: widget.classId!,
          fileIndex: a.fileIndex,
          lectureTitle: widget.title,
          focusAnnotationId: a.id,
        ),
      ));
      if (result is AiAsk && mounted) { Navigator.pop(context, result); return; }
      if (mounted) await _loadAnnotations();
      return;
    }
    final ctx = _bodyKey.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
    if (!mounted) return;
    setState(() => _flashId = a.id);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _flashId = null);
  }

  // ── Текст лекции с пометками ───────────────────────────────────────────

  TextSpan _bodySpan(BuildContext context) {
    final base = detailBodyStyle(context);
    final brightness = Theme.of(context).brightness;
    final spans = <TextSpan>[];
    var cursor = 0;

    for (final a in _textAnnotations) {
      // Пересекающиеся пометки: следующая начинается раньше конца предыдущей —
      // рисуем только видимый хвост, иначе куски текста задвоились бы.
      final start = a.startOffset < cursor ? cursor : a.startOffset;
      if (start >= a.endOffset) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: widget.content.substring(cursor, start)));
      }
      spans.add(TextSpan(
        text: widget.content.substring(start, a.endOffset),
        // Только заливка, без подчёркиваний: на многострочном фрагменте линии
        // читались как жирные полосы под текстом. Заметка видна по тапу и в
        // списке «Мои выделения».
        style: base.copyWith(
          backgroundColor: _flashId == a.id
              ? highlightSwatch(a.color)
              : highlightFill(a.color, brightness),
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _openSaved(a),
      ));
      cursor = a.endOffset;
    }
    if (cursor < widget.content.length) {
      spans.add(TextSpan(text: widget.content.substring(cursor)));
    }
    return TextSpan(style: base, children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final bg = detailBg(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = detailAccent(context);

    final body = Text.rich(_bodySpan(context), key: _bodyKey, textAlign: TextAlign.left);

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: accent,
        scaffoldBackgroundColor: bg,
        barBackgroundColor: bg,
        textTheme: CupertinoTextThemeData(
          primaryColor: accent,
          navLargeTitleTextStyle: TextStyle(
            // Крупный кегль — отрицательный трекинг и плотный интерлиньяж:
            // заголовок из двух строк иначе «разъезжается».
            fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1,
            color: detailText1(context),
          ),
          navTitleTextStyle: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            CupertinoSliverNavigationBar(
              // Полупрозрачный фон бара — CupertinoNavigationBar сам включает
              // под ним блюр, когда цвет не непрозрачный: свёрнутый заголовок
              // «плывёт» над текстом лекции, как в нативных приложениях.
              backgroundColor: bg.withValues(alpha: 0.82),
              border: null,
              stretch: true,
              largeTitle: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 56),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _MetaRow(dateLabel: widget.dateLabel, fileCount: widget.files.length, l: l),
                  if (widget.content.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 8),
                      child: Text(l.t('description').toUpperCase(), style: sectionCaptionStyle(context)),
                    ),
                    // Тело лекции — обычный текст на фоне страницы, как в Apple
                    // Notes: раньше он лежал в серой карточке, которая на
                    // длинном конспекте читалась как бесконечная плашка.
                    if (_canAnnotate)
                      SelectionArea(
                        contextMenuBuilder: _selectionMenu,
                        child: SelectionListener(
                          selectionNotifier: _selectionNotifier,
                          child: body,
                        ),
                      )
                    else
                      body,
                  ],
                  if (widget.files.isNotEmpty) ...[
                    SizedBox(height: widget.content.isNotEmpty ? 30 : 26),
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 8),
                      child: Text(l.t('attached_files_edit').toUpperCase(), style: sectionCaptionStyle(context)),
                    ),
                    FileList(
                      files: [
                        for (final f in widget.files) FileEntry(name: _fileDisplayName(f), url: f, previewUrl: f),
                      ],
                      onOpen: (f) => _openFile(widget.files.indexOf(f.url), f.url, f.name),
                    ),
                  ],
                  if (_annotations.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    HighlightsSection(
                      items: _annotations,
                      t: l.t,
                      onTap: _jumpTo,
                      onDelete: _delete,
                    ),
                  ],
                  if (widget.content.isEmpty && widget.files.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 56),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.book, size: 32, color: detailText2(context).withValues(alpha: 0.6)),
                          const SizedBox(height: 14),
                          Text(l.t('content_empty'),
                              style: TextStyle(fontSize: 16, color: detailText2(context), fontWeight: FontWeight.w500, letterSpacing: -0.2)),
                        ]),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String dateLabel;
  final int fileCount;
  final L10n l;
  const _MetaRow({required this.dateLabel, required this.fileCount, required this.l});

  @override
  Widget build(BuildContext context) {
    // Метаданные — капсулы-чипы на заливке, а не серая строка иконок с точкой:
    // так дата и число вложений читаются как два отдельных факта о лекции и не
    // соревнуются по весу с текстом ниже.
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _chip(context, CupertinoIcons.calendar, dateLabel),
      if (fileCount > 0)
        _chip(context, CupertinoIcons.paperclip,
            '$fileCount ${fileCount == 1 ? l.t('file') : l.t('files')}'),
    ]);
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final text2 = detailText2(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: detailSurface(context),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.devicePixelRatioOf(context)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: text2),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 14, color: text2, fontWeight: FontWeight.w500, letterSpacing: -0.2)),
      ]),
    );
  }
}

String _fileDisplayName(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
    return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
  } catch (_) {
    return url;
  }
}
