import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/utils/math_text.dart';

void main() {
  group('cleanMathText', () {
    test('unwraps \\( \\) delimiters (real summary case)', () {
      expect(
        cleanMathText('нахождение корней уравнения \\( f(x) = 0 \\) с помощью графика'),
        'нахождение корней уравнения f(x) = 0 с помощью графика',
      );
    });

    test('converts fractions and powers', () {
      expect(cleanMathText('\\frac{a}{b}'), 'a/b');
      expect(cleanMathText('\\frac{x+1}{2}'), '(x+1)/2');
      expect(cleanMathText('x^{2} + y^2 = z^{10}'), 'x² + y² = z¹⁰');
      expect(cleanMathText('a_{1} + a_n'), 'a₁ + aₙ');
    });

    test('converts sqrt and symbols', () {
      expect(cleanMathText('\\sqrt{x}'), '√x');
      expect(cleanMathText('\\sqrt{x+1}'), '√(x+1)');
      expect(cleanMathText('\\pi \\cdot r^2'), 'π · r²');
      expect(cleanMathText('x \\le y \\ne z'), 'x ≤ y ≠ z');
      expect(cleanMathText('\\int_0^1 f(x)'), '∫₀¹ f(x)');
    });

    test('unwraps \$...\$ only when it looks like math', () {
      expect(cleanMathText(r'$x^2 + 1$'), 'x² + 1');
      expect(cleanMathText(r'цена $100 и $200 за штуку'),
          r'цена $100 и $200 за штуку');
    });

    test('leaves ordinary text and snake_case untouched', () {
      expect(cleanMathText('обычный текст без формул'), 'обычный текст без формул');
      expect(cleanMathText('файл lecture_full.pdf'), 'файл lecture_full.pdf');
      expect(cleanMathText('**жирный** и - список'), '**жирный** и - список');
    });

    test('unmappable superscript falls back readably', () {
      expect(cleanMathText('e^{x+y}'), 'e^(x+y)');
    });
  });
}
