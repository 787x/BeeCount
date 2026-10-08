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
