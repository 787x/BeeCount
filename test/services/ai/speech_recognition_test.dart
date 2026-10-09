import 'dart:convert';
import 'package:beecount/services/ai/speech_recognition.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('platform defaults and non-Android effective mode', () {
    expect(
        effectiveSpeechMode(null, android: true), SpeechRecognitionMode.auto);
    expect(
        effectiveSpeechMode(null, android: false), SpeechRecognitionMode.cloud);
    expect(effectiveSpeechMode('androidOnDevice', android: false),
        SpeechRecognitionMode.cloud);
    expect(effectiveSpeechMode('unknown', android: true),
        SpeechRecognitionMode.auto);
  });
  test('all preferences round trip without AI config notification', () async {
    SharedPreferences.setMockInitialValues({});
    var notifications = 0;
    final original = AIProviderManager.onConfigChanged;
    AIProviderManager.onConfigChanged = () => notifications++;
    addTearDown(() => AIProviderManager.onConfigChanged = original);
    for (final mode in SpeechRecognitionMode.values) {
      final settings = SpeechRecognitionSettings(android: true);
      await settings.loaded;
      await settings.setMode(mode);
      settings.dispose();
      final restored = SpeechRecognitionSettings(android: true);
      await restored.loaded;
      expect(restored.state, mode);
      restored.dispose();
    }
    expect(notifications, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {SpeechRecognitionSettings.preferenceKey});
  });
  test('recognition mode never enters AI snapshots or server application',
      () async {
    SharedPreferences.setMockInitialValues({
      'ai_providers_v2': '[]',
      'ai_capability_binding_v2': '{}',
      SpeechRecognitionSettings.preferenceKey: 'androidSystem',
    });
    final snapshot = await AIProviderManager.snapshotForSync();
    expect(jsonEncode(snapshot), isNot(contains('speech_recognition_mode')));
    await AIProviderManager.applyFromServer(
        {'speech_recognition_mode': 'cloud'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SpeechRecognitionSettings.preferenceKey),
        'androidSystem');
  });
  test(
      'auto chooses capabilities before listening, speech provider optional locally',
      () {
    for (final row in [
      (true, true, false, SpeechEngine.onDevice),
      (false, true, false, SpeechEngine.system),
      (false, false, true, SpeechEngine.cloud),
    ]) {
      expect(
          selectSpeechEngine(SpeechRecognitionMode.auto,
              onDeviceAvailable: row.$1,
              systemAvailable: row.$2,
              cloudAvailable: row.$3),
          row.$4);
    }
    expect(
        () => selectSpeechEngine(SpeechRecognitionMode.auto,
            onDeviceAvailable: false,
            systemAvailable: false,
            cloudAvailable: false),
        throwsA(isA<SpeechInputException>()));
  });
  test('explicit modes never fall back', () {
    for (final mode in [
      SpeechRecognitionMode.androidOnDevice,
      SpeechRecognitionMode.androidSystem,
      SpeechRecognitionMode.cloud
    ]) {
      expect(
          () => selectSpeechEngine(mode,
              onDeviceAvailable: mode != SpeechRecognitionMode.androidOnDevice,
              systemAvailable: mode != SpeechRecognitionMode.androidSystem,
              cloudAvailable: mode != SpeechRecognitionMode.cloud),
          throwsA(isA<SpeechInputException>()));
    }
  });
  test(
      'auto actually opens cloud after an advertised system fails before speech',
      () async {
    final calls = <SpeechEngine>[];
    final text = await recognizeSpeech(
        mode: SpeechRecognitionMode.auto,
        onDeviceAvailable: false,
        systemAvailable: true,
        cloudAvailable: () async => true,
        listen: (engine) async {
          calls.add(engine);
          if (engine == SpeechEngine.system) {
            throw const SpeechInputException('client', speechStarted: false);
          }
          return '午饭35';
        });
    expect(text, '午饭35');
    expect(calls, [SpeechEngine.system, SpeechEngine.cloud]);
  });
  test(
      'explicit system never runs cloud; speech and uncertain stages never retry',
      () async {
    for (final row in [
      (
        SpeechRecognitionMode.auto,
        const SpeechInputException('client',
            speechStarted: false, userStopped: true)
      ),
      (
        SpeechRecognitionMode.androidSystem,
        const SpeechInputException('client', speechStarted: false)
      ),
      (
        SpeechRecognitionMode.auto,
        const SpeechInputException('client', speechStarted: true)
      ),
      (
        SpeechRecognitionMode.auto,
        const SpeechInputException('network', speechStarted: true)
      ),
      (
        SpeechRecognitionMode.auto,
        const SpeechInputException('no_match', speechStarted: false)
      ),
      (SpeechRecognitionMode.auto, const SpeechInputException('client')),
    ]) {
      final calls = <SpeechEngine>[];
      var cloudChecks = 0;
      await expectLater(
          recognizeSpeech(
              mode: row.$1,
              onDeviceAvailable: false,
              systemAvailable: true,
              cloudAvailable: () async {
                cloudChecks++;
                return true;
              },
              listen: (engine) async {
                calls.add(engine);
                throw row.$2;
              }),
          throwsA(isA<SpeechInputException>()));
      expect(calls, [SpeechEngine.system]);
      expect(cloudChecks, 0);
    }
  });
  test(
      'language failures before speech advance auto; cloud is checked at fallback',
      () async {
    for (final code in ['language_unavailable', 'language_unsupported']) {
      var cloudCalls = 0;
      expect(
          await recognizeSpeech(
              mode: SpeechRecognitionMode.auto,
              onDeviceAvailable: true,
              systemAvailable: true,
              cloudAvailable: () async => true,
              listen: (engine) async {
                if (engine != SpeechEngine.cloud) {
                  throw SpeechInputException(code, speechStarted: false);
                }
                cloudCalls++;
                return 'ok';
              }),
          'ok');
      expect(cloudCalls, 1);
    }
    await expectLater(
        recognizeSpeech(
            mode: SpeechRecognitionMode.auto,
            onDeviceAvailable: false,
            systemAvailable: true,
            cloudAvailable: () async => false,
            listen: (_) async => throw const SpeechInputException('client',
                speechStarted: false)),
        throwsA(isA<SpeechInputException>()
            .having((e) => e.code, 'code', 'unavailable')));
  });
  final bridge = AndroidSpeechRecognition();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(bridge.channel, null));
  test(
      'fake native contract: availability, text, stop, cancel and another session',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(bridge.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'availability') {
        return {'systemAvailable': true, 'onDeviceAvailable': false};
      }
      if (call.method == 'startListening') {
        expect(call.arguments, {
          'sessionId': bridge.sessionId,
          'onDevice': false,
          'language': 'zh-CN'
        });
        return '午饭35';
      }
      return null;
    });
    expect(await bridge.availability(), (system: true, onDevice: false));
    expect(await bridge.start(SpeechEngine.system, 'zh-CN'), '午饭35');
    await bridge.stop();
    await bridge.cancel();
    expect(await bridge.start(SpeechEngine.system, 'zh-CN'), '午饭35');
    expect(calls, [
      'availability',
      'startListening',
      'stopListening',
      'cancelListening',
      'startListening'
    ]);
  });
  test('native stable errors survive without localized platform text',
      () async {
    for (final code in [
      'no_match',
      'permission_denied',
      'cancelled',
      'network'
    ]) {
      messenger.setMockMethodCallHandler(
          bridge.channel,
          (_) async =>
              throw PlatformException(code: code, message: 'native detail'));
      await expectLater(
          bridge.start(SpeechEngine.onDevice, 'zh-CN'),
          throwsA(
              isA<SpeechInputException>().having((e) => e.code, 'code', code)));
    }
  });
}
