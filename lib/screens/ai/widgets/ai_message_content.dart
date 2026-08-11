import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../../../utils/haptics.dart';

/// Рендерит текст сообщения ассистента: формулы LaTeX, markdown-списки и
/// таблицы. Документ разбирается построчно на параграфы/списки/таблицы;
/// внутри параграфов блочные ($$...$$, \[...\]) и инлайн ($...$, \(...\))
/// формулы рисуются через flutter_math_fork, остальной текст — обычными
/// словами во `Wrap`, чтобы формулы могли стоять прямо посреди строки.
/// Внутри пунктов списка и ячеек таблицы поддерживаются только инлайн-формулы.
class AiMessageContent extends StatelessWidget {
  final String text;
  final TextStyle style;

  const AiMessageContent({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _buildDocument(text, style),
    );
  }

  // ── Document-level: параграфы / списки / таблицы ──────────────────────────
  List<Widget> _buildDocument(String text, TextStyle style) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    final paragraph = <String>[];

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      widgets.addAll(_buildBlocks(_tokenize(paragraph.join('\n')), style));
      paragraph.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        flushParagraph();
        i++; // пропускаем открывающий ``` (с языком или без)
        final codeLines = <String>[];
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // пропускаем закрывающий ```
        widgets.add(_buildCodeBlock(codeLines.join('\n'), style));
        continue;
      }
      if (_isTableRow(line) && i + 1 < lines.length && _isTableSep(lines[i + 1])) {
        flushParagraph();
        final header = _splitRow(line);
        i += 2;
        final rows = <List<String>>[];
        while (i < lines.length && _isTableRow(lines[i])) {
          rows.add(_splitRow(lines[i]));
          i++;
        }
        widgets.add(_buildTable(header, rows, style));
        continue;
      }
      if (_isUl(line) || _isOl(line)) {
        final ordered = _isOl(line);
        final items = <String>[];
        while (i < lines.length && (ordered ? _isOl(lines[i]) : _isUl(lines[i]))) {
          items.add(_stripMarker(lines[i]));
          i++;
        }
        flushParagraph();
        widgets.add(_buildList(items, ordered, style));
        continue;
      }
      paragraph.add(line);
      i++;
    }
    flushParagraph();
    return widgets;
  }

  // Таблицу опознаём по строке-разделителю (только "-", "|", ":", пробелы) —
  // не по обязательным крайним "|", т.к. модель их часто опускает. Требуем
  // "|" и в самой строке-разделителе, иначе горизонтальная черта "---"
  // (частый в ответах разделитель разделов) не будет ошибочно принята за таблицу.
  static final _tableRowRe = RegExp(r'\|');
  static final _tableSepRe = RegExp(r'^[-|:\s]+$');
  static final _ulRe = RegExp(r'^\s*[-*]\s+\S');
  static final _olRe = RegExp(r'^\s*\d+\.\s+\S');

  bool _isTableRow(String l) => _tableRowRe.hasMatch(l);
  bool _isTableSep(String l) => _tableSepRe.hasMatch(l) && l.contains('-') && l.contains('|');
  bool _isUl(String l) => _ulRe.hasMatch(l);
  bool _isOl(String l) => _olRe.hasMatch(l);
  String _stripMarker(String l) => l.replaceFirst(RegExp(r'^\s*(?:[-*]|\d+\.)\s+'), '');

  List<String> _splitRow(String l) {
    var s = l.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  Widget _buildList(List<String> items, bool ordered, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var idx = 0; idx < items.length; idx++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 22, child: Text(ordered ? '${idx + 1}.' : '•', style: style)),
                  Expanded(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _inlineWidgets(items[idx], style),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTable(List<String> header, List<List<String>> rows, TextStyle style) {
    final cols = header.length;
    List<String> pad(List<String> r) {
      final out = List<String>.from(r);
      while (out.length < cols) {
        out.add('');
      }
      if (out.length > cols) out.removeRange(cols, out.length);
      return out;
    }

    final borderColor = (style.color ?? const Color(0xFF000000)).withValues(alpha: 0.2);
    Widget cell(String text, TextStyle st) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _inlineWidgets(text, st),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: borderColor, width: 0.6),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(children: [for (final h in header) cell(h, style.copyWith(fontWeight: FontWeight.w700))]),
            for (final r in rows) TableRow(children: [for (final c in pad(r)) cell(c, style)]),
          ],
        ),
      ),
    );
  }

  // Тёмный фон код-блока — как на сайте (`.code-bl`: #0a0a16 / #99e6f0).
  Widget _buildCodeBlock(String code, TextStyle style) {
    final codeStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: (style.fontSize ?? 15) - 1,
      height: 1.5,
      color: const Color(0xFF99E6F0),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(color: const Color(0xFF0A0A16), borderRadius: BorderRadius.circular(8)),
        // Clip.none: кнопка копирования нарочно чуть "вылезает" за границы
        // код-блока (top:-4, right:-4) в отступ самого Container — по
        // умолчанию Stack обрезает всё за своими границами (Clip.hardEdge),
        // из-за чего иконка подрезалась по верхнему/правому краю.
        child: Stack(clipBehavior: Clip.none, children: [
          Padding(
            // Место справа под кнопку копирования, чтобы не наезжала на код.
            padding: const EdgeInsets.only(right: 30, top: 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(code, style: codeStyle),
            ),
          ),
          Positioned(
            top: -4, right: -4,
            child: Builder(builder: (ctx) => Tappable(
              onTap: () {
                hapticSelection();
                Clipboard.setData(ClipboardData(text: code));
                showToast(ctx, ctx.read<L10n>().t('copied'));
              },
              label: 'Скопировать код',
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(CupertinoIcons.doc_on_doc, size: 15, color: Color(0x99FFFFFF)),
              ),
            )),
          ),
        ]),
      ),
    );
  }

  Widget _inlineCode(String code, TextStyle style) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: (style.color ?? const Color(0xFF000000)).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(code, style: style.copyWith(fontFamily: 'monospace', fontSize: (style.fontSize ?? 15) - 1)),
      );

  List<Widget> _inlineWidgets(String text, TextStyle style) {
    final widgets = <Widget>[];
    for (final seg in _tokenizeInline(text)) {
      switch (seg.type) {
        case _SegType.inline:
          widgets.add(Math.tex(
            seg.value,
            mathStyle: MathStyle.text,
            textStyle: style,
            onErrorFallback: (_) => Text('\$${seg.value}\$', style: style),
          ));
          break;
        case _SegType.code:
          widgets.add(_inlineCode(seg.value, style));
          break;
        default:
          for (final word in seg.value.split(' ')) {
            if (word.isEmpty) continue;
            widgets.add(Text(word, style: style));
          }
      }
    }
    return widgets;
  }

  List<Widget> _buildBlocks(List<_Seg> segs, TextStyle style) {
    final blocks = <Widget>[];
    var currentLine = <Widget>[];

    void flushLine() {
      if (currentLine.isNotEmpty) {
        blocks.add(Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: currentLine));
        currentLine = [];
      }
    }

    for (final seg in segs) {
      switch (seg.type) {
        case _SegType.block:
          flushLine();
          blocks.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                seg.value,
                mathStyle: MathStyle.display,
                textStyle: style,
                onErrorFallback: (_) => Text('\$\$${seg.value}\$\$', style: style),
              ),
            ),
          ));
          break;
        case _SegType.inline:
          currentLine.add(Math.tex(
            seg.value,
            mathStyle: MathStyle.text,
            textStyle: style,
            onErrorFallback: (_) => Text('\$${seg.value}\$', style: style),
          ));
          break;
        case _SegType.code:
          currentLine.add(_inlineCode(seg.value, style));
          break;
        case _SegType.text:
          final lines = seg.value.split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (i > 0) flushLine();
            for (final word in lines[i].split(' ')) {
              if (word.isEmpty) continue;
              currentLine.add(Text(word, style: style));
            }
          }
          break;
      }
    }
    flushLine();
    return blocks;
  }

  static final _blockRe = RegExp(r'\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]');
  static final _inlineRe = RegExp(r'\$([^$\n]+?)\$|\\\(([\s\S]+?)\\\)');
  static final _inlineCodeRe = RegExp(r'`([^`\n]+)`');
  static final _currencyRe = RegExp(r'^\s*\d[\d,.\s]*\s*$');

  // flutter_math_fork регистрирует только aligned/alignedat/cases (см. пакет
  // src/parser/tex/environments/eqn_array.dart) — align, align*, gather,
  // gathered, equation и eqnarray не распознаются вообще и валят парсинг
  // формулы целиком в onErrorFallback (сырой LaTeX-текст на экране). Модель
  // же регулярно выбирает эти окружения (особенно align* для систем
  // уравнений) — заменяем их на ближайший поддерживаемый аналог до рендера.
  static final _alignEnvRe = RegExp(r'\\(begin|end)\{align\*?\}');
  static final _eqnArrayEnvRe = RegExp(r'\\(begin|end)\{eqnarray\*?\}');
  static final _gatherEnvRe = RegExp(r'\\(begin|end)\{gather(?:ed)?\*?\}');
  static final _equationEnvRe = RegExp(r'\\begin\{equation\*?\}|\\end\{equation\*?\}');

  static String _sanitizeTex(String tex) {
    var t = tex;
    t = t.replaceAllMapped(_alignEnvRe, (m) => '\\${m.group(1)}{aligned}');
    t = t.replaceAllMapped(_eqnArrayEnvRe, (m) => '\\${m.group(1)}{aligned}');
    t = t.replaceAllMapped(_gatherEnvRe, (m) => '\\${m.group(1)}{aligned}');
    t = t.replaceAll(_equationEnvRe, '');
    // Модель часто переносит строки внутри формулы через "\\" вообще без
    // окружения — а голый "\\" вне aligned/array/matrix невалиден и валит
    // парсинг всей формулы (именно так на экране появляется сырой текст со
    // "\\" и "\quad \Rightarrow \quad" вместо рендера). Раз перенос строк уже
    // есть, а окружения нет — заворачиваем сами.
    if (t.contains(r'\\') && !t.contains(r'\begin{')) {
      t = '\\begin{aligned}$t\\end{aligned}';
    }
    return t;
  }

  static List<_Seg> _tokenize(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _blockRe.allMatches(text)) {
      if (m.start > last) segs.addAll(_tokenizeInline(text.substring(last, m.start)));
      segs.add(_Seg(_SegType.block, _sanitizeTex(m.group(1) ?? m.group(2) ?? '')));
      last = m.end;
    }
    if (last < text.length) segs.addAll(_tokenizeInline(text.substring(last)));
    return segs;
  }

  // Инлайн-код (`...`) вырезаем раньше формул, чтобы `$var$` внутри код-спана
  // не принялось за LaTeX.
  static List<_Seg> _tokenizeInline(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _inlineCodeRe.allMatches(text)) {
      if (m.start > last) segs.addAll(_tokenizeMath(text.substring(last, m.start)));
      segs.add(_Seg(_SegType.code, m.group(1) ?? ''));
      last = m.end;
    }
    if (last < text.length) segs.addAll(_tokenizeMath(text.substring(last)));
    return segs;
  }

  static List<_Seg> _tokenizeMath(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _inlineRe.allMatches(text)) {
      final isDollarForm = m.group(1) != null;
      final tex = m.group(1) ?? m.group(2) ?? '';
      if (m.start > last) segs.add(_Seg(_SegType.text, text.substring(last, m.start)));
      if (isDollarForm && _currencyRe.hasMatch(tex)) {
        segs.add(_Seg(_SegType.text, m.group(0)!));
      } else {
        segs.add(_Seg(_SegType.inline, _sanitizeTex(tex)));
      }
      last = m.end;
    }
    if (last < text.length) segs.add(_Seg(_SegType.text, text.substring(last)));
    return segs;
  }
}

enum _SegType { text, inline, block, code }

class _Seg {
  final _SegType type;
  final String value;
  _Seg(this.type, this.value);
}
