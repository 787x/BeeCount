import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/speech_input_helper.dart';

class SpeechInputButton extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  const SpeechInputButton(
      {super.key, required this.controller, required this.enabled});
  @override
  ConsumerState<SpeechInputButton> createState() => _SpeechInputButtonState();
}

class _SpeechInputButtonState extends ConsumerState<SpeechInputButton> {
  bool _busy = false;
  Future<void> _recognize() async {
    if (_busy || !widget.enabled) return;
    setState(() => _busy = true);
    try {
      final text = await ref.read(speechInputRequestProvider)(context, ref);
      if (!mounted || !widget.enabled || text == null || text.trim().isEmpty) {
        return;
      }
      final value = widget.controller.value;
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      final prefix = start > 0 && !RegExp(r'\s').hasMatch(value.text[start - 1])
          ? ' '
          : '';
      final suffix =
          end < value.text.length && !RegExp(r'\s').hasMatch(value.text[end])
              ? ' '
              : '';
      final insertion = '$prefix${text.trim()}$suffix';
      widget.controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, insertion),
        selection: TextSelection.collapsed(offset: start + insertion.length),
      );
    } catch (_) {
      // The shared flow already shows errors; fake/custom flows can fail safely.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('speech-input-mic'),
        tooltip: AppLocalizations.of(context).speechInputAction,
        icon: const Icon(Icons.mic_none_rounded),
        onPressed: widget.enabled && !_busy ? _recognize : null,
      );
}
