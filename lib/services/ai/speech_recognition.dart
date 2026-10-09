import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local recognition preference; deliberately outside AI config sync.
enum SpeechRecognitionMode { auto, androidOnDevice, androidSystem, cloud }

/// Selected recognition capability for one input session.
enum SpeechEngine { onDevice, system, cloud }

class SpeechInputException implements Exception {
  final String code;
  final bool? speechStarted;
  final bool userStopped;
  const SpeechInputException(this.code,
      {this.speechStarted, this.userStopped = false});

  bool get canTryNextEngine =>
      !userStopped &&
      speechStarted == false &&
      const {
        'unavailable',
        'on_device_unavailable',
        'system_unavailable',
        'client',
        'language_unsupported',
        'language_unavailable',
        'network',
        'server',
        'support_unavailable',
      }.contains(code);
}

SpeechRecognitionMode effectiveSpeechMode(String? saved,
    {required bool android}) {
  if (!android) return SpeechRecognitionMode.cloud;
  return SpeechRecognitionMode.values.firstWhere(
    (mode) => mode.name == saved,
    orElse: () => SpeechRecognitionMode.auto,
  );
}

/// Selects before listening; explicit modes never fall back.
SpeechEngine selectSpeechEngine(
  SpeechRecognitionMode mode, {
  required bool onDeviceAvailable,
  required bool systemAvailable,
  required bool cloudAvailable,
}) {
  switch (mode) {
    case SpeechRecognitionMode.auto:
      if (onDeviceAvailable) return SpeechEngine.onDevice;
      if (systemAvailable) return SpeechEngine.system;
      if (cloudAvailable) return SpeechEngine.cloud;
      throw const SpeechInputException('unavailable');
    case SpeechRecognitionMode.androidOnDevice:
      if (onDeviceAvailable) return SpeechEngine.onDevice;
      throw const SpeechInputException('on_device_unavailable');
    case SpeechRecognitionMode.androidSystem:
      if (systemAvailable) return SpeechEngine.system;
      throw const SpeechInputException('system_unavailable');
    case SpeechRecognitionMode.cloud:
      if (cloudAvailable) return SpeechEngine.cloud;
      throw const SpeechInputException('cloud_unavailable');
  }
}

class SpeechRecognitionSettings extends StateNotifier<SpeechRecognitionMode> {
  static const preferenceKey = 'speech_recognition_mode';
  final bool android;
  late final Future<void> loaded;

  SpeechRecognitionSettings({bool? android})
      : android = android ?? Platform.isAndroid,
        super(
            effectiveSpeechMode(null, android: android ?? Platform.isAndroid)) {
    loaded = _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      state =
          effectiveSpeechMode(prefs.getString(preferenceKey), android: android);
    }
  }

  Future<void> setMode(SpeechRecognitionMode mode) async {
    await loaded;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, mode.name);
    if (mounted) state = effectiveSpeechMode(mode.name, android: android);
  }
}

final speechRecognitionSettingsProvider =
    StateNotifierProvider<SpeechRecognitionSettings, SpeechRecognitionMode>(
  (ref) => SpeechRecognitionSettings(),
);

/// Thin Android speech contract; create one instance per input session.
/// Session IDs keep delayed disposal from cancelling a newer recognizer.
class AndroidSpeechRecognition {
  static int _nextSessionId = 0;
  final int sessionId = ++_nextSessionId;
  final MethodChannel channel;
  AndroidSpeechRecognition(
      {this.channel = const MethodChannel('com.tntlikely.beecount/speech')});

  Future<({bool system, bool onDevice})> availability() async {
    final result =
        await channel.invokeMapMethod<String, dynamic>('availability');
    return (
      system: result?['systemAvailable'] == true,
      onDevice: result?['onDeviceAvailable'] == true
    );
  }

  Future<String?> start(SpeechEngine engine, String language) async {
    try {
      return await channel.invokeMethod<String>('startListening', {
        'sessionId': sessionId,
        'onDevice': engine == SpeechEngine.onDevice,
        'language': language,
      });
    } on PlatformException catch (error) {
      final details = error.details;
      throw SpeechInputException(error.code,
          speechStarted:
              details is Map ? details['speechStarted'] as bool? : null);
    }
  }

  Future<void> stop() =>
      channel.invokeMethod<void>('stopListening', {'sessionId': sessionId});
  Future<void> cancel() =>
      channel.invokeMethod<void>('cancelListening', {'sessionId': sessionId});
}

/// Runtime fallback is limited to definite initialization failures before speech.
Future<String?> recognizeSpeech({
  required SpeechRecognitionMode mode,
  required bool onDeviceAvailable,
  required bool systemAvailable,
  required Future<bool> Function() cloudAvailable,
  required Future<String?> Function(SpeechEngine) listen,
}) async {
  if (mode != SpeechRecognitionMode.auto) {
    final engine = selectSpeechEngine(mode,
        onDeviceAvailable: onDeviceAvailable,
        systemAvailable: systemAvailable,
        cloudAvailable: mode == SpeechRecognitionMode.cloud
            ? await cloudAvailable()
            : false);
    return listen(engine);
  }
  for (final engine in [
    if (onDeviceAvailable) SpeechEngine.onDevice,
    if (systemAvailable) SpeechEngine.system,
  ]) {
    try {
      return await listen(engine);
    } on SpeechInputException catch (error) {
      if (!error.canTryNextEngine) rethrow;
    }
  }
  if (await cloudAvailable()) return listen(SpeechEngine.cloud);
  throw const SpeechInputException('unavailable');
}
