import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/core/bill_info.dart';
import '../l10n/app_localizations.dart';
import '../pages/ai/billing_draft_page.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../services/ai/billing_draft_session.dart';
import '../services/ai/billing_image_service.dart';
import '../services/ai/bookkeeping_result.dart';
import '../services/ai/image_billing_flow.dart';
import '../services/attachment_service.dart';
import '../services/billing/post_processor.dart';
import '../services/data/tag_seed_service.dart';
import '../services/system/logger_service.dart';
import '../widgets/ai/ai_privacy_consent_dialog.dart';
import '../widgets/ui/ui.dart';

/// Manual images are analyzed before navigation; only ambiguity opens a page.
class ImageBillingHelper {
  static bool _active = false;
  static Future<void> pickImageForBilling(
          BuildContext context, WidgetRef ref) =>
      _open(context, ref, ImageSource.gallery);
  static Future<void> openCameraForBilling(
          BuildContext context, WidgetRef ref) =>
      _open(context, ref, ImageSource.camera);

  static Future<void> _open(
      BuildContext context, WidgetRef ref, ImageSource source) async {
    if (_active) return;
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final imageService = container.read(billingImageServiceProvider);
    final prepared = <BillingImageFiles>[];
    var handedOff = false;
    DialogRoute<void>? loading;
    void hideLoading() {
      final route = loading;
      loading = null;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    }

    _active = true;
    try {
      final keepOriginal =
          await container.read(attachmentKeepOriginalProvider.future);
      if (!context.mounted) return;
      final files = source == ImageSource.gallery
          ? await imageService.pickImages(keepOriginal: keepOriginal)
          : [await imageService.pickImage(source, keepOriginal: keepOriginal)]
              .whereType<File>()
              .toList();
      if (!context.mounted || files.isEmpty) return;
      if (!await ensureAiPrivacyConsent(context, ref) || !context.mounted) {
        return;
      }
      loading = DialogRoute<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => PopScope(
              canPop: false,
              child: Center(
                  child: Card(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(l10n.aiDraftAnalyzing)
                            ],
                          ))))));
      unawaited(Navigator.of(context, rootNavigator: true).push(loading!));
      final ledger = await container.read(currentLedgerProvider.future);
      if (!context.mounted) return;
      if (ledger == null) {
        hideLoading();
        showToast(context, l10n.aiOcrNoLedger);
        return;
      }
      for (final file in files) {
        prepared
            .add(await imageService.prepare(file, keepOriginal: keepOriginal));
      }
      if (!context.mounted) return;
      final bookkeeper = container.read(aiBookkeeperProvider);
      final attachmentService = container.read(attachmentServiceProvider);
      final session = BillingDraftSession(
          analyze: (images, replies, previous) => bookkeeper.analyzeImages(
              images: images.map((i) => i.recognition).toList(),
              ledgerId: ledger.id,
              replies: replies,
              previous: previous),
          persist: (drafts, images) async {
            final autoAttachment =
                container.read(smartBillingAutoAttachmentProvider);
            final result = await bookkeeper.persistDrafts(
                drafts: drafts,
                sourceImages: images.map((i) => i.attachment).toList(),
                fallbackTime: DateTime.now(),
                ledgerId: ledger.id,
                billingTypes: [
                  source == ImageSource.gallery
                      ? TagSeedService.billingTypeImage
                      : TagSeedService.billingTypeCamera,
                  TagSeedService.billingTypeAi
                ],
                l10n: l10n,
                saveAttachment: autoAttachment
                    ? (txId, file, index) => attachmentService.saveAttachment(
                        transactionId: txId, sourceFile: file, index: index)
                    : null);
            if (result.success) {
              try {
                await PostProcessor.runC(container,
                    ledgerId: ledger.id,
                    tags: true,
                    attachments: autoAttachment);
              } catch (_) {
                // A refresh failure must not turn saved transactions into a retryable batch.
                logger.warning('ImageBilling', '交易已保存，后处理失败');
              }
            }
            return result;
          });
      // The flow is the sole session owner, including while the page borrows it.
      handedOff = true;
      final result = await ImageBillingFlow(session).run(
          images: prepared,
          isActive: () => context.mounted,
          clarify: (session) async {
            hideLoading();
            if (!context.mounted) return null;
            return Navigator.of(context).push<BookkeepingResult>(
                MaterialPageRoute(
                    settings: const RouteSettings(name: 'billing-clarification'),
                    builder: (_) => BillingDraftPage(
                        session: session, currency: ledger.currency)));
          });
      hideLoading();
      if (context.mounted && result != null) _showResult(context, l10n, result);
    } catch (error) {
      hideLoading();
      if (context.mounted) {
        showToast(context, imageBillingError(l10n, error));
      }
    } finally {
      try {
        hideLoading();
        if (!handedOff) {
          for (final image in prepared) {
            await image.dispose();
          }
        }
      } finally {
        _active = false;
      }
    }
  }

  static void _showResult(
      BuildContext context, AppLocalizations l10n, BookkeepingResult result) {
    if (!result.success) {
      showToast(
          context,
          result.failedCount > 0
              ? '${l10n.aiDraftSaved(0, result.failedCount)}\n${l10n.aiOcrCheckLog}'
              : l10n.aiOcrNoBill);
      return;
    }
    final type = result.firstBill!.type;
    final typeText = type == BillType.income
        ? l10n.aiTypeIncome
        : type == BillType.transfer
            ? l10n.transferTitle
            : l10n.aiTypeExpense;
    var message =
        l10n.aiOcrSuccess(typeText, result.totalAbsAmount.toStringAsFixed(2));
    if (result.isMulti) message = '$message × ${result.savedCount}';
    if (result.failedCount > 0) {
      message =
          '$message\n${l10n.aiDraftSaved(result.savedCount, result.failedCount)}';
    }
    if (result.unconvertedCurrencies.isNotEmpty) {
      message =
          '$message\n${l10n.aiBillingRateMissingHint(result.unconvertedCurrencies.join('、'))}';
    }
    showToast(context, message);
  }
}
