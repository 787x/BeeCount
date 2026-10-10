import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../providers/ai_config_providers.dart';
import '../ai/providers/ai_provider_manager.dart';
import '../ai/providers/ai_provider_config.dart';
import '../ai/providers/ai_provider_factory.dart';
import '../providers/smart_billing_providers.dart';
import 'text_billing_helper.dart';
import '../widgets/ui/ui.dart';
import 'speech_input_helper.dart';

/// Existing speech recognition feeds the shared manual text draft flow.
class VoiceBillingHelper {
  static bool _active = false;
  static Future<void> startVoiceBilling(
      BuildContext context, WidgetRef ref) async {
    if (_active) return;
    _active = true;
    final l10n = AppLocalizations.of(context);
    try {
      final policy = await ref.read(quickBillingPolicyProvider.future);
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
      await TextBillingHelper.processText(context, ref,
          text: text, policy: policy, voice: true);
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
