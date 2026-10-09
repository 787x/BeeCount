import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/ai/core/ai_extraction_engine.dart';
import 'package:beecount/ai/core/bill_info.dart';
import 'package:beecount/ai/core/billing_draft.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/ai/billing_draft_page.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/providers/ai_chat_providers.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/ai/billing_image_service.dart';
import 'package:beecount/services/ai/bookkeeping_result.dart';
import 'package:beecount/services/billing/bill_creation_service.dart';
import 'package:beecount/utils/image_billing_helper.dart';
import 'package:beecount/utils/speech_input_helper.dart';

const _ready = BillingDraftAnalysis(
    drafts: [BillingDraft(BillInfo(amount: 20, type: BillType.expense))]);
const _needsInput = BillingDraftAnalysis(
    drafts: [BillingDraft(BillInfo(type: BillType.expense))],
    needsInput: true,
    question: 'Amount?');

class _Image extends BillingImageFiles {
  int disposals = 0;
  _Image(File file) : super(file, file);
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Images extends BillingImageService {
  List<File> files = [File('A')];
  final prepared = <_Image>[];
  @override
  Future<List<File>> pickImages({required bool keepOriginal}) async =>
      List.of(files);
  @override
  Future<File?> pickImage(ImageSource source,
          {required bool keepOriginal}) async =>
      files.isEmpty ? null : files.first;
  @override
  Future<BillingImageFiles> prepare(File file,
      {required bool keepOriginal}) async {
    final image = _Image(file);
    prepared.add(image);
    return image;
  }
}

class _Bookkeeper extends AiBookkeeper {
  final List<Object> responses;
  final requests = <({int images, List<String> replies})>[];
  int saves = 0;
  _Bookkeeper(LocalRepository repo, this.responses)
      : super(
            repository: repo,
            engine: const DefaultAiExtractionEngine(),
            persister: BillCreationService(repo));
  @override
  Future<BillingDraftAnalysis> analyzeImages(
      {required List<File> images,
      required int ledgerId,
      required List<String> replies,
      BillingDraftAnalysis? previous}) async {
    requests.add((images: images.length, replies: List.of(replies)));
    final response = responses.removeAt(0);
    if (response is BillingDraftAnalysis) return response;
    throw response;
  }

