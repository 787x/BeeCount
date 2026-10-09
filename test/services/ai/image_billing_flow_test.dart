import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/services/ai/billing_draft_session.dart';
import 'package:beecount/services/ai/billing_image_service.dart';
import 'package:beecount/services/ai/bookkeeping_result.dart';
import 'package:beecount/services/ai/image_billing_flow.dart';

const ready = BillingDraftAnalysis(
    drafts: [BillingDraft(BillInfo(amount: 20, type: BillType.expense))]);
const needsInput = BillingDraftAnalysis(
    drafts: [BillingDraft(BillInfo(type: BillType.expense))],
    needsInput: true,
    question: 'Amount?');

class _Image extends BillingImageFiles {
  int disposals = 0;
  _Image(String name) : super(File(name), File(name));
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  for (final imageCount in [1, 3]) {
    test('initial ready with $imageCount images saves once without navigation',
        () async {
      var saves = 0;
      var navigations = 0;
      final images = List.generate(imageCount, (i) => _Image('$i'));
      final session = BillingDraftSession(analyze: (files, _, __) async {
        expect(files, hasLength(imageCount));
        return ready;
      }, persist: (_, __) async {
        saves++;
        return const BookkeepingResult(transactionIds: [1]);
      });
      final result = await ImageBillingFlow(session).run(
          images: images,
          clarify: (_) async {
            navigations++;
            return null;
          });
      expect(result!.success, true);
      expect(saves, 1);
      expect(navigations, 0);
      expect(await session.saveReady(), isNull);
      expect(images.map((i) => i.disposals), everyElement(1));
    });
  }

  test('needsInput opens clarification with zero writes; cancel disposes once',
      () async {
    var saves = 0;
    var navigations = 0;
    final image = _Image('A');
    final session = BillingDraftSession(
        analyze: (_, __, ___) async => needsInput,
        persist: (_, __) async {
          saves++;
          return BookkeepingResult.empty;
        });
    final result = await ImageBillingFlow(session).run(
        images: [image],
        clarify: (borrowed) async {
          navigations++;
          expect(borrowed, same(session));
          expect(saves, 0);
          expect(borrowed.state, BillingDraftState.needsInput);
          final disposal = borrowed.dispose();
          expect(borrowed.dispose(), same(disposal));
          await disposal;
          return null;
        });
    expect(result, isNull);
    expect(navigations, 1);
    expect(saves, 0);
    expect(image.disposals, 1);
  });

  test('no bill does not open clarification or write', () async {
    var saves = 0;
    var navigations = 0;
    final image = _Image('A');
    final session = BillingDraftSession(
        analyze: (_, __, ___) async => const BillingDraftAnalysis(),
        persist: (_, __) async {
          saves++;
          return BookkeepingResult.empty;
        });
    final result = await ImageBillingFlow(session).run(
        images: [image],
        clarify: (_) async {
          navigations++;
          return null;
        });
    expect(result, same(BookkeepingResult.empty));
    expect(saves, 0);
    expect(navigations, 0);
    expect(image.disposals, 1);
  });

  test('provider failure ends initial flow without navigation or writes',
      () async {
    var saves = 0;
    var navigations = 0;
    final image = _Image('A');
    final session = BillingDraftSession(
        analyze: (_, __, ___) async => throw StateError('offline'),
        persist: (_, __) async {
          saves++;
          return BookkeepingResult.empty;
        });
    await expectLater(
        ImageBillingFlow(session).run(
            images: [image],
            clarify: (_) async {
              navigations++;
              return null;
            }),
        throwsStateError);
    expect(saves, 0);
    expect(navigations, 0);
    expect(image.disposals, 1);
  });

  test('closed entry does not save after in-flight analysis becomes ready',
      () async {
    var saves = 0;
    final image = _Image('A');
    final session = BillingDraftSession(
        analyze: (_, __, ___) async => ready,
        persist: (_, __) async {
          saves++;
          return BookkeepingResult.empty;
        });
    expect(
        await ImageBillingFlow(session).run(
            images: [image],
            isActive: () => false,
            clarify: (_) async => throw StateError('must not navigate')),
        isNull);
    expect(saves, 0);
    expect(image.disposals, 1);
  });

  test('transient clarification failure keeps complete context for retry',
      () async {
    var calls = 0;
    var saves = 0;
    final image = _Image('A');
    final session =
        BillingDraftSession(analyze: (images, replies, previous) async {
      calls++;
      if (calls == 1) return needsInput;
      expect(images, hasLength(1));
      expect(replies, ['20']);
      expect(previous, same(needsInput));
      if (calls == 2) throw StateError('offline');
      return ready;
    }, persist: (_, __) async {
      saves++;
      return const BookkeepingResult(transactionIds: [1]);
    });
    final result = await ImageBillingFlow(session).run(
        images: [image],
        clarify: (session) async {
          await expectLater(session.update(reply: '20'), throwsStateError);
          expect(image.disposals, 0);
          expect(session.analysis, same(needsInput));
          expect(session.state, BillingDraftState.needsInput);
          expect(await session.saveReady(), isNull);
          expect(saves, 0);
          await session.update();
          return session.saveReady();
        });
    expect(result!.success, true);
    expect(saves, 1);
    expect(image.disposals, 1);
  });
}
