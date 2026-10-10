import 'package:beecount/widgets/ai/agent_math_markdown_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('currency cannot bridge into another amount or later formula', () {
    for (final source in [
      r'$35 $50',
      r'$35.50 $1,234.56',
      r'US$ 35',
      r'$100 then $120 then $x^2$',
    ]) {
      final normalized = AgentMathMarkdownNormalizer(source);
      expect(normalized.spans.length, source.endsWith(r'$x^2$') ? 1 : 0);
      expect(normalized.data, startsWith(source.split(' then ').first));
    }
  });

  test('fences, inline code, escaping and indented code stay untouched', () {
    for (final source in [
      '```dart\nfinal price = "\$35";\n\\(x=1\\)\n```',
      '~~~text\n\$x^2\$\n~~~',
      r'`$x^2$` ``\(x=1\)``',
      r'\$x^2\$',
      '    \$x^2\$',
      '> ```text\n> \$x^2\$\n> ```',
    ]) {
      final normalized = AgentMathMarkdownNormalizer(source);
      expect(normalized.spans, isEmpty);
      expect(normalized.data, source);
    }
  });

  test('complete preceding math survives an unfinished tail', () {
    final normalized = AgentMathMarkdownNormalizer(r'\(x=1\) then $x=\frac{');
    expect(normalized.spans.single.tex, 'x=1');
    expect(normalized.data, endsWith(r'$x=\frac{'));
  });

  test('numeric equations require complete operands and never absorb amounts',
      () {
    for (final source in [
      r'$35$',
      r'$35 + $50',
      r'$35-$50',
      r'$35.50, $50',
      r'$1,234.56 $50'
    ]) {
      expect(AgentMathMarkdownNormalizer(source).spans, isEmpty);
    }
    for (final source in [r'$1200 - 1000 = 200$', r'$1/2$', r'$x = 1$']) {
      expect(AgentMathMarkdownNormalizer(source).spans.length, 1);
    }
  });

  test('markers cannot collide with source text', () {
    final normalized = AgentMathMarkdownNormalizer('\uE0000\uE000 \\(x=1\\)');
    expect(normalized.marker, '\uE000\uE000');
    expect(normalized.spans.length, 1);
  });
}
