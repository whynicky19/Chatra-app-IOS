/// Окно контекста для запросов к ИИ: вся переписка целиком упирается в лимит
/// модели и растит стоимость квадратично, поэтому держим только хвост.
///
///
/// Держим только хвост переписки. System-промпт добавляется вызывающим кодом
/// отдельно и в окно не входит — он нужен всегда.
const int kAiContextWindow = 20;

/// Максимальная длина одного сообщения в символах. Вставленный студентом
/// лог на 200 КБ иначе улетает в запрос целиком.
const int kAiMaxMessageChars = 8000;

/// Последние [kAiContextWindow] сообщений в формате API, с обрезкой слишком
List<Map<String, dynamic>> aiContextWindow(List<Map<String, String>> msgs) {
  final tail = msgs.length <= kAiContextWindow
      ? msgs
      : msgs.sublist(msgs.length - kAiContextWindow);

  return tail.map((m) {
    final text = m['text'] ?? '';
    return <String, dynamic>{
      'role': m['role'] ?? 'user',
      'content': text.length > kAiMaxMessageChars
          ? '${text.substring(0, kAiMaxMessageChars)}…'
          : text,
    };
  }).toList();
}
