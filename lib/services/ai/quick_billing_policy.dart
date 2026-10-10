import '../../ai/core/billing_draft.dart';

enum NoBillAction { notify, clarify }

enum NeedsInputAction { clarify, saveBestEffort }

enum ReadyAction { saveImmediately, confirm }

enum QuickBillingDecision { notify, clarify, persist, confirm }

/// Immutable, session-scoped preferences for foreground quick billing only.
class QuickBillingResultPolicy {
  final NoBillAction noBillAction;
  final NeedsInputAction needsInputAction;
  final ReadyAction readyAction;
  const QuickBillingResultPolicy({
    this.noBillAction = NoBillAction.notify,
    this.needsInputAction = NeedsInputAction.clarify,
    this.readyAction = ReadyAction.saveImmediately,
  });

  QuickBillingResultPolicy copyWith(
          {NoBillAction? noBillAction,
          NeedsInputAction? needsInputAction,
          ReadyAction? readyAction}) =>
      QuickBillingResultPolicy(
          noBillAction: noBillAction ?? this.noBillAction,
          needsInputAction: needsInputAction ?? this.needsInputAction,
          readyAction: readyAction ?? this.readyAction);

  Map<String, dynamic> toJson() => {
        'noBillAction': noBillAction.name,
        'needsInputAction': needsInputAction.name,
        'readyAction': readyAction.name,
      };

  factory QuickBillingResultPolicy.fromJson(Map<String, dynamic> json) {
    T read<T extends Enum>(List<T> values, String key, T fallback) =>
        values.where((v) => v.name == json[key]).firstOrNull ?? fallback;
    return QuickBillingResultPolicy(
        noBillAction:
            read(NoBillAction.values, 'noBillAction', NoBillAction.notify),
        needsInputAction: read(NeedsInputAction.values, 'needsInputAction',
            NeedsInputAction.clarify),
        readyAction: read(
            ReadyAction.values, 'readyAction', ReadyAction.saveImmediately));
  }

  QuickBillingDecision decide(BillingDraftAnalysis analysis) {
    if (analysis.drafts.isEmpty && !analysis.needsInput) {
      return noBillAction == NoBillAction.notify
          ? QuickBillingDecision.notify
          : QuickBillingDecision.clarify;
    }
    if (analysis.ready) {
      return readyAction == ReadyAction.confirm
          ? QuickBillingDecision.confirm
          : QuickBillingDecision.persist;
    }
    return needsInputAction == NeedsInputAction.saveBestEffort &&
            analysis.drafts.isNotEmpty &&
            analysis.drafts.every((d) => d.canAcceptCandidate)
        ? QuickBillingDecision.persist
        : QuickBillingDecision.clarify;
  }
}
