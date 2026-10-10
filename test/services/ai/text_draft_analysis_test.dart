import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/ai/core/billing_draft_analyzer.dart';
import 'package:beecount/services/ai/quick_billing_policy.dart';

void main() {
  test('structured text retains absent values, original and follow-up data',
      () async {
    const analyzer = BillingDraftAnalyzer();
    const context = AiExtractionContext();
    for (final input in ['午饭35元', '午饭', '今天天气不错']) {
      final result = await analyzer.analyzeText(input, context, [], null,
          request: (data, protocol) async {
        expect(jsonDecode(data)['text'], input);
        expect(protocol, contains('needs_input'));
        return input == '今天天气不错'
            ? '{"drafts":[],"needs_input":false}'
            : jsonEncode({
                'drafts': [
                  {
                    'amount': input == '午饭' ? null : 35,
                    'type': 'expense',
                    'time': null
                  }
                ],
                'needs_input': input == '午饭',
                'missing_fields': input == '午饭' ? ['amount'] : []
              });
      });
      expect(result.ready, input == '午饭35元');
      if (input == '午饭') expect(result.drafts.single.bill.amount, isNull);
      if (input == '今天天气不错') expect(result.drafts, isEmpty);
    }
    final result = await analyzer.analyzeText(
        '今天天气不错', context, ['其实午饭35元'], const BillingDraftAnalysis(),
        request: (data, protocol) async {
      expect(jsonDecode(data)['replies'], ['其实午饭35元']);
      expect(protocol, isNot(contains('其实午饭35元')));
      return '{"drafts":[{"amount":35,"type":"expense"}],"needs_input":false}';
    });
    expect(result.ready, true);
  });
  test(
      'unknown transfer account cannot be accepted; parse and provider errors propagate',
      () async {
    const analyzer = BillingDraftAnalyzer();
    const context = AiExtractionContext(
        accounts: [(name: 'A', currency: 'CNY'), (name: 'B', currency: 'CNY')]);
    final result = await analyzer.analyzeText('转账', context, [], null,
        request: (_, __) async =>
            '{"drafts":[{"amount":35,"type":"transfer","from_account":"unknown","to_account":"B"}],"needs_input":false}');
    expect(result.ready, false);
    expect(
        const QuickBillingResultPolicy(
                needsInputAction: NeedsInputAction.saveBestEffort)
            .decide(result),
        QuickBillingDecision.clarify);
    await expectLater(
        analyzer.analyzeText('text', context, [], null,
            request: (_, __) async => '[]'),
        throwsFormatException);
    await expectLater(
        analyzer.analyzeText('text', context, [], null,
            request: (_, __) async => throw StateError('401')),
        throwsStateError);
  });
}
