import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/settings/smart_billing_page.dart';
import 'package:beecount/providers/smart_billing_providers.dart';
import 'package:beecount/services/ai/quick_billing_policy.dart';

void main() {
  testWidgets('Smart Billing selections persist all three policies and reload',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget host() => const ProviderScope(
        child: MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SmartBillingPage()));
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    for (final choice in [
      ('未识别到账单', '继续补充信息'),
      ('信息不足', '尽量直接记账'),
      ('信息完整', '记账前确认')
    ]) {
      await tester.scrollUntilVisible(find.text(choice.$1), 150);
      await tester.tap(find.text(choice.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice.$2));
      await tester.pumpAndSettle();
      expect(find.text(choice.$2), findsOneWidget);
    }
    final prefs = await SharedPreferences.getInstance();
    expect(
        jsonDecode(prefs.getString(QuickBillingPolicyNotifier.preferenceKey)!),
        const QuickBillingResultPolicy(
                noBillAction: NoBillAction.clarify,
                needsInputAction: NeedsInputAction.saveBestEffort,
                readyAction: ReadyAction.confirm)
            .toJson());
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('快捷记账结果处理'), 150);
    expect(find.text('继续补充信息'), findsOneWidget);
    expect(find.text('尽量直接记账'), findsOneWidget);
    expect(find.text('记账前确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
