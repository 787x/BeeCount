import 'dart:convert';
import 'package:beecount/ai/providers/ai_provider_config.dart';
import 'package:beecount/ai/providers/ai_provider_manager.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/widgets/ai/assistant_thinking_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget host({bool enabled = true}) => ProviderScope(
      child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(body: AssistantThinkingControl(enabled: enabled))));
  void configure(AIServiceProviderConfig config) =>
      SharedPreferences.setMockInitialValues({
        'ai_providers_v2': jsonEncode([config.toJson()]),
        'ai_capability_binding_v2':
            jsonEncode(AICapabilityBinding(textProviderId: config.id).toJson()),
      });
  testWidgets('MiMo toggle persists Assistant only, billing stays unchanged',
      (tester) async {
    configure(AIServiceProviderConfig.xiaomiDefault);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('AI 助手深度思考'), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    final config = await AIProviderManager.getProvider('xiaomi_mimo');
    expect(config!.assistantThinkingEnabled, isFalse);
    expect(config.thinkingEnabled, isTrue);
    expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets(
      'DeepSeek toggle persists Assistant only, billing stays unchanged',
      (tester) async {
    configure(AIServiceProviderConfig.deepSeekDefault);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('AI 助手深度思考'), findsOneWidget);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    final config = await AIProviderManager.getProvider('deepseek');
    expect(config!.assistantThinkingEnabled, isFalse);
    expect(config.thinkingEnabled, isTrue);
    expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
  testWidgets('non-MiMo provider hides the control', (tester) async {
    configure(AIServiceProviderConfig.zhipuDefault);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(FilterChip), findsNothing);
  });
  testWidgets('running Agent disables the toggle', (tester) async {
    configure(AIServiceProviderConfig.xiaomiDefault);
    await tester.pumpWidget(host(enabled: false));
    await tester.pumpAndSettle();
    expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).onSelected, isNull);
    expect(
        (await AIProviderManager.getProvider('xiaomi_mimo'))!
            .assistantThinkingEnabled,
        isTrue);
  });
}
