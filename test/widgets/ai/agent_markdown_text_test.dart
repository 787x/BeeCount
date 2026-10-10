import 'package:beecount/widgets/ai/agent_markdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';

void main() {
  Future<void> render(WidgetTester tester, String source,
      {Brightness brightness = Brightness.light, double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SizedBox(
            width: 240,
            child: AgentMarkdownText(data: source),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  for (final source in [
    r'储蓄率为 \( \frac{20}{100}=20\% \)。',
    r'储蓄率为 \( \frac{收入-支出}{收入}\times100\% \)。',
    r'增长率为 $r=\frac{20}{100}$',
    r'变量 $x$，其中 $x = 1$。',
    r'增长额为 $1200 - 1000 = 200$。',
    r'增长率 $\text{增长率}=\frac{1200-1000}{1000}\times100\%$。',
    r'储蓄率 $\frac{收入-支出}{收入}\times100\%$。',
    '\$\$\nr = \\frac{120-100}{100}\n\$\$',
    '\\[\nr = 20\\%\n\\]',
    r'\(\sqrt{x}+\sum_{i=1}^n i+\int x\cdot y\,dx\times100\%\)',
    r'\[\begin{aligned}x&=1\\y&=2\end{aligned}\]',
  ]) {
    testWidgets('renders formula: $source', (tester) async {
      await render(tester, source);
      expect(find.byType(Math),
          source.startsWith('变量') ? findsNWidgets(2) : findsOneWidget);
      for (final math in tester.widgetList<Math>(find.byType(Math))) {
        expect(math.parseError, isNull);
      }
    });
  }

  for (final source in [
    r'价格是 $35',
    r'价格是 $35.50',
    r'预算 $1,234.56',
    r'US$ 35',
    r'从 $35 增加到 $50',
    r'预算从 $100 增加到 $120',
    r'我花了 $35，余额还有 $50',
    r'价格 $35$，另一笔 $50$',
    r'$35 + $50',
    r'$35-$50',
    r'$35.50, $50',
    r'\$35',
    r'`$35` `$HOME` `\(x\)`',
    '```text\n\$35\n\$x^2\$\n```',
  ]) {
    testWidgets('keeps literal dollars/code: $source', (tester) async {
      await render(tester, source);
      expect(find.byType(Math), findsNothing);
      final text = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan!.toPlainText())
          .join();
      expect(
          text,
          anyOf(contains(r'$35'), contains(r'$1,234.56'), contains(r'$100'),
              contains(r'$ 35')));
    });
  }

  testWidgets('mixed currency and block math', (tester) async {
    await render(
        tester, '支出从 \$100 增长到 \$120，因此\n\\[\n\\frac{120-100}{100}=20\\%\n\\]');
    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'$100'), findsOneWidget);
    expect(find.textContaining(r'$120'), findsOneWidget);
  });

  testWidgets('streaming prefixes become math only after closing',
      (tester) async {
    for (final prefixes in [
      [r'$', r'$x', r'$x=', r'$x=\frac{', r'$x=\frac{1}{2}$'],
      [r'$$', r'$$\frac{', r'$$\frac{1}{2}$$'],
      [r'\(', r'\(\frac{', r'\(\frac{1}{2}\)'],
      [r'\[', r'\[\frac{', r'\[\frac{1}{2}\]'],
    ]) {
      for (final prefix in prefixes) {
        await render(tester, prefix);
        expect(find.byType(Math),
            prefix == prefixes.last ? findsOneWidget : findsNothing);
      }
    }
  });

  testWidgets('malformed formula falls back to its readable source',
      (tester) async {
    for (final source in [r'\(\frac{1}{\)', r'\(\unknowncommand{x}\)']) {
      await render(tester, source);
      expect(find.text(source), findsOneWidget);
    }
    await render(tester, r'\(\frac{1}{');
    expect(find.text(r'\(\frac{1}{'), findsOneWidget);
  });

  testWidgets('long display math scrolls locally in both themes and scales',
      (tester) async {
    final source = '\$\$\n\\text{${'long expression ' * 20}}\n\$\$';
    for (final brightness in Brightness.values) {
      await render(tester, source, brightness: brightness, scale: 1.7);
      final math = tester.widget<Math>(find.byType(Math));
      expect(math.textScaleFactor, 1.7);
      expect(math.textStyle!.color, isNotNull);
      expect(math.textStyle!.color!.computeLuminance(),
          brightness == Brightness.dark ? greaterThan(0.5) : lessThan(0.5));
      final scroll = tester.widget<SingleChildScrollView>(find
          .ancestor(
              of: find.byType(Math),
              matching: find.byType(SingleChildScrollView))
          .first);
      expect(scroll.scrollDirection, Axis.horizontal);
      final viewport = find
          .ancestor(
              of: find.byType(Math),
              matching: find.byType(SingleChildScrollView))
          .first;
      await tester.drag(viewport, const Offset(-200, 0));
      await tester.pumpAndSettle();
      final position = tester
          .state<ScrollableState>(find
              .descendant(of: viewport, matching: find.byType(Scrollable))
              .first)
          .position;
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('GFM headings lists quotes and tables remain available',
      (tester) async {
    await render(tester,
        '# 标题\n\n**粗体** *斜体*\n\n- 项目\n\n1. 编号\n\n> 引用\n\n| A | B |\n|---|---|\n| 1 | 2 |');
    expect(find.text('标题'), findsOneWidget);
    expect(find.byType(Table), findsOneWidget);
  });

  testWidgets('renders assistant content with MarkdownBody', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentMarkdownText(data: '**本月支出**：`80 元`'),
        ),
      ),
    );

    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data, '**本月支出**：`80 元`');
  });
}
