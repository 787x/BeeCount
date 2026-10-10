import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/services/platform/app_link_service.dart';
import 'package:beecount/widgets/biz/billing_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'tap sheet exposes all five actions and returns their existing routes',
      (tester) async {
    AppLinkAction? selected;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
          builder: (context) => Scaffold(
              body: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    selected = await showModalBottomSheet<AppLinkAction>(
                        context: context,
                        builder: (_) => const BillingQuickActions());
                  }))),
    ));
    for (final action in [
      AppLinkAction.newTransaction,
      AppLinkAction.text,
      AppLinkAction.camera,
      AppLinkAction.image,
      AppLinkAction.voice
    ]) {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      final tiles = find.byType(ListTile);
      expect(tiles, findsNWidgets(6));
      expect(find.text('手动记账'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      await tester.tap(tiles.at([
            AppLinkAction.newTransaction,
            AppLinkAction.text,
            AppLinkAction.camera,
            AppLinkAction.image,
            AppLinkAction.voice
          ].indexOf(action) +
          1));
      await tester.pumpAndSettle();
      expect(selected, action);
    }
  });
}
