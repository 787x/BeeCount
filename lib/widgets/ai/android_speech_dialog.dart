import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/voice_billing_providers.dart';
import '../../services/ai/speech_recognition.dart';
import '../ui/ui.dart';

String speechErrorMessage(AppLocalizations l10n, String code) => switch (code) {
      'on_device_unavailable' => l10n.speechOnDeviceUnavailable,
      'system_unavailable' => l10n.speechSystemUnavailable,
      'permission_denied' => l10n.voiceRecordingPermissionDenied,
      'no_match' => l10n.voiceRecordingNoSpeech,
      'busy' => l10n.speechBusy,
      'network' => l10n.speechNetworkError,
      'cloud_unavailable' => l10n.speechCloudUnavailable,
      'unavailable' => l10n.speechUnavailable,
      _ => l10n.speechRecognitionFailed,
    };

class AndroidSpeechDialog extends StatefulWidget {
  final AndroidSpeechRecognition bridge;
  final SpeechEngine engine;
  final String language;
  final VoiceTriggerMode triggerMode;
  const AndroidSpeechDialog(
      {super.key,
      required this.bridge,
      required this.engine,
      required this.language,
      required this.triggerMode});
  @override
  State<AndroidSpeechDialog> createState() => _AndroidSpeechDialogState();
}

class _AndroidSpeechDialogState extends State<AndroidSpeechDialog>
    with WidgetsBindingObserver {
  bool _started = false;
  bool _stopping = false;
  bool _finished = false;
  bool _cancelIssued = false;
  Timer? _timeout;
  bool get _hold => widget.triggerMode == VoiceTriggerMode.holdToTalk;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_hold) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && mounted) {
      unawaited(_cancel());
    }
  }

  Future<void> _start() async {
    if (_started || _finished || !mounted) return;
    setState(() => _started = true);
    _timeout = Timer(const Duration(seconds: 60), _stop);
    try {
      final text = await widget.bridge.start(widget.engine, widget.language);
      _complete(text);
    } on SpeechInputException catch (error) {
      if (!mounted || _finished) return;
      if (error.code != 'cancelled') {
        showToast(context,
            speechErrorMessage(AppLocalizations.of(context), error.code));
      }
      _complete();
    } catch (_) {
      if (!mounted || _finished) return;
      showToast(context, AppLocalizations.of(context).speechRecognitionFailed);
      _complete();
    }
  }

  void _complete([String? text]) {
    if (!mounted || _finished) return;
    _finished = true;
    _timeout?.cancel();
    Navigator.of(context).pop(text);
  }

  Future<void> _cancel() async {
    if (!mounted || _finished) return;
    _finished = true;
    _timeout?.cancel();
    _cancelIssued = true;
    try {
      await widget.bridge.cancel();
    } catch (_) {
      _cancelIssued = false;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stop() async {
    if (!_started || _stopping || _finished || !mounted) return;
    setState(() => _stopping = true);
    try {
      await widget.bridge.stop();
    } catch (_) {
      await _cancel();
      return;
    }
    _timeout?.cancel();
    if (!mounted || _finished) return;
    _timeout = Timer(const Duration(seconds: 10), () {
      unawaited(_cancel());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timeout?.cancel();
    if (!_cancelIssued) {
      unawaited(widget.bridge.cancel().catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.voiceRecordingTitle),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_hold)
              Listener(
                  onPointerDown: (_) => _start(),
                  onPointerUp: (_) => _stop(),
                  onPointerCancel: (_) => _stop(),
                  child: const Padding(
                      padding: EdgeInsets.all(24),
                      child: Icon(Icons.mic, size: 48)))
            else
              const Icon(Icons.mic, size: 48),
            Text(_stopping
                ? l10n.voiceRecordingProcessing
                : _hold && !_started
                    ? l10n.voiceRecordingHoldToTalk
                    : l10n.speechListening),
          ]),
          actions: [
            if (_started && !_hold && !_stopping)
              TextButton(onPressed: _stop, child: Text(l10n.commonFinish)),
            TextButton(onPressed: _cancel, child: Text(l10n.commonCancel)),
          ],
        ));
  }
}
