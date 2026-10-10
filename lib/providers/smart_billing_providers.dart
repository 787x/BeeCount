import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai/quick_billing_policy.dart';

class QuickBillingPolicyNotifier
    extends AsyncNotifier<QuickBillingResultPolicy> {
  static const preferenceKey = 'quickBillingResultPolicy.v1';
  @override
  Future<QuickBillingResultPolicy> build() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = prefs.getString(preferenceKey);
      if (saved != null) {
        final json = jsonDecode(saved);
        if (json is Map<String, dynamic>) {
          return QuickBillingResultPolicy.fromJson(json);
        }
      }
    } catch (_) {
      // Corrupt settings never change the defaults or block quick billing.
    }
    return const QuickBillingResultPolicy();
  }

  Future<void> setPolicy(QuickBillingResultPolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(preferenceKey, jsonEncode(policy.toJson()))) {
      throw StateError('Policy persistence failed');
    }
    state = AsyncData(policy);
  }
}

final quickBillingPolicyProvider =
    AsyncNotifierProvider<QuickBillingPolicyNotifier, QuickBillingResultPolicy>(
        QuickBillingPolicyNotifier.new);

/// 智能记账自动关联标签开关（默认开启）
final smartBillingAutoTagsProvider = StateProvider<bool>((ref) => true);

/// 智能记账自动添加附件开关（默认开启）
final smartBillingAutoAttachmentProvider = StateProvider<bool>((ref) => true);

/// 智能记账自动关联标签持久化初始化
final smartBillingAutoTagsInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoTags');
  if (saved != null) {
    ref.read(smartBillingAutoTagsProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoTagsProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoTags', next);
  });
});

/// 智能记账自动添加附件持久化初始化
final smartBillingAutoAttachmentInitProvider =
    FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getBool('smartBillingAutoAttachment');
  if (saved != null) {
    ref.read(smartBillingAutoAttachmentProvider.notifier).state = saved;
  }
  ref.listen<bool>(smartBillingAutoAttachmentProvider, (prev, next) async {
    await prefs.setBool('smartBillingAutoAttachment', next);
  });
});
