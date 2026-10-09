import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/services/ai/billing_draft_session.dart';
import 'package:beecount/services/ai/billing_image_service.dart';
import 'package:beecount/services/ai/bookkeeping_result.dart';

void main() {
  test('save exception is handled and never allows batch replay', () async {
    final session = BillingDraftSession(
        analyze: (_, __, ___) async => const BillingDraftAnalysis(drafts: [
              BillingDraft(BillInfo(amount: 20, type: BillType.expense))
            ]),
        persist: (_, __) async => throw StateError('late failure'));
    await session.update(images: [BillingImageFiles(File('A'), File('A'))]);
    await expectLater(session.confirm(), throwsStateError);
    expect(session.state, BillingDraftState.done);
    expect(await session.confirm(), isNull);
    await session.dispose();
  });
  test('draft parser preserves absent amount and time, validates associations',
      () {
    final analysis = BillingDraftAnalysis.parse('''{"drafts":[
      {"type":"expense","source_image_numbers":[1,1,3,0,-1,2.0,"2",99]},
      {"amount":68,"type":"expense","source_image_numbers":[-1]}],
      "needs_input":false,"missing_fields":[],"question":null}''', 3);
    expect(analysis.drafts, hasLength(2));
    expect(analysis.drafts.first.bill.amount, isNull);
    expect(analysis.drafts.first.bill.time, isNull);
    expect(analysis.ready, false);
    expect(analysis.drafts.first.sourceImageIndexes, [0, 2]);
    expect(analysis.drafts.last.attachmentIndexes(3), [0, 1, 2]);
    final time = DateTime(2026, 10, 9);
    expect(analysis.drafts.last.toBill(time).time, time);
    expect(analysis.drafts.last.toBill(time).amount, -68);
  });

  test(
      'amount/type/currency/transfer uncertainty blocks; optional absence does not',
      () {
    for (final json in [
      '{"amount":0,"type":"expense"}',
      '{"amount":20}',
      '{"amount":20,"type":"expense","currency":"???"}',
      '{"amount":20,"type":"transfer","from_account":"A"}',
      '{"amount":20,"type":"expense","uncertain_fields":["time"]}',
    ]) {
      expect(
          BillingDraftAnalysis.parse(
                  '{"drafts":[$json],"needs_input":false}', 1)
              .ready,
          false);
    }
    expect(
        BillingDraftAnalysis.parse(
                '{"drafts":[{"amount":20,"type":"expense"}],"needs_input":false}',
                1)
            .ready,
        true);
  });

  test(
      'full reanalysis with text/voice/additional image writes zero; confirm exactly once',
      () async {
    var writes = 0;
    var attachments = 0;
    final calls = <List<Object>>[];
    final gate = Completer<BookkeepingResult>();
    final session =
        BillingDraftSession(analyze: (images, replies, previous) async {
      calls.add([images.length, List.of(replies)]);
      return BillingDraftAnalysis(drafts: [
        BillingDraft(BillInfo(
            amount: replies.isEmpty ? null : 68, type: BillType.expense))
      ], needsInput: replies.isEmpty, question: 'Currency?');
    }, persist: (drafts, images) async {
      writes++;
      attachments += images.length;
      return gate.future;
    });
    await session.update(images: [BillingImageFiles(File('A'), File('A'))]);
    expect(session.state, BillingDraftState.needsInput);
    await session.update(reply: 'USD');
    await session.update(reply: 'voice transcript');
    await session.update(images: [BillingImageFiles(File('B'), File('B'))]);
    expect(calls.last, [
      2,
      ['USD', 'voice transcript']
    ]);
    expect(writes, 0);
    expect(attachments, 0);
    expect(session.state, BillingDraftState.ready);
    final saving = session.confirm();
    expect(session.state, BillingDraftState.saving);
    expect(await session.confirm(), isNull);
    gate.complete(const BookkeepingResult(transactionIds: [1], failedCount: 1));
    await saving;
    expect(writes, 1);
    expect(attachments, 2);
    expect(session.state, BillingDraftState.done);
    expect(await session.confirm(), isNull);
    await session.dispose();
  });

  for (final outcome in [
    'cancel',
    'dispose during analysis',
    'failure',
    'success'
  ]) {
    test('$outcome cleans only owned temporary recognition files', () async {
      final parent = await Directory.systemTemp.createTemp('draft-test-');
      final original =
          await File('${parent.path}/original.png').writeAsString('original');
      final temp = await parent.createTemp('recognition-');
      final recognition =
          await File('${temp.path}/copy.jpg').writeAsString('copy');
      final gate = Completer<BillingDraftAnalysis>();
      var writes = 0;
      final session = BillingDraftSession(
          analyze: (_, __, ___) => gate.future,
          persist: (_, __) async {
            writes++;
            return const BookkeepingResult(transactionIds: [1]);
          });
      final work = session
          .update(images: [BillingImageFiles(original, recognition, temp)]);
      Future<void>? disposal;
      if (outcome == 'dispose during analysis') disposal = session.dispose();
      if (outcome == 'failure') {
        gate.completeError(StateError('offline'));
        await expectLater(work, throwsStateError);
      } else {
        gate.complete(const BillingDraftAnalysis(drafts: [
          BillingDraft(BillInfo(amount: 20, type: BillType.expense))
        ]));
        await work;
        if (outcome == 'success') await session.confirm();
      }
      await disposal;
      await session.dispose();
      expect(await temp.exists(), false);
      expect(await original.exists(), true);
      expect(writes, outcome == 'success' ? 1 : 0);
      await parent.delete(recursive: true);
    });
  }
}
