// Platform interfaces are supplied by the existing record/path_provider plugins.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:beecount/ai/privacy/ai_privacy_consent.dart';
import 'package:flutter/services.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'dart:convert';
import 'package:beecount/ai/providers/ai_constants.dart';
import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/ai_chat_providers.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:beecount/services/ai/ai_bookkeeper.dart';
import 'package:beecount/services/ai/bookkeeping_result.dart';
import 'package:beecount/services/data/tag_seed_service.dart';
import 'package:beecount/utils/speech_input_helper.dart';
import 'package:beecount/utils/voice_billing_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Bookkeeper implements AiBookkeeper {
  String? transcript = '午饭35';
  int sttCalls = 0;
  @override
  Future<String?> speechToText(File audio) async {
    sttCalls++;
    return transcript;
  }

  final calls = <({String text, int ledgerId, List<String> tags})>[];
  @override
  Future<BookkeepingResult> fromText(
      {required String text,
      required int ledgerId,
      required List<String> billingTypes,
      String billGuard = '',
      AppLocalizations? l10n}) async {
    calls.add((text: text, ledgerId: ledgerId, tags: billingTypes));
    return BookkeepingResult.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recorder extends RecordPlatform {
  int starts = 0;
  int disposals = 0;
  @override
  Future<void> create(String recorderId) async {}
  @override
  Future<void> start(String recorderId, RecordConfig config,
      {required String path}) async {
    expect(config.encoder, AudioEncoder.wav);
    starts++;
  }

  @override
  Future<String?> stop(String recorderId) async => null;
  @override
  Future<void> dispose(String recorderId) async {
    disposals++;
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();
  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: -60, max: -60);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Paths extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  setUp(() {
    final textOnly = AIServiceProviderConfig(
        id: 'text',
        name: 'text',
        apiKey: 'fake-key',
        baseUrl: 'https://example.invalid',
        textModel: 'text-model',
        audioModel: 'speech-model',
        createdAt: DateTime(2026));
    SharedPreferences.setMockInitialValues({
      AiPrivacyConsentStore.prefsKey: kAiPrivacyConsentVersion,
      AIConstants.keyAiBillExtractionEnabled: true,
      'ai_providers_v2': jsonEncode([textOnly.toJson()]),
      'ai_capability_binding_v2': jsonEncode(
          const AICapabilityBinding(textProviderId: 'text').toJson()),
    });
  });
  Widget host(_Bookkeeper bookkeeper, SpeechInputRequest input) =>
      ProviderScope(
        overrides: [
          aiBookkeeperProvider.overrideWithValue(bookkeeper),
          speechInputRequestProvider.overrideWithValue(input),
          currentLedgerProvider.overrideWith((ref) => Stream.value(Ledger(
              id: 7,
              name: '账本',
              currency: 'CNY',
              type: 'local',
              createdAt: DateTime(2026),
              myRole: 'owner',
              memberCount: 1,
              isShared: false,
              monthStartDay: 1))),
        ],
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Consumer(
                builder: (context, ref, _) => Scaffold(
                    body: TextButton(
                        onPressed: () =>
                            VoiceBillingHelper.startVoiceBilling(context, ref),
                        child: const Text('record'))))),
      );
  testWidgets(
      'local speech without speech provider reaches fromText with voice + AI tags',
      (tester) async {
    final bookkeeper = _Bookkeeper();
    var inputCalls = 0;
    await tester.pumpWidget(host(bookkeeper, (_, __) async {
      inputCalls++;
      return '午饭35';
    }));
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    expect(inputCalls, 1);
    expect(bookkeeper.calls.single.text, '午饭35');
    expect(bookkeeper.calls.single.ledgerId, 7);
    expect(bookkeeper.calls.single.tags,
        [TagSeedService.billingTypeVoice, TagSeedService.billingTypeAi]);
    expect(find.textContaining('午饭35'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('cancel, empty and STT failure never enter accounting service',
      (tester) async {
    final bookkeeper = _Bookkeeper();
    for (final result in [null, '', '   ']) {
      await tester.pumpWidget(host(bookkeeper, (_, __) async => result));
      await tester.tap(find.text('record'));
      await tester.pumpAndSettle();
      expect(bookkeeper.calls, isEmpty);
    }
    await tester.pumpWidget(host(
        bookkeeper, (_, __) async => throw StateError('fake STT failure')));
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    expect(bookkeeper.calls, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets(
      'cloud recording transcribes before entering the same fromText flow',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('speech_recognition_mode', 'cloud');
    await prefs.setString(
        'ai_capability_binding_v2',
        jsonEncode(const AICapabilityBinding(
                textProviderId: 'text', speechProviderId: 'text')
            .toJson()));
    final originalRecorder = RecordPlatform.instance;
    final originalPaths = PathProviderPlatform.instance;
    final recorder = _Recorder();
    RecordPlatform.instance = recorder;
    PathProviderPlatform.instance = _Paths();
    const permission =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permission, (_) async => 1);
    addTearDown(() {
      RecordPlatform.instance = originalRecorder;
      PathProviderPlatform.instance = originalPaths;
      messenger.setMockMethodCallHandler(permission, null);
    });
    final bookkeeper = _Bookkeeper();
    await tester.pumpWidget(host(bookkeeper, SpeechInputHelper.recognize));
    await tester.tap(find.text('record'));
    for (var i = 0; i < 20 && find.text('完成').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(recorder.starts, 1);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(bookkeeper.sttCalls, 1);
    expect(bookkeeper.calls.single.text, '午饭35');
    expect(bookkeeper.calls.single.tags,
        [TagSeedService.billingTypeVoice, TagSeedService.billingTypeAi]);
    await tester.pump(const Duration(seconds: 3));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(recorder.disposals, 1);
  });
  testWidgets(
      'microphone denial never records or writes; permanent denial offers settings',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('speech_recognition_mode', 'cloud');
    await prefs.setString(
        'ai_capability_binding_v2',
        jsonEncode(const AICapabilityBinding(
                textProviderId: 'text', speechProviderId: 'text')
            .toJson()));
    final original = RecordPlatform.instance;
    final recorder = _Recorder();
    RecordPlatform.instance = recorder;
    const permission =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var status = 0;
    messenger.setMockMethodCallHandler(permission, (call) async {
      if (call.method == 'requestPermissions') {
        return {for (final value in call.arguments as List) value: status};
      }
      return status;
    });
    addTearDown(() {
      RecordPlatform.instance = original;
      messenger.setMockMethodCallHandler(permission, null);
    });
    final bookkeeper = _Bookkeeper();
    await tester.pumpWidget(host(bookkeeper, SpeechInputHelper.recognize));
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    expect(recorder.starts, 0);
    expect(bookkeeper.calls, isEmpty);
    expect(bookkeeper.sttCalls, 0);
    await tester.pump(const Duration(seconds: 3));
    status = 4;
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(recorder.starts, 0);
    expect(bookkeeper.calls, isEmpty);
  });
  testWidgets('version 1 user cannot start speech before accepting version 2',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AiPrivacyConsentStore.prefsKey, 1);
    final original = RecordPlatform.instance;
    final recorder = _Recorder();
    RecordPlatform.instance = recorder;
    const permission =
        MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var permissionCalls = 0;
    messenger.setMockMethodCallHandler(permission, (_) async {
      permissionCalls++;
      return 1;
    });
    addTearDown(() {
      RecordPlatform.instance = original;
      messenger.setMockMethodCallHandler(permission, null);
    });
    final bookkeeper = _Bookkeeper();
    await tester.pumpWidget(host(bookkeeper, SpeechInputHelper.recognize));
    await tester.tap(find.text('record'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(await AiPrivacyConsentStore.isConsented(), isFalse);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await AiPrivacyConsentStore.readVersion(), 1);
    expect(permissionCalls, 0);
    expect(recorder.starts, 0);
    expect(bookkeeper.sttCalls, 0);
    expect(bookkeeper.calls, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