  @override
  Future<BookkeepingResult> persistDrafts(
      {required List<BillingDraft> drafts,
      required List<File> sourceImages,
      required int ledgerId,
      required List<String> billingTypes,
      required DateTime fallbackTime,
      AppLocalizations? l10n,
      Future<void> Function(int, File, int)? saveAttachment}) {
    saves++;
    return super.persistDrafts(
        drafts: drafts,
        sourceImages: sourceImages,
        ledgerId: ledgerId,
        billingTypes: billingTypes,
        fallbackTime: fallbackTime,
        l10n: l10n,
        saveAttachment: saveAttachment);
  }
}

class _Navigation extends NavigatorObserver {
  int clarifications = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'billing-clarification') clarifications++;
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
  }
  expect(ready(), true, reason: 'Expected image billing state did not arrive');
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BeeDatabase database;
  late LocalRepository repository;
  late _Images images;
  late _Navigation navigation;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai_privacy_consent_version': 3,
      'ai_providers_v2': '[]',
      'ai_capability_binding_v2': '{}'
    });
    database = BeeDatabase.forTesting(NativeDatabase.memory());
    repository = LocalRepository(database);
    await repository.createLedger(name: 'Test');
    images = _Images();
    navigation = _Navigation();
  });
  tearDown(() async {
    await database.close();
  });

  Widget host(_Bookkeeper bookkeeper) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            repositoryProvider.overrideWithValue(repository),
            aiBookkeeperProvider.overrideWithValue(bookkeeper),
            billingImageServiceProvider.overrideWithValue(images),
            smartBillingAutoAttachmentProvider.overrideWith((ref) => false),
            speechInputRequestProvider.overrideWithValue((_, __) async => '20'),
          ],
          child: MaterialApp(
              locale: const Locale('zh'),
              navigatorObservers: [navigation],
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                  builder: (context, ref, _) => Scaffold(
                          body: Column(children: [
                        TextButton(
                            onPressed: () =>
                                ImageBillingHelper.pickImageForBilling(
                                    context, ref),
                            child: const Text('gallery')),
                        TextButton(
                            onPressed: () =>
                                ImageBillingHelper.openCameraForBilling(
                                    context, ref),
                            child: const Text('camera')),
                      ])))));

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  }

  for (final entry in ['gallery', 'camera']) {
    for (final count in [1, 3]) {
      testWidgets(
          '$entry initial ready ($count images) saves without opening a page',
          (tester) async {
        images.files = List.generate(count, (i) => File('$i'));
        final bookkeeper = _Bookkeeper(repository, [_ready]);
        await tester.pumpWidget(host(bookkeeper));
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry));
        await _until(
            tester,
            () =>
                images.prepared.isNotEmpty &&
                images.prepared.every((i) => i.disposals == 1));
        expect(bookkeeper.saves, 1);
        expect(navigation.clarifications, 0);
        expect(find.byType(BillingDraftPage), findsNothing);
        expect(find.text('确认记账'), findsNothing);
        expect(
            await database.select(database.transactions).get(), hasLength(1));
        await finish(tester);
      });
    }
  }

  for (final reply in ['text', 'voice', 'gallery image', 'camera image']) {
    testWidgets('$reply clarification automatically saves and returns to entry',
        (tester) async {
      final bookkeeper = _Bookkeeper(repository, [_needsInput, _ready]);
      await tester.pumpWidget(host(bookkeeper));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gallery'));
      await _until(
          tester, () => find.byType(BillingDraftPage).evaluate().isNotEmpty);
      expect(bookkeeper.saves, 0);
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(await database.select(database.transactionAttachments).get(),
          isEmpty);
      expect(find.text('确认记账'), findsNothing);
      if (reply == 'text' || reply == 'voice') {
        if (reply == 'text') {
          await tester.enterText(find.byType(TextField), '20');
        } else {
          await tester.tap(find.byKey(const ValueKey('speech-input-mic')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('billing-draft-send')));
      } else {
        images.files = [File('B')];
        await tester.tap(find.text(reply == 'gallery image' ? '添加图片' : '补拍图片'));
      }
      await _until(
          tester,
          () =>
              bookkeeper.saves == 1 &&
              find.byType(BillingDraftPage).evaluate().isEmpty);
      expect(navigation.clarifications, 1);
      expect(await database.select(database.transactions).get(), hasLength(1));
      expect(bookkeeper.requests.last.images, reply.contains('image') ? 2 : 1);
      expect(bookkeeper.requests.last.replies,
          reply.contains('image') ? isEmpty : ['20']);
      expect(images.prepared.map((i) => i.disposals), everyElement(1));
      await finish(tester);
    });
  }

  testWidgets('duplicate entry callback does not start a second image session',
      (tester) async {
    final bookkeeper = _Bookkeeper(repository, [_ready]);
    await tester.pumpWidget(host(bookkeeper));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gallery'));
    await tester.tap(find.text('gallery'));
    await _until(
        tester,
        () =>
            images.prepared.isNotEmpty &&
            images.prepared.every((i) => i.disposals == 1));
    expect(bookkeeper.requests, hasLength(1));
    expect(bookkeeper.saves, 1);
    expect(navigation.clarifications, 0);
    expect(await database.select(database.transactions).get(), hasLength(1));
    await finish(tester);
  });

  for (final response in [
    const BillingDraftAnalysis(),
    AIException('temporary network failure')
  ]) {
    testWidgets(
        'no bill/provider error ends without navigating or writing: $response',
        (tester) async {
      final bookkeeper = _Bookkeeper(repository, [response]);
      await tester.pumpWidget(host(bookkeeper));
      await tester.pumpAndSettle();
      await tester.tap(find.text('gallery'));
      await _until(
          tester,
          () =>
              images.prepared.isNotEmpty &&
              images.prepared.single.disposals == 1);
      expect(bookkeeper.saves, 0);
      expect(navigation.clarifications, 0);
      expect(await database.select(database.transactions).get(), isEmpty);
      expect(await database.select(database.transactionAttachments).get(),
          isEmpty);
      expect(find.byType(BillingDraftPage), findsNothing);
      expect(
          find.textContaining(response is AIException
              ? 'temporary network failure'
              : '未识别到账单信息'),
          findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets(
      'clarification retry keeps images and answers and does not replay saving',
      (tester) async {
    final bookkeeper = _Bookkeeper(repository,
        [_needsInput, AIException('temporary network failure'), _ready]);
    await tester.pumpWidget(host(bookkeeper));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gallery'));
    await _until(
        tester, () => find.byType(BillingDraftPage).evaluate().isNotEmpty);
    await tester.enterText(find.byType(TextField), '20');
    await tester.tap(find.byKey(const ValueKey('billing-draft-send')));
    await _until(
        tester,
        () => find
            .byKey(const ValueKey('billing-draft-retry'))
            .evaluate()
            .isNotEmpty);
    expect(bookkeeper.saves, 0);
    expect(images.prepared.single.disposals, 0);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(
        await database.select(database.transactionAttachments).get(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('billing-draft-retry')));
    await _until(
        tester,
        () =>
            bookkeeper.saves == 1 &&
            find.byType(BillingDraftPage).evaluate().isEmpty);
    expect(bookkeeper.requests.last.replies, ['20']);
    expect(bookkeeper.requests.last.images, 1);
    expect(await database.select(database.transactions).get(), hasLength(1));
    expect(images.prepared.single.disposals, 1);
    await finish(tester);
  });

  testWidgets('cancel clarification and cancel picker never write',
      (tester) async {
    final bookkeeper = _Bookkeeper(repository, [_needsInput]);
    await tester.pumpWidget(host(bookkeeper));
    await tester.pumpAndSettle();
    images.files = [];
    await tester.tap(find.text('gallery'));
    await tester.pumpAndSettle();
    expect(bookkeeper.requests, isEmpty);
    expect(images.prepared, isEmpty);
    images.files = [File('A')];
    await tester.tap(find.text('gallery'));
    await _until(
        tester, () => find.byType(BillingDraftPage).evaluate().isNotEmpty);
    await tester.tap(find.text('取消'));
    await _until(tester, () => images.prepared.single.disposals == 1);
    expect(bookkeeper.saves, 0);
    expect(await database.select(database.transactions).get(), isEmpty);
    expect(
        await database.select(database.transactionAttachments).get(), isEmpty);
    await finish(tester);
  });
}
