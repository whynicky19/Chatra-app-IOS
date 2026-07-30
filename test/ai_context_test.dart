import 'package:chatra_app/utils/ai_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<Map<String, String>> msgs(int n) => List.generate(
        n,
        (i) => {'role': i.isEven ? 'user' : 'assistant', 'text': 'msg$i'},
      );

  test('короткая переписка проходит целиком', () {
    final out = aiContextWindow(msgs(5));
    expect(out.length, 5);
    expect(out.first['content'], 'msg0');
  });

  test('длинная переписка режется до окна и берётся хвост', () {
    final out = aiContextWindow(msgs(100));
    expect(out.length, kAiContextWindow);
    expect(out.last['content'], 'msg99');
    expect(out.first['content'], 'msg${100 - kAiContextWindow}');
  });

  test('роли сохраняются', () {
    final out = aiContextWindow(msgs(4));
    expect(out.map((m) => m['role']).toList(),
        ['user', 'assistant', 'user', 'assistant']);
  });

  test('слишком длинное сообщение обрезается', () {
    final long = 'x' * (kAiMaxMessageChars + 5000);
    final out = aiContextWindow([
      {'role': 'user', 'text': long}
    ]);
    expect((out.single['content'] as String).length, kAiMaxMessageChars + 1);
    expect((out.single['content'] as String).endsWith('…'), isTrue);
  });

  test('пустой список не падает', () {
    expect(aiContextWindow(const []), isEmpty);
  });

  test('отсутствующие поля получают дефолты', () {
    final out = aiContextWindow([{}]);
    expect(out.single['role'], 'user');
    expect(out.single['content'], '');
  });
}
