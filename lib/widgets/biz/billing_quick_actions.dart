import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/platform/app_link_service.dart';

/// The same actions are dispatched through the existing app-link handlers.
class BillingQuickActions extends StatelessWidget {
  const BillingQuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
          title: Text(l10n.billingQuickActions),
          trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop())),
      for (final item in [
        (
          AppLinkAction.newTransaction,
          Icons.edit_note,
          l10n.billingManualAction
        ),
        (AppLinkAction.camera, Icons.camera_alt_rounded, l10n.fabActionCamera),
        (
          AppLinkAction.image,
          Icons.photo_library_rounded,
          l10n.fabActionGallery
        ),
        (AppLinkAction.voice, Icons.mic_rounded, l10n.fabActionVoice),
      ])
        ListTile(
            leading: Icon(item.$2),
            title: Text(item.$3),
            onTap: () => Navigator.of(context).pop(item.$1)),
    ]));
  }
}
