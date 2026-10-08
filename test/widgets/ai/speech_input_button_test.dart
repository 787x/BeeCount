import 'dart:async';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/utils/speech_input_helper.dart';
import 'package:beecount/widgets/ai/speech_input_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
          TextEditingController controller, Future<String?> Function() input,
          {bool enabled = true}) =>
      ProviderScope(
        overrides: [
          speechInputRequestProvider.overrideWithValue((_, __) => input())
        ],
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
                body: Row(children: [
              SpeechInputButton(controller: controller, enabled: enabled),
              Expanded(child: TextField(controller: controller)),
            ]))),
      );
  testWidgets('mic adds recognized text to draft without submitting',
      (tester) async {
    final controller = TextEditingController(text: '已有草稿');
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, () async => '午饭35'));
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(controller.text, '已有草稿 午饭35');
    expect(find.text('已有草稿 午饭35'), findsOneWidget);
  });
  testWidgets('current selection receives text', (tester) async {
    final controller = TextEditingController(text: '前文 后文')
      ..selection = const TextSelection.collapsed(offset: 3);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, () async => '午饭35'));
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(controller.text, '前文 午饭35 后文');
  });
  testWidgets('cancel and empty results keep draft unchanged', (tester) async {
    final controller = TextEditingController(text: 'draft');
    addTearDown(controller.dispose);
    for (final text in [null, '', '  ']) {
      await tester.pumpWidget(host(controller, () async => text));
      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pumpAndSettle();
      expect(controller.text, 'draft');
    }
  });
  testWidgets('running agent disables mic and duplicate taps are guarded',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var calls = 0;
    final pending = Completer<String?>();
    Future<String?> input() {
      calls++;
      return pending.future;
    }

    await tester.pumpWidget(host(controller, input, enabled: false));
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    await tester.pumpWidget(host(controller, input));
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
  });
}
