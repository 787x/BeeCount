import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/smart_billing_providers.dart';
import '../../services/ai/quick_billing_policy.dart';
import '../ui/ui.dart';
import '../biz/biz.dart';

class QuickBillingPolicySettings extends ConsumerWidget {
  const QuickBillingPolicySettings({super.key});

  Future<void> _select<T>(
      BuildContext context,
      WidgetRef ref,
      String title,
      T current,
      List<(T, String, String)> choices,
      QuickBillingResultPolicy Function(QuickBillingResultPolicy, T)
          update) async {
    final selected = await showDialog<T>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final choice in choices)
                    RadioListTile<T>(
                        value: choice.$1,
                        groupValue: current,
                        title: Text(choice.$2),
                        subtitle: Text(choice.$3),
                        onChanged: (value) => Navigator.pop(context, value)),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context).commonCancel))
                ]));
    if (selected == null || !context.mounted) return;
    try {
      final latest = await ref.read(quickBillingPolicyProvider.future);
      await ref
          .read(quickBillingPolicyProvider.notifier)
          .setPolicy(update(latest, selected));
    } catch (_) {
      if (context.mounted) {
        showToast(context, AppLocalizations.of(context).commonError);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final value = ref.watch(quickBillingPolicyProvider);
    final policy = value.valueOrNull;
    if (policy == null) return const LinearProgressIndicator();
    return SectionCard(
        margin: EdgeInsets.zero,
        child: Column(children: [
          ListTile(title: Text(l10n.quickBillingPolicyTitle)),
          AppListTile(
              leading: Icons.search_off,
              title: l10n.quickBillingNoBill,
              subtitle: policy.noBillAction == NoBillAction.notify
                  ? l10n.quickBillingNotify
                  : l10n.quickBillingContinue,
              onTap: () => _select(
                  context,
                  ref,
                  l10n.quickBillingNoBill,
                  policy.noBillAction,
                  [
                    (
                      NoBillAction.notify,
                      l10n.quickBillingNotify,
                      l10n.quickBillingNotifyDesc
                    ),
                    (
                      NoBillAction.clarify,
                      l10n.quickBillingContinue,
                      l10n.quickBillingContinueDesc
                    ),
                  ],
                  (p, v) => p.copyWith(noBillAction: v))),
          AppListTile(
              leading: Icons.help_outline,
              title: l10n.quickBillingNeedsInput,
              subtitle: policy.needsInputAction == NeedsInputAction.clarify
                  ? l10n.quickBillingClarify
                  : l10n.quickBillingBestEffort,
              onTap: () => _select(
                  context,
                  ref,
                  l10n.quickBillingNeedsInput,
                  policy.needsInputAction,
                  [
                    (
                      NeedsInputAction.clarify,
                      l10n.quickBillingClarify,
                      l10n.quickBillingClarifyDesc
                    ),
                    (
                      NeedsInputAction.saveBestEffort,
                      l10n.quickBillingBestEffort,
                      l10n.quickBillingBestEffortDesc
                    ),
                  ],
                  (p, v) => p.copyWith(needsInputAction: v))),
          AppListTile(
              leading: Icons.check_circle_outline,
              title: l10n.quickBillingReady,
              subtitle: policy.readyAction == ReadyAction.saveImmediately
                  ? l10n.quickBillingSave
                  : l10n.quickBillingReview,
              onTap: () => _select(
                  context,
                  ref,
                  l10n.quickBillingReady,
                  policy.readyAction,
                  [
                    (
                      ReadyAction.saveImmediately,
                      l10n.quickBillingSave,
                      l10n.quickBillingSaveDesc
                    ),
                    (
                      ReadyAction.confirm,
                      l10n.quickBillingReview,
                      l10n.quickBillingReviewDesc
                    ),
                  ],
                  (p, v) => p.copyWith(readyAction: v))),
        ]));
  }
}
