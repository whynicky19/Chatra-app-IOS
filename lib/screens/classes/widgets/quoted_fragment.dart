import 'package:flutter/cupertino.dart';

/// Разбор сообщения-вопроса по выделенному фрагменту лекции.
///
/// Сообщение отправляется обычным текстом (его же видит модель и хранит
/// сервер), но в переписке его стоит показывать как цитату из материала:
/// вводная строка, сам фрагмент подсветкой и карточка источника. Формат задан
/// в utils/ai_ask.dart — здесь он разбирается обратно.
class QuotedFragment {
  final String intro;
  final String quote;
  final String? lectureTitle;
  final int? page;

  const QuotedFragment({
    required this.intro,
    required this.quote,
    this.lectureTitle,
    this.page,
  });

  /// Начало сообщения (вводная строка) и сам фрагмент разделены пустой
  /// строкой — так его собирает buildQuotePrompt.
  static final _intro = RegExp(r'^(Объясни этот фрагмент|Explain this excerpt|Осы үзіндіні)');
  static final _titleRe = RegExp(r'[«"“]([^«»"”\n]+)[»"”]');
  static final _pageRe = RegExp(r'(?:стр\.|p\.)\s*(\d+)|(\d+)-бет');

  /// null, если это обычное сообщение, а не цитата.
  static QuotedFragment? tryParse(String text) {
    final t = text.trim();
    if (!_intro.hasMatch(t)) return null;

    final split = t.indexOf('\n');
    if (split < 0) return null;
    final intro = t.substring(0, split).trim();
    var quote = t.substring(split).trim();
    if (quote.isEmpty || !intro.endsWith(':')) return null;

    // Кавычки вокруг фрагмента — часть оформления, в цитате они не нужны.
    if (quote.length > 1 && '«"“'.contains(quote[0]) && '»"”'.contains(quote[quote.length - 1])) {
      quote = quote.substring(1, quote.length - 1).trim();
    }
    if (quote.isEmpty) return null;

    final title = _titleRe.firstMatch(intro)?.group(1)?.trim();
    final pm = _pageRe.firstMatch(intro);
    return QuotedFragment(
      intro: intro,
      quote: quote,
      lectureTitle: title == null || title.isEmpty ? null : title,
      page: pm == null ? null : int.tryParse(pm.group(1) ?? pm.group(2) ?? ''),
    );
  }
}

/// Пузырь сообщения с цитатой: подсвеченный фрагмент и карточка источника —
/// сразу видно, о каком куске лекции идёт речь.
class QuotedFragmentBubble extends StatelessWidget {
  final QuotedFragment fragment;
  final Color bubbleColor;
  final String pageLabel;

  const QuotedFragmentBubble({
    super.key,
    required this.fragment,
    required this.bubbleColor,
    required this.pageLabel,
  });

  @override
  Widget build(BuildContext context) {
    const onBubble = CupertinoColors.white;
    final source = [
      if (fragment.lectureTitle != null) fragment.lectureTitle!,
      if (fragment.page != null) '$pageLabel ${fragment.page}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20), topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(fragment.intro,
            style: const TextStyle(
              fontSize: 16.5, color: onBubble, height: 1.35, letterSpacing: -0.3,
            )),
        const SizedBox(height: 8),
        // Сам фрагмент — как пометка в лекции: жёлтая подсветка на белой
        // подложке, чтобы цитата читалась текстом материала, а не репликой.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(fragment.quote,
              style: TextStyle(
                fontSize: 15.5, height: 1.4, letterSpacing: -0.2,
                color: const Color(0xFF1C1C1E),
                backgroundColor: const Color(0xFFFFD84D).withValues(alpha: 0.55),
              )),
        ),
        if (source.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: CupertinoColors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.doc_text, size: 15, color: onBubble),
              const SizedBox(width: 7),
              Flexible(child: Text(source,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13, color: onBubble, height: 1.25, letterSpacing: -0.2,
                    fontWeight: FontWeight.w500,
                  ))),
            ]),
          ),
        ],
      ]),
    );
  }
}
