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
    try {
      if (images.isEmpty) return null;
      await session.update(images: images);
      if (!(isActive?.call() ?? true)) return null;
      if (session.state == BillingDraftState.ready) {
        return await session.saveReady();
      }
      final analysis = session.analysis;
      if (analysis == null) return null;
      if (analysis.drafts.isEmpty && !analysis.needsInput) {
        return BookkeepingResult.empty;
      }
      if (analysis.drafts.isEmpty &&
          (analysis.question?.trim().isEmpty ?? true)) {
        throw const FormatException('Missing clarification question');
      }
      return await clarify(session);
    } finally {
      await session.dispose();
    }
  }
}
