import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Рендерит текст сообщения ассистента с формулами LaTeX внутри.
/// Блочные ($$...$$, \[...\]) и инлайн ($...$, \(...\)) формулы разбираются
/// и рисуются через flutter_math_fork; остальной текст — обычными словами
/// во `Wrap`, чтобы формулы могли стоять прямо посреди строки.
class AiMessageContent extends StatelessWidget {
  final String text;
  final TextStyle style;

  const AiMessageContent({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    final blocks = _buildBlocks(_tokenize(text), style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
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
  static final _currencyRe = RegExp(r'^\s*\d[\d,.\s]*\s*$');

  static List<_Seg> _tokenize(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _blockRe.allMatches(text)) {
      if (m.start > last) segs.addAll(_tokenizeInline(text.substring(last, m.start)));
      segs.add(_Seg(_SegType.block, m.group(1) ?? m.group(2) ?? ''));
      last = m.end;
    }
    if (last < text.length) segs.addAll(_tokenizeInline(text.substring(last)));
    return segs;
  }

  static List<_Seg> _tokenizeInline(String text) {
    final segs = <_Seg>[];
    var last = 0;
    for (final m in _inlineRe.allMatches(text)) {
      final isDollarForm = m.group(1) != null;
      final tex = m.group(1) ?? m.group(2) ?? '';
      if (m.start > last) segs.add(_Seg(_SegType.text, text.substring(last, m.start)));
      if (isDollarForm && _currencyRe.hasMatch(tex)) {
        segs.add(_Seg(_SegType.text, m.group(0)!));
      } else {
        segs.add(_Seg(_SegType.inline, tex));
      }
      last = m.end;
    }
    if (last < text.length) segs.add(_Seg(_SegType.text, text.substring(last)));
    return segs;
  }
}

enum _SegType { text, inline, block }

class _Seg {
  final _SegType type;
  final String value;
  _Seg(this.type, this.value);
}
