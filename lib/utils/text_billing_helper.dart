import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../pages/ai/billing_draft_page.dart';
import '../services/ai/billing_draft_session.dart';
import '../services/ai/bookkeeping_result.dart';
import '../services/ai/quick_billing_flow.dart';
import '../services/ai/quick_billing_policy.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../services/system/logger_service.dart';
import '../widgets/ai/ai_privacy_consent_dialog.dart';
import '../widgets/ui/ui.dart';
import 'image_billing_helper.dart';

/// One-shot input and shared draft processing for text and transcribed speech.
class TextBillingHelper {
  static bool _active = false;
  static Future<void> startTextBilling(
      BuildContext context, WidgetRef ref) async {
    if (_active) return;
    _active = true;
    try {
      final policy = await ref.read(quickBillingPolicyProvider.future);
      if (!context.mounted) return;
      final text = await showDialog<String>(
          context: context, builder: (_) => const _TextBillingInput());
      if (!context.mounted || text == null || text.trim().isEmpty) return;
      await processText(context, ref, text: text, policy: policy);
    } catch (error) {
      if (context.mounted) {
        showToast(
            context, imageBillingError(AppLocalizations.of(context), error));
      }
    } finally {
      _active = false;
    }
  }

  static Future<void> processText(BuildContext context, WidgetRef ref,
      {required String text,
      required QuickBillingResultPolicy policy,
      bool voice = false}) async {
    if (text.trim().isEmpty) return;
    if (!await ensureAiPrivacyConsent(context, ref) || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final l10n = AppLocalizations.of(context);
    final ledger = await container.read(currentLedgerProvider.future);
    if (!context.mounted) return;
    if (ledger == null) {
      showToast(context, l10n.aiOcrNoLedger);
      return;
    }
    final bookkeeper = container.read(aiBookkeeperProvider);
    final session = BillingDraftSession(
        policy: policy,
        allowImages: false,
        analyze: (_, replies, previous) => bookkeeper.analyzeText(
            text: text,
            ledgerId: ledger.id,
            replies: replies,
            previous: previous),
        persist: (drafts, _) async {
          final result = await bookkeeper.persistDrafts(
              drafts: drafts,
              sourceImages: const [],
              ledgerId: ledger.id,
              billingTypes: [
                if (voice) TagSeedService.billingTypeVoice,
                TagSeedService.billingTypeAi
              ],
              fallbackTime: DateTime.now(),
              l10n: l10n);
          if (result.success) {
            try {
              await PostProcessor.runC(container,
                  ledgerId: ledger.id, tags: true);
            } catch (_) {
              logger.warning('QuickBilling', '交易已保存，后处理失败');
            }
          }
          return result;
        });
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
                content: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.quickBillingAnalyzing)
            ]))));
    void hideProgress() {
      if (progress.isActive) navigator.removeRoute(progress);
    }

    unawaited(navigator.push(progress));
    try {
      final result = await QuickBillingFlow(session).run(
          isActive: () => context.mounted,
          clarify: (session) async {
            hideProgress();
            if (!context.mounted) return null;
            return Navigator.of(context).push<BookkeepingResult>(
                MaterialPageRoute(
                    settings:
                        const RouteSettings(name: 'billing-clarification'),
                    builder: (_) => BillingDraftPage(
                        session: session, currency: ledger.currency)));
          });
      hideProgress();
      if (context.mounted && result != null) {
        ImageBillingHelper.showResult(context, l10n, result,
            noBillMessage: l10n.quickBillingNoBillNotice);
      }
    } finally {
      hideProgress();
    }
  }
}

class _TextBillingInput extends StatefulWidget {
  const _TextBillingInput();
  @override
  State<_TextBillingInput> createState() => _TextBillingInputState();
}

class _TextBillingInputState extends State<_TextBillingInput> {
  final _text = TextEditingController();
  bool _submitted = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
        title: Text(l10n.billingTextAction),
        content: TextField(
            key: const ValueKey('quick-billing-text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: l10n.billingTextHint)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel)),
          FilledButton(
              key: const ValueKey('quick-billing-text-submit'),
              onPressed: _submitted || _text.text.trim().isEmpty
                  ? null
                  : () {
                      setState(() => _submitted = true);
                      Navigator.pop(context, _text.text.trim());
                    },
              child: Text(l10n.quickBillingAnalyze)),
        ]);
  }
}
