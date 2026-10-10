import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/ai/agent_markdown_text.dart';
import 'package:beecount/widgets/ai/agent_reasoning_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reasoning stays collapsed and safely renders streaming math',
      (tester) async {
    Widget host(String reasoning) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: AgentReasoningPanel(reasoning: reasoning),
          ),
        );
    await tester.pumpWidget(host(r'计算：\('));
    await tester.pumpAndSettle();
    expect(find.byType(AgentMarkdownText), findsNothing);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    for (final source in [r'计算：\(', r'计算：\(x=', r'计算：\(x=1\)']) {
      await tester.pumpWidget(host(source));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(AgentMarkdownText), findsOneWidget);
    }
    expect(find.byType(Math), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNothing);
  });
}
