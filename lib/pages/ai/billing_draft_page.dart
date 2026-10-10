import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../ai/core/bill_info.dart';
import '../../ai/providers/ai_provider_factory.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/ai/billing_draft_session.dart';
import '../../services/ai/billing_image_service.dart';
import '../../services/ai/bookkeeping_result.dart';
import '../../services/ai/quick_billing_policy.dart';
import '../../widgets/ai/speech_input_button.dart';

/// Borrows a quick billing session for clarification or confirmation.
/// Route disposal cancels the session; the flow awaits the same cleanup task.
class BillingDraftPage extends ConsumerStatefulWidget {
  final BillingDraftSession session;
  final String currency;
  const BillingDraftPage(
      {super.key, required this.session, required this.currency});
  @override
  ConsumerState<BillingDraftPage> createState() => _BillingDraftPageState();
}

class _BillingDraftPageState extends ConsumerState<BillingDraftPage> {
  final _reply = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _update(
      {String? reply, List<BillingImageFiles> images = const []}) async {
    try {
      await widget.session.update(reply: reply, images: images);
      if (!mounted) return;
      _reply.clear();
      if (widget.session.decision == QuickBillingDecision.persist) {
        final result = await widget.session.saveReady();
        if (mounted && result != null) Navigator.pop(context, result);
      } else if (widget.session.decision == QuickBillingDecision.notify) {
        Navigator.pop(context, BookkeepingResult.empty);
      }
    } catch (error) {
      if (mounted) {
        _error = imageBillingError(AppLocalizations.of(context), error);
      }
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.session.saveReady();
      if (mounted && result != null) Navigator.pop(context, result);
    } catch (error) {
      if (mounted) {
        _error = imageBillingError(AppLocalizations.of(context), error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reanalyze({bool retry = false}) async {
    if (_busy || (!retry && _reply.text.trim().isEmpty)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _update(reply: retry ? null : _reply.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addImages(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final prepared = <BillingImageFiles>[];
    var handedOff = false;
    try {
      final imageService = ref.read(billingImageServiceProvider);
      final keepOriginal =
          await ref.read(attachmentKeepOriginalProvider.future);
      final files = source == ImageSource.gallery
          ? await imageService.pickImages(keepOriginal: keepOriginal)
          : [await imageService.pickImage(source, keepOriginal: keepOriginal)]
              .whereType<File>()
              .toList();
      for (final file in files) {
        prepared
            .add(await imageService.prepare(file, keepOriginal: keepOriginal));
      }
      if (!mounted || prepared.isEmpty) return;
      handedOff = true;
      await _update(images: prepared);
    } catch (error) {
      if (mounted) {
        _error = imageBillingError(AppLocalizations.of(context), error);
      }
    } finally {
      if (!handedOff) {
        for (final image in prepared) {
          await image.dispose();
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(widget.session.dispose());
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = widget.session;
    final done = session.state == BillingDraftState.done;
    final confirming = session.decision == QuickBillingDecision.confirm;
    final question = session.analysis?.question?.trim() ?? '';
    return PopScope(
        canPop: session.state != BillingDraftState.saving,
        child: Scaffold(
            appBar: AppBar(
                title: Text(
                    confirming ? l10n.quickBillingReview : l10n.aiDraftTitle)),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(session.state == BillingDraftState.saving
                    ? l10n.aiDraftSaving
                    : session.allowImages
                        ? l10n.aiDraftAnalyzing
                        : l10n.quickBillingAnalyzing)
              ],
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (!done && session.allowImages)
                Text(l10n.aiImageCount(session.images.length)),
              for (final draft in session.analysis?.drafts ?? [])
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text([
                          draft.bill.type == BillType.income
                              ? l10n.aiTypeIncome
                              : draft.bill.type == BillType.expense
                                  ? l10n.aiTypeExpense
                                  : draft.bill.type == BillType.transfer
                                      ? l10n.transferTitle
                                      : l10n.aiDraftNeedsInput,
                          '${draft.bill.amount?.abs().toStringAsFixed(2) ?? '?'} ${draft.bill.currency ?? widget.currency}',
                          if (draft.bill.time != null) '${draft.bill.time}',
                          draft.bill.note ?? '',
                          draft.bill.category ?? '',
                          draft.bill.account ?? '',
                          if (draft.bill.type == BillType.transfer)
                            '${draft.bill.fromAccount ?? '?'} → ${draft.bill.toAccount ?? '?'}',
                          if (!done && session.allowImages)
                            l10n.aiImageCount(draft
                                .attachmentIndexes(session.images.length)
                                .length),
                        ].where((s) => s.isNotEmpty).join('\n')))),
              if (!_busy && !done && confirming)
                FilledButton(
                    key: const ValueKey('billing-draft-confirm'),
                    onPressed: _confirm,
                    child: Text(l10n.quickBillingConfirm)),
              if (session.decision == QuickBillingDecision.clarify &&
                  session.policy.needsInputAction ==
                      NeedsInputAction.saveBestEffort &&
                  session.analysis?.drafts.isNotEmpty == true)
                Text(l10n.quickBillingBestEffortFallback),
              if (!_busy && !done && !confirming) ...[
                Text(question.isNotEmpty
                    ? question
                    : (session.state == BillingDraftState.noBill
                        ? l10n.quickBillingNoBillPrompt
                        : l10n.aiDraftNeedsInput)),
                Row(children: [
                  SpeechInputButton(controller: _reply, enabled: !_busy),
                  Expanded(
                      child: TextField(
                          controller: _reply,
                          decoration:
                              InputDecoration(hintText: l10n.aiDraftReply))),
                  IconButton(
                      key: const ValueKey('billing-draft-send'),
                      onPressed: _reanalyze,
                      icon: const Icon(Icons.send))
                ]),
                if (_error != null)
                  TextButton(
                      key: const ValueKey('billing-draft-retry'),
                      onPressed: () => _reanalyze(retry: true),
                      child: Text(l10n.aiDraftRetry)),
                if (session.allowImages)
                  Wrap(children: [
                    TextButton.icon(
                        onPressed: () => _addImages(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(l10n.aiImagesAdd)),
                    TextButton.icon(
                        onPressed: () => _addImages(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(l10n.aiImagesCamera)),
                  ]),
              ],
              if (session.state != BillingDraftState.saving)
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel)),
            ])));
  }
}

/// Both paths retain the provider's existing safe user-facing error mapping.
String imageBillingError(AppLocalizations l10n, Object error) =>
    error.toString().contains('multi_image_unsupported')
        ? l10n.aiImagesUnsupported
        : l10n.aiOcrFailed(AIProviderFactory.userFacingError(error));
