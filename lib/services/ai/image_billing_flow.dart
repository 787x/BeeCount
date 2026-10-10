import 'quick_billing_flow.dart';
import 'billing_draft_session.dart';
import 'billing_image_service.dart';
import 'bookkeeping_result.dart';

/// Makes the navigation decision before any clarification page is opened.
/// Owns the session throughout both paths and disposes it when the flow ends.
class ImageBillingFlow {
  final BillingDraftSession session;
  const ImageBillingFlow(this.session);

  Future<BookkeepingResult?> run({
    required List<BillingImageFiles> images,
    required Future<BookkeepingResult?> Function(BillingDraftSession) clarify,
    bool Function()? isActive,
  }) async {
    if (images.isEmpty) {
      await session.dispose();
      return null;
    }
    return QuickBillingFlow(session)
        .run(images: images, clarify: clarify, isActive: isActive);
  }
}
