import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../ai/core/bill_info.dart';
import '../../ai/providers/ai_provider_factory.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/ai_chat_providers.dart';
import '../../services/ai/billing_draft_session.dart';
import '../../services/ai/billing_image_service.dart';
import '../../services/attachment_service.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/tag_seed_service.dart';
import '../../widgets/ai/ai_privacy_consent_dialog.dart';
import '../../widgets/ai/speech_input_button.dart';

class BillingDraftPage extends ConsumerStatefulWidget {
  final ImageSource source;
  const BillingDraftPage({super.key, required this.source});
  @override
  ConsumerState<BillingDraftPage> createState() => _BillingDraftPageState();
}

class _BillingDraftPageState extends ConsumerState<BillingDraftPage> {
  final _reply = TextEditingController();
  final _imageService = BillingImageService();
  BillingDraftSession? _session;
  DateTime _fallbackTime = DateTime.now();
  String _currency = '';
  bool _busy = true;
  bool _editing = false;
  String? _error;
  String? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      if (!await ensureAiPrivacyConsent(context, ref) || !mounted) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final ledger = await ref.read(currentLedgerProvider.future);
      if (!mounted) return;
      if (ledger == null) {
        throw StateError(AppLocalizations.of(context).aiOcrNoLedger);
      }
      _currency = ledger.currency;
      final bookkeeper = ref.read(aiBookkeeperProvider);
      final attachments = ref.read(attachmentServiceProvider);
      final l10n = AppLocalizations.of(context);
      _session = BillingDraftSession(
          analyze: (images, replies, previous) => bookkeeper.analyzeImages(
              images: images.map((i) => i.recognition).toList(),
              ledgerId: ledger.id,
              replies: replies,
              previous: previous),
          persist: (drafts, images) async {
            final autoAttachment = ref.read(smartBillingAutoAttachmentProvider);
            final result = await bookkeeper.persistDrafts(
                drafts: drafts,
                sourceImages: images.map((i) => i.attachment).toList(),
                fallbackTime: _fallbackTime,
                ledgerId: ledger.id,
                billingTypes: [
                  widget.source == ImageSource.gallery
                      ? TagSeedService.billingTypeImage
                      : TagSeedService.billingTypeCamera,
                  TagSeedService.billingTypeAi
                ],
                l10n: l10n,
                saveAttachment: autoAttachment
                    ? (txId, source, index) => attachments.saveAttachment(
                        transactionId: txId, sourceFile: source, index: index)
                    : null);
            if (result.success && mounted) {
              await PostProcessor.run(ref,
                  ledgerId: ledger.id, tags: true, attachments: autoAttachment);
            }
            return result;
          });
      await _addImages(widget.source);
      if (mounted &&
          _session!.images.isEmpty &&
          _session!.analysis == null &&
          _error == null) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AIProviderFactory.userFacingError(error);
        });
      }
    }
  }

  Future<void> _addImages(ImageSource source) async {
    if (!mounted) return;
    setState(() => _busy = true);
    final prepared = <BillingImageFiles>[];
    try {
      final keepOriginal =
          await ref.read(attachmentKeepOriginalProvider.future);
      final files = source == ImageSource.gallery
          ? await _imageService.pickImages(keepOriginal: keepOriginal)
          : [await _imageService.pickImage(source, keepOriginal: keepOriginal)]
              .whereType<File>()
              .toList();
      for (final file in files) {
        prepared
            .add(await _imageService.prepare(file, keepOriginal: keepOriginal));
      }
      if (!mounted) {
        for (final image in prepared) {
          await image.dispose();
        }
        return;
      }
      if (prepared.isNotEmpty) {
        await _session!.update(images: prepared);
        _fallbackTime = DateTime.now();
        _editing = false;
      }
    } catch (error) {
      for (final image in prepared) {
        await image.dispose();
      }
      if (mounted) {
        _error = error.toString().contains('multi_image_unsupported')
            ? AppLocalizations.of(context).aiImagesUnsupported
            : AppLocalizations.of(context).aiImageProcessingFailed;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reanalyze() async {
    if (_busy || _reply.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _session!.update(reply: _reply.text);
      _reply.clear();
      _fallbackTime = DateTime.now();
      _editing = false;
    } catch (_) {
      if (!mounted) return;
      _error = AppLocalizations.of(context).aiImageProcessingFailed;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _session!.confirm();
      if (!mounted || result == null) return;
      final l10n = AppLocalizations.of(context);
      _result = l10n.aiDraftSaved(result.savedCount, result.failedCount);
      if (result.unconvertedCurrencies.isNotEmpty) {
        _result =
            '$_result\n${l10n.aiBillingRateMissingHint(result.unconvertedCurrencies.join(', '))}';
      }
    } catch (_) {
      _error = AppLocalizations.of(context).aiOcrCheckLog;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_session?.dispose());
    _reply.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = _session;
    final ready = session?.state == BillingDraftState.ready;
    final done = session?.state == BillingDraftState.done;
    final input = !_busy && !done && session != null && (!ready || _editing);
    return PopScope(
        canPop: session?.state != BillingDraftState.saving,
        child: Scaffold(
            appBar: AppBar(title: Text(l10n.aiDraftTitle)),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 16),
                Text(session?.state == BillingDraftState.saving
                    ? l10n.aiDraftSaving
                    : l10n.aiDraftAnalyzing)
              ],
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_result != null) Text(_result!),
              if (session != null && !done)
                Text(l10n.aiImageCount(session.images.length)),
              for (final draft in session?.analysis?.drafts ?? [])
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
                          '${draft.bill.amount?.abs().toStringAsFixed(2) ?? '?'} ${draft.bill.currency ?? _currency}',
                          '${draft.bill.time ?? _fallbackTime}',
                          draft.bill.note ?? '',
                          draft.bill.category ?? '',
                          draft.bill.account ?? '',
                          if (draft.bill.type == BillType.transfer)
                            '${draft.bill.fromAccount ?? '?'} → ${draft.bill.toAccount ?? '?'}',
                          if (!done)
                            l10n.aiImageCount(draft
                                .attachmentIndexes(session!.images.length)
                                .length),
                        ].where((s) => s.isNotEmpty).join('\n')))),
              if (input) ...[
                Text(session.analysis?.question ?? l10n.aiDraftNeedsInput),
                Row(children: [
                  SpeechInputButton(controller: _reply, enabled: !_busy),
                  Expanded(
                      child: TextField(
                          controller: _reply,
                          decoration:
                              InputDecoration(hintText: l10n.aiDraftReply))),
                  IconButton(
                      onPressed: _reanalyze, icon: const Icon(Icons.send))
                ]),
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
              if (ready && !_busy && !_editing) ...[
                FilledButton(
                    onPressed: _confirm, child: Text(l10n.aiDraftConfirm)),
                TextButton(
                    onPressed: () => setState(() => _editing = true),
                    child: Text(l10n.aiDraftModify)),
              ],
              if (session?.state != BillingDraftState.saving)
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(done ? l10n.commonFinish : l10n.commonCancel)),
            ])));
  }
}
