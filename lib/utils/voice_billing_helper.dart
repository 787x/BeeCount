import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../providers/ai_config_providers.dart';
import '../ai/providers/ai_provider_manager.dart';
import '../ai/providers/ai_provider_config.dart';
import '../ai/providers/ai_provider_factory.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../widgets/ui/ui.dart';
import 'speech_input_helper.dart';

/// Speech is transcribed before entering the existing text bookkeeping service.
class VoiceBillingHelper {
  static bool _active = false;
  static Future<void> startVoiceBilling(
      BuildContext context, WidgetRef ref) async {
    if (_active) return;
    _active = true;
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(aiConfigProvider.notifier).ensureLoaded();
      final textProvider = await AIProviderManager.getProviderForCapability(
          AICapabilityType.text);
      if (!context.mounted) return;
      if (!ref.read(aiConfigProvider).enabled ||
          textProvider?.isValid != true ||
          textProvider?.supportsText != true) {
        showToast(context, l10n.fabActionVoiceDisabled);
        return;
      }
      final text = await ref.read(speechInputRequestProvider)(context, ref);
      if (!context.mounted || text == null || text.trim().isEmpty) return;
      final ledger = await ref.read(currentLedgerProvider.future);
      if (!context.mounted) return;
      if (ledger == null) {
        showToast(context, l10n.voiceRecordingNoLedger);
        return;
      }
      // Keep the transcript visible while the existing service owns extraction and writes.
      final navigator = Navigator.of(context, rootNavigator: true);
      final progress = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
              canPop: false,
              child: AlertDialog(
                  title: Text(l10n.voiceRecordingProcessing),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.voiceRecordingResultLabel),
                    Text(text),
                  ]))));
      navigator.push(progress);
      try {
        final result = await ref.read(aiBookkeeperProvider).fromText(
            text: text,
            ledgerId: ledger.id,
            billingTypes: [
              TagSeedService.billingTypeVoice,
              TagSeedService.billingTypeAi
            ],
            l10n: l10n);
        if (result.success) {
          await PostProcessor.run(ref, ledgerId: ledger.id, tags: true);
        }
        if (!context.mounted) return;
        final success = result.isMulti
            ? '${l10n.voiceRecordingSuccess} × ${result.savedCount}'
            : l10n.voiceRecordingSuccess;
        showToast(
            context,
            !result.success
                ? l10n.voiceRecordingNoInfoDetected(text)
                : result.unconvertedCurrencies.isEmpty
                    ? success
                    : '$success\n${l10n.aiBillingRateMissingHint(result.unconvertedCurrencies.join('、'))}');
      } finally {
        if (progress.isActive) navigator.removeRoute(progress);
      }
    } catch (error) {
      if (context.mounted) {
        showToast(
            context,
            l10n.voiceRecordingRecognizeFailed(
                AIProviderFactory.userFacingError(error)));
      }
    } finally {
      _active = false;
    }
  }
}
