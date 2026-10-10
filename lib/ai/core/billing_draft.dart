import 'dart:convert';

import 'bill_info.dart';

/// Unsanitized extraction: missing values remain observable until confirmation.
class BillingDraft {
  final BillInfo bill;
  final List<int> sourceImageIndexes;
  final List<String> uncertainFields;

  const BillingDraft(this.bill,
      {this.sourceImageIndexes = const [], this.uncertainFields = const []});

  bool get blocked =>
      bill.amount == null ||
      !bill.amount!.isFinite ||
      bill.amount == 0 ||
      bill.type == null ||
      uncertainFields.isNotEmpty ||
      (bill.type == BillType.transfer &&
          (bill.fromAccount == null ||
              bill.fromAccount!.trim().isEmpty ||
              bill.toAccount == null ||
              bill.toAccount!.trim().isEmpty ||
              bill.fromAccount == bill.toAccount));

  BillInfo toBill(DateTime fallbackTime) {
    if (blocked) throw StateError('Draft needs clarification');
    return bill.copyWith(
      time: bill.time ?? fallbackTime,
      amount: bill.type == BillType.expense
          ? -bill.amount!.abs()
          : bill.amount!.abs(),
    );
  }

  /// Opt-in may accept uncertainty, never missing core values or invalid accounts.
  bool get canAcceptCandidate =>
      bill.amount != null &&
      bill.amount!.isFinite &&
      bill.amount != 0 &&
      bill.type != null &&
      !uncertainFields.contains('transfer_accounts') &&
      (bill.type != BillType.transfer ||
          (bill.fromAccount != null &&
              bill.fromAccount!.trim().isNotEmpty &&
              bill.toAccount != null &&
              bill.toAccount!.trim().isNotEmpty &&
              bill.fromAccount!.trim() != bill.toAccount!.trim()));

  /// Keeps strict conversion unchanged for all other callers.
  BillingDraft acceptCandidate() {
    if (!canAcceptCandidate) throw StateError('Unsafe draft candidate');
    return BillingDraft(bill, sourceImageIndexes: sourceImageIndexes);
  }

  List<int> attachmentIndexes(int imageCount) => sourceImageIndexes.isEmpty
      ? List.generate(imageCount, (index) => index)
      : sourceImageIndexes;

  Map<String, dynamic> toJson() => {
        ...bill.toJson(),
        'source_image_numbers': sourceImageIndexes.map((i) => i + 1).toList(),
        'uncertain_fields': uncertainFields,
      };
}

class BillingDraftAnalysis {
  final List<BillingDraft> drafts;
  final bool needsInput;
  final List<String> missingFields;
  final String? question;

  const BillingDraftAnalysis(
      {this.drafts = const [],
      this.needsInput = false,
      this.missingFields = const [],
      this.question});

  bool get ready =>
      drafts.isNotEmpty &&
      !needsInput &&
      missingFields.isEmpty &&
      drafts.every((draft) => !draft.blocked);

  /// This parser never invokes the legacy sanitizer or logs model output.
  factory BillingDraftAnalysis.parse(String response, int imageCount) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end < start) {
      throw const FormatException('Invalid draft envelope');
    }
    final data = jsonDecode(response.substring(start, end + 1));
    if (data is! Map ||
        data['drafts'] is! List ||
        data['needs_input'] is! bool) {
      throw const FormatException('Invalid draft envelope');
    }
    List<String> strings(dynamic value) => value is List
        ? value.whereType<String>().where((s) => s.trim().isNotEmpty).toList()
        : const [];
    final drafts = <BillingDraft>[];
    for (final item in data['drafts'] as List) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid draft');
      }
      final indexes = <int>{};
      final sources = item['source_image_numbers'];
      if (sources is List) {
        for (final number in sources) {
          if (number is int && number >= 1 && number <= imageCount) {
            indexes.add(number - 1);
          }
        }
      }
      final bill = BillInfo.fromJson(item);
      final uncertainty = strings(item['uncertain_fields']).toSet();
      // A present but unresolvable currency must not silently become the base currency.
      if (item['currency'] != null && bill.currency == null) {
        uncertainty.add('currency');
      }
      drafts.add(BillingDraft(bill,
          sourceImageIndexes: List.unmodifiable(indexes),
          uncertainFields: List.unmodifiable(uncertainty)));
    }
    return BillingDraftAnalysis(
        drafts: List.unmodifiable(drafts),
        needsInput: data['needs_input'] == true,
        missingFields: List.unmodifiable(strings(data['missing_fields'])),
        question:
            data['question'] is String ? data['question'] as String : null);
  }
}
