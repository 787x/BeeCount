import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../pages/ai/billing_draft_page.dart';

/// All manual image entry points share one ephemeral confirmation flow.
class ImageBillingHelper {
  static Future<void> pickImageForBilling(
          BuildContext context, WidgetRef ref) =>
      _open(context, ImageSource.gallery);
  static Future<void> openCameraForBilling(
          BuildContext context, WidgetRef ref) =>
      _open(context, ImageSource.camera);
  static Future<void> _open(BuildContext context, ImageSource source) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => BillingDraftPage(source: source)));
  }
}
