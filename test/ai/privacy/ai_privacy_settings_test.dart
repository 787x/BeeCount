import 'package:beecount/ai/privacy/ai_privacy_consent.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/ai/ai_settings_page.dart';
import 'package:beecount/widgets/ai/ai_privacy_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget host() => const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: AISettingsPage(),
        ),
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ai_bill_extraction_enabled': true,
      AiPrivacyConsentStore.prefsKey: 1,
      'ai_providers_v2': '[]',
      'ai_capability_binding_v2': '{}',
    });
  });

  testWidgets(
      'enabled version 1 user sees new notice after settings load; cancel disables AI',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(AiPrivacyConsentDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ai_bill_extraction_enabled'), isFalse);
    expect(await AiPrivacyConsentStore.readVersion(), 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('accepting the notice stores version 2 and keeps AI enabled',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byType(AiPrivacyConsentDialog), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('ai_bill_extraction_enabled'), isTrue);
    expect(await AiPrivacyConsentStore.readVersion(), 2);
    expect(await AiPrivacyConsentStore.isConsented(), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
