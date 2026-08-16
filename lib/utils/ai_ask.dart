/// Вопрос к ИИ-чату класса по выделенному фрагменту лекции.
///
/// Экран лекции возвращает его через Navigator.pop, класс переключается на
/// вкладку «ИИ» и отправляет сообщение в СУЩЕСТВУЮЩИЙ тред класса — отдельного
/// ИИ-интерфейса под выделения нет.
///
/// Идентификаторы (annotationId / lectureId / page) едут отдельными полями, а
/// не строкой внутри текста: по ним сервер сам подставляет в контекст, из какой
/// лекции и страницы взят фрагмент (см. backend routers/ai.py:_fragment_context).
class AiAsk {
  final String text;
  final int? annotationId;
  final int lectureId;
  final int page;
  final String? quote;

  const AiAsk({
    required this.text,
    required this.lectureId,
    this.annotationId,
    this.page = 0,
    this.quote,
  });
}

const _maxQuote = 1500;

/// Видимая формулировка вопроса — обычная человеческая фраза, как её написал бы
/// сам студент.
String buildQuotePrompt({
  required String lang,
  required String text,
  required String lectureTitle,
  int page = 0,
}) {
  final quote = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final short = quote.length > _maxQuote ? quote.substring(0, _maxQuote) : quote;
  final title = lectureTitle.trim();

  if (lang == 'EN') {
    final where = [
      title.isNotEmpty ? 'the lecture “$title”' : 'the lecture',
      if (page > 0) 'p. $page',
    ].join(', ');
    return 'Explain this excerpt from $where:\n\n«$short»';
  }
  if (lang == 'KZ' || lang == 'KK') {
    final where = [
      title.isNotEmpty ? '«$title» дәрісінен' : 'дәрістен',
      if (page > 0) '$page-бет',
    ].join(', ');
    return 'Осы үзіндіні түсіндіріп бер ($where):\n\n«$short»';
  }
  final where = [
    title.isNotEmpty ? 'из лекции «$title»' : 'из лекции',
    if (page > 0) 'стр. $page',
  ].join(', ');
  return 'Объясни этот фрагмент $where:\n\n«$short»';
}
