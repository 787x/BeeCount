import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/ai_extraction_context.dart';
import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';

/// 可编程的 fake engine。不做 AI 调用,直接返回预设的 bills。
class _FakeEngine implements AiExtractionEngine {
  List<BillInfo> bills;
  AudioExtractionResult audio;

  _FakeEngine({
    this.bills = const [],
    this.audio = const AudioExtractionResult(),
  });

  @override
  Future<List<BillInfo>> extractFromText(String text, AiExtractionContext ctx,
          {String billGuard = ''}) async =>
      bills;

  @override
  Future<List<BillInfo>> extractFromImage(File image, AiExtractionContext ctx,
          {String billGuard = ''}) async =>
      bills;

  @override
  Future<AudioExtractionResult> extractFromAudio(
    File audio,
    AiExtractionContext ctx,
  ) async =>
      this.audio;

  @override
  Future<String?> speechToText(File audio) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;
  late BillCreationService persister;
  late int ledgerId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    persister = BillCreationService(repo);
    ledgerId = await repo.createLedger(name: 'test');
    // 准备一些可用分类供 BillCreationService 匹配
    await repo.createCategory(name: '餐饮', kind: 'expense');
    await repo.createCategory(name: '其他', kind: 'expense');
    await repo.createCategory(name: '工资', kind: 'income');
  });

  tearDown(() async {
    await db.close();
  });

  for (final sources in [
    [
      [0],
      [0]
    ],
    [
      [0, 1]
    ],
    [
      [0],
      [1, 2]
    ],
    [<int>[]]
  ]) {
    test(
        'confirmed source mapping $sources uses actual transaction attachments',
        () async {
      final bookkeeper = AiBookkeeper(
          repository: repo, engine: _FakeEngine(), persister: persister);
      final result = await bookkeeper.persistDrafts(
          drafts: [
            for (final indexes in sources)
              BillingDraft(const BillInfo(amount: 20, type: BillType.expense),
                  sourceImageIndexes: indexes)
          ],
          sourceImages: [File('A'), File('B'), File('C')],
          ledgerId: ledgerId,
          billingTypes: const [],
          fallbackTime: DateTime(2026, 10, 9),
          saveAttachment: (id, source, index) async {
            await repo.createAttachment(
                transactionId: id, fileName: source.path, sortOrder: index);
          });
      for (var i = 0; i < sources.length; i++) {
        final attachments =
            await repo.getAttachmentsByTransaction(result.transactionIds[i]);
        expect(
            attachments.map((a) => a.fileName).toList(),
            sources[i].isEmpty
                ? ['A', 'B', 'C']
                : sources[i].map((s) => ['A', 'B', 'C'][s]).toList());
      }
    });
  }

  test('preceding persistence failure does not shift attachment mapping',
      () async {
    final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: _FakeEngine(),
        persister: _FailFirstPersister(repo));
    final result = await bookkeeper.persistDrafts(
        drafts: const [
          BillingDraft(BillInfo(amount: 20, type: BillType.expense),
              sourceImageIndexes: [0]),
          BillingDraft(BillInfo(amount: 30, type: BillType.expense),
              sourceImageIndexes: [1])
        ],
        sourceImages: [File('A'), File('B')],
        ledgerId: ledgerId,
        billingTypes: const [],
        fallbackTime: DateTime(2026, 10, 9),
        saveAttachment: (id, source, index) async {
          await repo.createAttachment(
              transactionId: id, fileName: source.path, sortOrder: index);
        });
    expect(result.failedCount, 1);
    expect(result.savedCount, 1);
    expect(
        (await repo.getAttachmentsByTransaction(result.firstTransactionId!))
            .single
            .fileName,
        'B');
  });

  test('no attachment callback creates only transactions', () async {
    final bookkeeper = AiBookkeeper(
        repository: repo, engine: _FakeEngine(), persister: persister);
    final result = await bookkeeper.persistDrafts(
        drafts: const [
          BillingDraft(BillInfo(amount: 20, type: BillType.expense))
        ],
        sourceImages: [File('A')],
        ledgerId: ledgerId,
        billingTypes: const [],
        fallbackTime: DateTime(2026, 10, 9));
    expect(result.success, true);
    expect(await repo.getAllAttachments(), isEmpty);
  });

  group('AiBookkeeper.fromText', () {
    test('单笔成功 → savedBills.length == 1 + isMulti=false', () async {
      final engine = _FakeEngine(bills: [
        BillInfo(
          amount: -30,
          time: DateTime(2026, 5, 26, 12, 0),
          category: '餐饮',
          type: BillType.expense,
          note: '午餐',
        ),
      ]);
      final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: engine,
        persister: persister,
      );

      final result = await bookkeeper.fromText(
        text: '午餐30',
        ledgerId: ledgerId,
        billingTypes: const ['ai_chat'],
      );

      expect(result.success, isTrue);
      expect(result.savedBills, hasLength(1));
      expect(result.transactionIds, hasLength(1));
      expect(result.isMulti, isFalse);
      expect(result.failedCount, 0);
      expect(result.totalAbsAmount, 30);
    });

    test('多笔成功 → 全部入库, isMulti=true', () async {
      final engine = _FakeEngine(bills: [
        BillInfo(
          amount: -5,
          time: DateTime(2026, 5, 26, 9, 0),
          category: '餐饮',
          type: BillType.expense,
        ),
        BillInfo(
          amount: -40,
          time: DateTime(2026, 5, 26, 12, 0),
          category: '餐饮',
          type: BillType.expense,
        ),
        BillInfo(
          amount: -35,
          time: DateTime(2026, 5, 26, 19, 0),
          category: '餐饮',
          type: BillType.expense,
        ),
      ]);
      final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: engine,
        persister: persister,
      );

      final result = await bookkeeper.fromText(
        text: '早5中40晚35',
        ledgerId: ledgerId,
        billingTypes: const ['ai_chat'],
      );

      expect(result.success, isTrue);
      expect(result.savedBills, hasLength(3));
      expect(result.transactionIds, hasLength(3));
      expect(result.isMulti, isTrue);
      expect(result.totalAbsAmount, 80);
    });

    test('engine 返回空 → success=false', () async {
      final engine = _FakeEngine(bills: const []);
      final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: engine,
        persister: persister,
      );

      final result = await bookkeeper.fromText(
        text: 'noop',
        ledgerId: ledgerId,
        billingTypes: const ['ai_chat'],
      );

      expect(result.success, isFalse);
      expect(result.transactionIds, isEmpty);
      expect(result.savedBills, isEmpty);
    });

    test('ledgerId 被附加到保存后的 BillInfo', () async {
      final engine = _FakeEngine(bills: [
        BillInfo(
          amount: -30,
          time: DateTime(2026, 5, 26, 12, 0),
          category: '餐饮',
          type: BillType.expense,
        ),
      ]);
      final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: engine,
        persister: persister,
      );

      final result = await bookkeeper.fromText(
        text: 'x',
        ledgerId: ledgerId,
        billingTypes: const ['ai_chat'],
      );

      expect(result.savedBills.first.ledgerId, ledgerId);
    });
  });

  group('AiBookkeeper.fromAudio', () {
    test('返回 recognizedText 给 UI 展示', () async {
      final engine = _FakeEngine(
        audio: AudioExtractionResult(
          bills: [
            BillInfo(
              amount: -30,
              time: DateTime(2026, 5, 26, 12, 0),
              category: '餐饮',
              type: BillType.expense,
            ),
          ],
          recognizedText: '午餐30块',
        ),
      );
      final bookkeeper = AiBookkeeper(
        repository: repo,
        engine: engine,
        persister: persister,
      );

      // 必须有可用音频文件,fromAudio 内部会调 extractFromAudio
      // (fake engine 直接返回预设结果,无需读文件)
      final tempFile = await File.fromUri(
              Uri.file('${Directory.systemTemp.path}/test_audio.wav'))
          .create();
      final response = await bookkeeper.fromAudio(
        audio: tempFile,
        ledgerId: ledgerId,
        billingTypes: const ['voice'],
      );
      await tempFile.delete();

      expect(response.result.success, isTrue);
      expect(response.recognizedText, '午餐30块');
    });
  });
}

class _FailFirstPersister extends BillCreationService {
  _FailFirstPersister(super.repo);
  bool first = true;
  @override
  Future<int?> createFromBill(
      {required BillInfo bill,
      required int ledgerId,
      List<String>? billingTypes,
      List<String>? customTagNames,
      dynamic l10n,
      bool autoAddTags = true}) async {
    if (first) {
      first = false;
      return null;
    }
    return super.createFromBill(
        bill: bill, ledgerId: ledgerId, billingTypes: billingTypes);
  }
}
