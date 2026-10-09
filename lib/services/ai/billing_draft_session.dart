import '../../ai/core/billing_draft.dart';
import 'billing_image_service.dart';
import 'bookkeeping_result.dart';

enum BillingDraftState { analyzing, needsInput, ready, saving, done }

/// Ephemeral session. Only a reliable ready result can invoke the persister.
class BillingDraftSession {
  final List<BillingImageFiles> _images = [];
  final List<String> _replies = [];
  final Future<BillingDraftAnalysis> Function(
      List<BillingImageFiles>, List<String>, BillingDraftAnalysis?) analyze;
  final Future<BookkeepingResult> Function(
      List<BillingDraft>, List<BillingImageFiles>) persist;
  BillingDraftState state = BillingDraftState.needsInput;
  BillingDraftAnalysis? analysis;
  bool _disposed = false;
  Future<void>? _operation;
  Future<void>? _disposal;

  BillingDraftSession({required this.analyze, required this.persist});
  List<BillingImageFiles> get images => List.unmodifiable(_images);
  List<String> get replies => List.unmodifiable(_replies);

  Future<void> update(
      {List<BillingImageFiles> images = const [], String? reply}) async {
    if (_disposed ||
        state == BillingDraftState.done ||
        state == BillingDraftState.saving ||
        state == BillingDraftState.analyzing) {
      for (final image in images) {
        await image.dispose();
      }
      return;
    }
    _images.addAll(images);
    if (reply != null && reply.trim().isNotEmpty) _replies.add(reply.trim());
    state = BillingDraftState.analyzing;
    final work = _analyze();
    _operation = work;
    await work;
  }

  Future<void> _analyze() async {
    try {
      final next = await analyze(images, replies, analysis);
      if (_disposed) return;
      analysis = next;
      state = next.ready
          ? BillingDraftState.ready
          : next.drafts.isEmpty && !next.needsInput
              ? BillingDraftState.done
              : BillingDraftState.needsInput;
    } catch (_) {
      // The owner cleans terminal initial failures. A clarification retry
      // needs the same images, replies and last successful draft context.
      state = BillingDraftState.needsInput;
      rethrow;
    }
  }

  /// Starts persistence once; rebuilding or retrying cannot replay a saved batch.
  Future<BookkeepingResult?> saveReady() async {
    if (_disposed || state != BillingDraftState.ready) return null;
    state = BillingDraftState.saving;
    final work = _save();
    _operation = work.then((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }

  Future<BookkeepingResult> _save() async {
    try {
      return await persist(analysis!.drafts, images);
    } finally {
      // Even a late failure may follow a successful write. Never replay the batch.
      state = BillingDraftState.done;
      await _cleanup();
    }
  }

  Future<void> _cleanup() async {
    final images = List<BillingImageFiles>.of(_images);
    _images.clear();
    for (final image in images) {
      await image.dispose();
    }
  }

  /// Route disposal and the flow's finally block share one resource release.
  Future<void> dispose() {
    _disposed = true;
    return _disposal ??= _finishDisposal();
  }

  Future<void> _finishDisposal() async {
    final operation = _operation;
    if (operation != null) {
      try {
        await operation;
      } catch (_) {}
    }
    await _cleanup();
  }
}
