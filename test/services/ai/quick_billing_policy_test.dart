import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/providers/smart_billing_providers.dart';
import 'package:beecount/services/ai/quick_billing_policy.dart';
import 'package:beecount/services/ai/billing_draft_session.dart';
import 'package:beecount/services/ai/bookkeeping_result.dart';
import 'package:beecount/services/ai/quick_billing_flow.dart';

const ready = BillingDraftAnalysis(
    drafts: [BillingDraft(BillInfo(amount: 35, type: BillType.expense))]);
const candidate = BillingDraftAnalysis(
    drafts: [
      BillingDraft(BillInfo(amount: 35, type: BillType.expense),
          uncertainFields: ['currency'])
    ],
    needsInput: true,
    missingFields: ['currency']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('decision matrix keeps defaults and accepts only safe whole batches',
      () {
    const defaults = QuickBillingResultPolicy();
    const best = QuickBillingResultPolicy(
        needsInputAction: NeedsInputAction.saveBestEffort);
    expect(defaults.decide(const BillingDraftAnalysis()),
        QuickBillingDecision.notify);
    expect(
        defaults
            .copyWith(noBillAction: NoBillAction.clarify)
            .decide(const BillingDraftAnalysis()),
        QuickBillingDecision.clarify);
    expect(defaults.decide(candidate), QuickBillingDecision.clarify);
    expect(best.decide(candidate), QuickBillingDecision.persist);
    expect(defaults.decide(ready), QuickBillingDecision.persist);
    expect(defaults.copyWith(readyAction: ReadyAction.confirm).decide(ready),
        QuickBillingDecision.confirm);
    for (final bill in [
      const BillInfo(type: BillType.expense),
      const BillInfo(amount: 35),
      const BillInfo(amount: 0, type: BillType.expense),
      const BillInfo(amount: double.infinity, type: BillType.expense),
      const BillInfo(
          amount: 35,
          type: BillType.transfer,
          fromAccount: 'A',
          toAccount: 'A'),
      const BillInfo(amount: 35, type: BillType.transfer, fromAccount: 'A'),
    ]) {
      expect(
          best.decide(BillingDraftAnalysis(
              drafts: [candidate.drafts.single, BillingDraft(bill)])),
          QuickBillingDecision.clarify);
    }
    expect(
        best.decide(const BillingDraftAnalysis(drafts: [
          BillingDraft(
              BillInfo(
                  amount: 35,
                  type: BillType.transfer,
                  fromAccount: 'unknown',
                  toAccount: 'B'),
              uncertainFields: ['transfer_accounts'])
        ])),
        QuickBillingDecision.clarify);
    expect(
        () => candidate.drafts.single.toBill(DateTime.now()), throwsStateError);
    expect(
        candidate.drafts.single.acceptCandidate().toBill(DateTime.now()).amount,
        -35);
  });

  test('serialization, defaults, corrupt data and restart', () async {
    const policy = QuickBillingResultPolicy(
        noBillAction: NoBillAction.clarify,
        needsInputAction: NeedsInputAction.saveBestEffort,
        readyAction: ReadyAction.confirm);
    expect(QuickBillingResultPolicy.fromJson(policy.toJson()).toJson(),
        policy.toJson());
    expect(
        QuickBillingResultPolicy.fromJson(
            {'noBillAction': 'new', 'readyAction': 42}).toJson(),
        const QuickBillingResultPolicy().toJson());
    for (final saved in [
      null,
      '{',
      '[]',
      jsonEncode({'noBillAction': 'clarify'})
    ]) {
      SharedPreferences.setMockInitialValues(
          {if (saved != null) QuickBillingPolicyNotifier.preferenceKey: saved});
      final container = ProviderContainer();
      final loaded = await container.read(quickBillingPolicyProvider.future);
      expect(loaded.readyAction, ReadyAction.saveImmediately);
      expect(loaded.needsInputAction, NeedsInputAction.clarify);
      await container
          .read(quickBillingPolicyProvider.notifier)
          .setPolicy(policy);
      container.dispose();
      final restarted = ProviderContainer();
      expect((await restarted.read(quickBillingPolicyProvider.future)).toJson(),
          policy.toJson());
      restarted.dispose();
    }
  });

  test(
      'noBill can reanalyze, snapshot remains fixed, double confirm saves once',
      () async {
    var current = const QuickBillingResultPolicy(
        noBillAction: NoBillAction.clarify, readyAction: ReadyAction.confirm);
    var saves = 0;
    final session = BillingDraftSession(
        policy: current,
        allowImages: false,
        analyze: (_, replies, __) async =>
            replies.isEmpty ? const BillingDraftAnalysis() : ready,
        persist: (_, __) async {
          saves++;
          return const BookkeepingResult(transactionIds: [1]);
        });
    await QuickBillingFlow(session).run(clarify: (session) async {
      expect(session.state, BillingDraftState.noBill);
      expect(saves, 0);
      current = const QuickBillingResultPolicy();
      await session.update(reply: '其实午饭35元');
      expect(session.decision, QuickBillingDecision.confirm);
      expect(saves, 0);
      final save = session.saveReady();
      expect(await session.saveReady(), isNull);
      return save;
    });
    expect(saves, 1);
    expect(current.readyAction, ReadyAction.saveImmediately);
  });

  test('best effort persists accepted batch once; errors never become noBill',
      () async {
    var saves = 0;
    final session = BillingDraftSession(
        policy: const QuickBillingResultPolicy(
            needsInputAction: NeedsInputAction.saveBestEffort),
        analyze: (_, __, ___) async => candidate,
        persist: (drafts, _) async {
          expect(drafts.single.blocked, false);
          saves++;
          return BookkeepingResult.empty;
        });
    await session.update();
    await session.saveReady();
    await session.saveReady();
    expect(saves, 1);
    await session.dispose();
    final failed = BillingDraftSession(
        analyze: (_, __, ___) async =>
            throw const FormatException('bad envelope'),
        persist: (_, __) async {
          saves++;
          return BookkeepingResult.empty;
        });
    await expectLater(
        QuickBillingFlow(failed)
            .run(clarify: (_) async => throw StateError('must not navigate')),
        throwsFormatException);
    expect(saves, 1);
  });
}
