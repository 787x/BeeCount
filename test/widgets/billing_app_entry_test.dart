import 'package:beecount/app.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/pages/transaction/transaction_editor_page.dart';
import 'package:beecount/providers/database_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'real center tap opens five entries; manual keeps quick-add editor; long press keeps radial actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final database = BeeDatabase.forTesting(NativeDatabase.memory());
    final repository = LocalRepository(database);
    addTearDown(database.close);
    await tester.runAsync(() => repository.createLedger(name: '账本'));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          repositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: const BeeApp())));
    await tester.pumpAndSettle();
    final center = find.byIcon(Icons.add_circle_outline);
    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(find.text('手动记账'), findsOneWidget);
    expect(find.text('文字记账'), findsOneWidget);
    await tester.tap(find.text('文字记账'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quick-billing-text')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(center);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    await tester.tap(find.text('手动记账'));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<TransactionEditorPage>(find.byType(TransactionEditorPage));
    expect(editor.initialKind, 'expense');
    expect(editor.quickAdd, isTrue);
    final editorContext = tester.element(find.byType(TransactionEditorPage));
    Navigator.of(editorContext).pop();
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(center));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
