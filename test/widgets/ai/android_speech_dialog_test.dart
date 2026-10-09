import 'dart:async';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers/voice_billing_providers.dart';
import 'package:beecount/services/ai/speech_recognition.dart';
import 'package:beecount/widgets/ai/android_speech_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bridge extends AndroidSpeechRecognition {
  final pending = Completer<String?>();
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  @override
  Future<String?> start(SpeechEngine engine, String language) {
    starts++;
    return pending.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (!pending.isCompleted) {
      pending.completeError(const SpeechInputException('cancelled'));
    }
  }
}

void main() {
  Future<void> open(WidgetTester tester, _Bridge bridge,
      {VoiceTriggerMode mode = VoiceTriggerMode.auto,
      ValueChanged<String?>? onResult}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    final text = await showDialog<String>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => AndroidSpeechDialog(
                            bridge: bridge,
                            engine: SpeechEngine.system,
                            language: 'zh-CN',
                            triggerMode: mode));
                    onResult?.call(text);
                  },
                  child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('auto result returns text and disposes session', (tester) async {
    final bridge = _Bridge();
    String? result;
    await open(tester, bridge, onResult: (text) => result = text);
    expect(bridge.starts, 1);
    bridge.pending.complete('午饭35');
    await tester.pumpAndSettle();
    expect(result, '午饭35');
    expect(bridge.cancels, 1);
  });
  testWidgets(
      'hold starts on press, release stops once, cancellation returns no text',
      (tester) async {
    final bridge = _Bridge();
    String? result;
    await open(tester, bridge,
        mode: VoiceTriggerMode.holdToTalk, onResult: (text) => result = text);
    expect(bridge.starts, 0);
    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.mic)));
    await tester.pump();
    expect(bridge.starts, 1);
    await gesture.up();
    await tester.pump();
    expect(bridge.stops, 1);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(bridge.cancels, 1);
  });
  testWidgets('no-match is friendly and never starts a second engine',
      (tester) async {
    final bridge = _Bridge();
    await open(tester, bridge);
    bridge.pending.completeError(const SpeechInputException('no_match'));
    await tester.pumpAndSettle();
    expect(bridge.starts, 1);
    expect(bridge.cancels, 1);
    await tester.pump(const Duration(seconds: 3));
  });
}
