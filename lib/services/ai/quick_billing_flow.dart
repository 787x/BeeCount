import 'billing_draft_session.dart';
import 'billing_image_service.dart';
import 'bookkeeping_result.dart';
import 'quick_billing_policy.dart';

/// Owns cleanup and applies the same decision for text, speech and images.
class QuickBillingFlow {
  final BillingDraftSession session;
  const QuickBillingFlow(this.session);

  Future<BookkeepingResult?> run({
    List<BillingImageFiles> images = const [],
    required Future<BookkeepingResult?> Function(BillingDraftSession) clarify,
    bool Function()? isActive,
  }) async {
    try {
      await session.update(images: images);
      if (!(isActive?.call() ?? true)) return null;
      switch (session.decision) {
        case QuickBillingDecision.notify:
          return BookkeepingResult.empty;
        case QuickBillingDecision.persist:
          return await session.saveReady();
        case QuickBillingDecision.confirm:
        case QuickBillingDecision.clarify:
          return await clarify(session);
      }
    } finally {
      await session.dispose();
    }
  }
}
