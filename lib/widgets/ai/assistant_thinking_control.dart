import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../ai/providers/ai_provider_config.dart';
import '../../ai/providers/ai_provider_manager.dart';
import '../../providers/ai_config_providers.dart';
import '../../l10n/app_localizations.dart';

final assistantTextProviderProvider =
    FutureProvider<AIServiceProviderConfig?>((ref) {
  ref.watch(aiCapabilityBindingRefreshProvider);
  ref.watch(aiProviderListForCapabilityRefreshProvider);
  return AIProviderManager.getProviderForCapability(AICapabilityType.text);
});

/// The Assistant uses the provider's persisted setting, independently of billing.
class AssistantThinkingControl extends ConsumerStatefulWidget {
  final bool enabled;
  const AssistantThinkingControl({super.key, required this.enabled});
  @override
  ConsumerState<AssistantThinkingControl> createState() =>
      _AssistantThinkingControlState();
}

class _AssistantThinkingControlState
    extends ConsumerState<AssistantThinkingControl> {
  bool _saving = false;
  Future<void> _setThinking(
      AIServiceProviderConfig provider, bool value) async {
    if (_saving || !widget.enabled) return;
    setState(() => _saving = true);
    try {
      final latest = await AIProviderManager.getProvider(provider.id);
      if (!mounted ||
          !widget.enabled ||
          latest == null ||
          !latest.supportsThinkingControl) {
        return;
      }
      await AIProviderManager.updateProvider(
          latest.copyWith(assistantThinkingEnabled: value));
      if (mounted) {
        ref.read(aiProviderListForCapabilityRefreshProvider.notifier).state++;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(assistantTextProviderProvider).valueOrNull;
    if (provider == null || !provider.supportsThinkingControl) {
      return const SizedBox.shrink();
    }
    return Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          key: const ValueKey('assistant-thinking-toggle'),
          avatar: const Icon(Icons.psychology_outlined, size: 18),
          label: Text(AppLocalizations.of(context).aiMiMoAssistantThinking),
          selected: provider.assistantThinkingEnabled,
          onSelected: widget.enabled && !_saving
              ? (value) => _setThinking(provider, value)
              : null,
        ));
  }
}
