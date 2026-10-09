import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import '../providers/ai_chat_providers.dart';
import '../providers/voice_billing_providers.dart';
import '../services/system/logger_service.dart';
import '../ai/providers/ai_provider_manager.dart';
import '../ai/providers/ai_provider_config.dart';
import '../widgets/ui/ui.dart';
import '../styles/tokens.dart';
import '../widgets/ai/android_speech_dialog.dart';
import '../widgets/ai/ai_privacy_consent_dialog.dart';

import '../services/ai/speech_recognition.dart';
import '../ai/providers/ai_provider_factory.dart';

typedef SpeechInputRequest = Future<String?> Function(BuildContext, WidgetRef);

/// Override this boundary in UI tests without requesting a real microphone.
final speechInputRequestProvider =
    Provider<SpeechInputRequest>((ref) => SpeechInputHelper.recognize);

/// Shared microphone permission and speech-to-text UI for billing and chat.
class SpeechInputHelper {
  static bool _active = false;
  static Future<String?> recognize(BuildContext context, WidgetRef ref) async {
    if (_active) return null;
    _active = true;
    final l10n = AppLocalizations.of(context);
    try {
      if (!await ensureAiPrivacyConsent(context, ref)) return null;
      if (!context.mounted) return null;
      await ref.read(speechRecognitionSettingsProvider.notifier).loaded;
      await ref.read(voiceBillingSettingsProvider.notifier).ensureLoaded();
      final mode = ref.read(speechRecognitionSettingsProvider);
      final bridge = AndroidSpeechRecognition();
      final availability =
          Platform.isAndroid && mode != SpeechRecognitionMode.cloud
              ? await bridge.availability()
              : (system: false, onDevice: false);
      if (!context.mounted) return null;
      var permissionGranted = false;
      final settings = ref.read(voiceBillingSettingsProvider);
      return await recognizeSpeech(
        mode: mode,
        onDeviceAvailable: availability.onDevice,
        systemAvailable: availability.system,
        cloudAvailable: () async {
          final provider = await AIProviderManager.getProviderForCapability(
              AICapabilityType.speech);
          return provider?.isValid == true && provider?.supportsSpeech == true;
        },
        listen: (engine) async {
          if (!context.mounted) return null;
          if (!permissionGranted) {
            if (!await _permission(context) || !context.mounted) return null;
            permissionGranted = true;
          }
          if (engine != SpeechEngine.cloud) {
            final locale = Localizations.localeOf(context);
            // Region-less app locales are not necessarily supported by the ROM's service.
            final language = locale.countryCode?.isNotEmpty == true
                ? locale.toLanguageTag()
                : '';
            final sessionBridge = AndroidSpeechRecognition();
            final result = await showDialog<Object?>(
                context: context,
                barrierDismissible: false,
                builder: (_) => AndroidSpeechDialog(
                    bridge: sessionBridge,
                    engine: engine,
                    language: language,
                    triggerMode: settings.triggerMode,
                    returnErrors: true));
            if (result is SpeechInputException) throw result;
            return result as String?;
          }
          final temp = await getTemporaryDirectory();
          if (!context.mounted) return null;
          final recorder = AudioRecorder();
          final audioPath =
              '${temp.path}/voice_${DateTime.now().microsecondsSinceEpoch}.wav';
          return showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (_) => _CloudRecordingDialog(
                  recorder: recorder,
                  audioPath: audioPath,
                  triggerMode: settings.triggerMode,
                  silenceTimeoutMs: settings.silenceTimeoutMs));
        },
      );
    } on SpeechInputException catch (error) {
      if (context.mounted && error.code != 'cancelled') {
        showToast(context, speechErrorMessage(l10n, error.code));
      }
    } catch (error) {
      if (context.mounted) {
        showToast(
            context,
            l10n.voiceRecordingRecognizeFailed(
                AIProviderFactory.userFacingError(error)));
      }
    } finally {
      _active = false;
    }
    return null;
  }

  static Future<bool> _permission(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    var status = await Permission.microphone.status;
    if (!context.mounted) return false;
    if (status.isPermanentlyDenied) {
      final open = await AppDialog.confirm<bool>(context,
          title: l10n.voiceRecordingPermissionDeniedTitle,
          message: l10n.voiceRecordingPermissionDeniedMessage,
          okLabel: l10n.commonGoSettings,
          cancelLabel: l10n.commonCancel);
      if (open == true) await openAppSettings();
      return false;
    }
    if (!status.isGranted && !status.isRestricted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted && context.mounted) {
      showToast(context, l10n.voiceRecordingPermissionDenied);
    }
    return status.isGranted;
  }
}

/// 语音录音对话框（私有）
class _CloudRecordingDialog extends ConsumerStatefulWidget {
  final String audioPath;
  final AudioRecorder recorder;

  /// 触发方式：自动检测停顿 / 按住说话
  final VoiceTriggerMode triggerMode;

  /// 自动检测模式下的静音判定阈值（毫秒）
  final int silenceTimeoutMs;

  const _CloudRecordingDialog({
    required this.audioPath,
    required this.recorder,
    required this.triggerMode,
    required this.silenceTimeoutMs,
  });

  @override
  ConsumerState<_CloudRecordingDialog> createState() =>
      _CloudRecordingDialogState();
}

class _CloudRecordingDialogState extends ConsumerState<_CloudRecordingDialog> {
  // 静音检测相关阈值（自动检测模式）。抽为常量便于统一调参。
  /// 起始静音判定（开场多少秒无语音则认为"没说话"）
  static const int _kStartSilenceTimeoutSec = 3;

  /// 最长录音时长上限（秒），防止静音检测失效导致永不停止
  static const int _kMaxRecordingSec = 60;

  /// 音量归一化阈值（约 -25dB），超过才计入"有声"
  static const double _kSoundThreshold = 0.58;

  /// 连续多少帧（每帧 100ms）有声才判定"开始说话"
  static const int _kConsecutiveSoundFrames = 5;

  /// 按住说话最短有效时长（毫秒），低于此值视为误触丢弃
  static const int _kMinHoldMs = 500;

  bool _isRecording = false;
  bool _isProcessing = false;
  String? _status;
  int _duration = 0;
  double _amplitude = 0.0;
  DateTime? _lastSoundTime;
  bool _hasSpoken = false;
  int _consecutiveSoundCount = 0;
  Timer? _silenceTimer;
  Timer? _amplitudeTimer;

  /// 按住说话：是否正在长按录音
  bool _isHolding = false;

  /// 按住说话：录音是否正在启动中（recorder.start 在途）。
  /// 用于守卫快速「按-松-按」时对同一 recorder 并发调用 start()。
  bool _isStarting = false;

  /// 本次录音开始时间（用于按住说话的最短时长判定）
  DateTime? _recordStartTime;

  bool get _isHoldToTalk => widget.triggerMode == VoiceTriggerMode.holdToTalk;

  @override
  void initState() {
    super.initState();
    // 自动检测模式：弹窗打开即录音。按住说话模式：等待用户长按再录。
    if (!_isHoldToTalk) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRecording();
      });
    }
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _amplitudeTimer?.cancel();
    unawaited(_disposeRecorder());
    super.dispose();
  }

  Future<void> _disposeRecorder() async {
    try {
      await widget.recorder.dispose();
    } catch (_) {}
    try {
      await File(widget.audioPath).delete();
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    try {
      await widget.recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
        ),
        path: widget.audioPath,
      );

      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _isRecording = true;
        _status = l10n.voiceRecordingInProgress;
        _lastSoundTime = now;
        _recordStartTime = now;
      });

      _startTimer();
      _startAmplitudeMonitoring();
      // 仅自动检测模式跑静音检测；按住说话靠松手结束，不做自动截断。
      if (!_isHoldToTalk) {
        _startSilenceDetection();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isHolding = false;
        _status = l10n.speechRecognitionFailed;
      });
      // 按住说话分支 UI 不渲染 _status,启动失败时直接 toast 兜底,避免零反馈。
      if (_isHoldToTalk) {
        showToast(context, l10n.speechRecognitionFailed);
      }
    }
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isRecording || !mounted) return;
      setState(() => _duration++);
      // 最长录音保护(两模式共用)：静音检测只在自动模式跑,按住说话靠此处兜底,
      // 防止长按几分钟产出超大 WAV、上传超时。
      if (_duration >= _kMaxRecordingSec) {
        if (_hasSpoken || _isHoldToTalk) {
          _stopAndProcess();
        } else {
          final l10n = AppLocalizations.of(context);
          Navigator.of(context).pop();
          showToast(context, l10n.voiceRecordingNoSpeech);
        }
        return;
      }
      _startTimer();
    });
  }

  void _startAmplitudeMonitoring() {
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!mounted || !_isRecording) {
        timer.cancel();
        return;
      }

      try {
        final amplitude = await widget.recorder.getAmplitude();
        if (!mounted || !_isRecording) {
          timer.cancel();
          return;
        }

        final current = amplitude.current;
        final normalizedAmplitude = ((current + 60) / 60).clamp(0.0, 1.0);

        if (normalizedAmplitude > _kSoundThreshold) {
          _consecutiveSoundCount++;

          setState(() {
            _amplitude = normalizedAmplitude;
          });

          if (_consecutiveSoundCount >= _kConsecutiveSoundFrames) {
            _lastSoundTime = DateTime.now();
            if (!_hasSpoken) {
              setState(() {
                _hasSpoken = true;
              });
              logger.info('VoiceRecording', '检测到用户开始说话');
            }
          }
        } else {
          _consecutiveSoundCount = 0;
          setState(() {
            _amplitude = _amplitude * 0.7;
          });
        }
      } catch (e) {
        // 忽略错误
      }
    });
  }

  void _startSilenceDetection() {
    final startTime = DateTime.now();

    _silenceTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isRecording) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();

      // 注：最长录音上限已统一挪到 _startTimer(两模式共用),此处只管静音判定。

      if (!_hasSpoken) {
        if (now.difference(startTime).inSeconds >= _kStartSilenceTimeoutSec) {
          timer.cancel();
          if (mounted) {
            final l10n = AppLocalizations.of(context);
            Navigator.of(context).pop();
            showToast(context, l10n.voiceRecordingNoSpeech);
          }
        }
      } else {
        final lastSound = _lastSoundTime;
        if (lastSound != null &&
            now.difference(lastSound).inMilliseconds >=
                widget.silenceTimeoutMs) {
          timer.cancel();
          _stopAndProcess();
        }
      }
    });
  }

  /// 按住说话：长按开始录音
  Future<void> _onHoldStart() async {
    // 守卫覆盖「启动中」窗口：快速 按-松-按 时,第二次按下若仅看 _isRecording/
    // _isProcessing 均为 false 会放行,对同一 recorder 并发调 start()。
    if (_isRecording || _isProcessing || _isStarting) return;
    _isStarting = true;
    setState(() => _isHolding = true);
    try {
      await _startRecording();
    } finally {
      _isStarting = false;
    }
    // 竞态修复：录音已启动但启动期间用户已松手，丢弃 orphan 录音。
    // 限定 _isRecording，避免启动失败(catch 已 toast)时再叠一条"过短"提示。
    if (!_isHolding && _isRecording) {
      await _discardRecording();
      // 与正常 <500ms 路径体验一致：丢弃时提示录音过短。
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showToast(context, l10n.voiceRecordingTooShort);
      }
    }
  }

  /// 按住说话：松手结束。录音过短视为误触丢弃，否则送识别。
  Future<void> _onHoldEnd() async {
    if (!_isHolding) return;
    setState(() => _isHolding = false);
    if (!_isRecording) return;

    final start = _recordStartTime;
    final tooShort = start != null &&
        DateTime.now().difference(start).inMilliseconds < _kMinHoldMs;
    if (tooShort) {
      await _discardRecording();
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        showToast(context, l10n.voiceRecordingTooShort);
      }
      return;
    }
    await _stopAndProcess();
  }

  /// 丢弃当前录音（不送识别），用于按住说话误触场景。
  Future<void> _discardRecording() async {
    _silenceTimer?.cancel();
    _amplitudeTimer?.cancel();
    // mounted 保护：按下→松手→取消三步都发生在 recorder.start() 在途窗口内时,
    // State 可能已 dispose,此处对已卸载的 State 调 setState 会崩溃。
    if (!mounted) {
      _isRecording = false;
      _hasSpoken = false;
      _duration = 0;
    } else {
      setState(() {
        _isRecording = false;
        _hasSpoken = false;
        _duration = 0;
      });
    }
    try {
      await widget.recorder.stop();
    } catch (_) {}
    try {
      await File(widget.audioPath).delete();
    } catch (_) {}
  }

  Future<void> _stopAndProcess() async {
    if (!_isRecording) return;

    final l10n = AppLocalizations.of(context);
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _status = l10n.voiceRecordingProcessing;
    });

    try {
      await widget.recorder.stop();

      final audioFile = File(widget.audioPath);
      final text = await ref.read(aiBookkeeperProvider).speechToText(audioFile);
      if (!mounted) return;
      if (text == null || text.trim().isEmpty) {
        showToast(context, l10n.voiceRecordingNoSpeech);
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pop(text.trim());
      }
    } catch (e) {
      if (!mounted) return;
      showToast(
          context,
          l10n.voiceRecordingRecognizeFailed(
              AIProviderFactory.userFacingError(e)));
      Navigator.of(context).pop();
    } finally {
      try {
        await File(widget.audioPath).delete();
      } catch (_) {}
    }
  }

  /// 录音振幅可视化圆形（自动检测与按住说话共用）。
  Widget _buildAmplitudeCircle() {
    final primaryColor = ref.watch(primaryColorProvider);
    return SizedBox(
      height: 80,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 60 + (_amplitude * 40),
          height: 60 + (_amplitude * 40),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primaryColor.withValues(alpha: 0.3),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.5),
                blurRadius: 10 + (_amplitude * 20),
                spreadRadius: _amplitude * 10,
              ),
            ],
          ),
          child: Center(
            child: Icon(Icons.mic, size: 30, color: primaryColor),
          ),
        ),
      ),
    );
  }

  /// 自动检测模式录音中 UI。
  List<Widget> _buildAutoRecordingContent(AppLocalizations l10n) {
    return [
      _buildAmplitudeCircle(),
      const SizedBox(height: 16),
      Text(
        _hasSpoken
            ? l10n.voiceRecordingAutoHintSpoken
            : l10n.voiceRecordingAutoHintWaiting,
        style: TextStyle(
          fontSize: 14,
          color: _hasSpoken
              ? ref.watch(primaryColorProvider)
              : BeeTokens.textSecondary(context),
          fontWeight: _hasSpoken ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.voiceRecordingDuration(_duration),
        style: TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context)),
      ),
    ];
  }

  /// 按住说话模式 UI（长按按钮 + 提示）。
  List<Widget> _buildHoldToTalkContent(AppLocalizations l10n) {
    final primaryColor = ref.watch(primaryColorProvider);
    return [
      if (_isRecording) ...[
        _buildAmplitudeCircle(),
        const SizedBox(height: 8),
        Text(
          l10n.voiceRecordingDuration(_duration),
          style:
              TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context)),
        ),
        const SizedBox(height: 16),
      ] else
        const SizedBox(height: 8),
      // 用 Listener 监听原始指针按下/抬起，比 LongPress 手势更适合"按住说话"。
      Listener(
        onPointerDown: (_) => _onHoldStart(),
        onPointerUp: (_) => _onHoldEnd(),
        onPointerCancel: (_) => _onHoldEnd(),
        child: Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isHolding
                ? primaryColor
                : primaryColor.withValues(alpha: 0.15),
          ),
          child: Icon(
            Icons.mic,
            size: 40,
            color: _isHolding ? BeeTokens.textOnPrimary(context) : primaryColor,
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        _isRecording
            ? l10n.voiceRecordingReleaseToFinish
            : l10n.voiceRecordingHoldToTalk,
        style: TextStyle(
          fontSize: 14,
          color: _isRecording ? primaryColor : BeeTokens.textSecondary(context),
          fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.voiceRecordingTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isProcessing) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status ?? l10n.voiceRecordingProcessing),
          ] else if (_isHoldToTalk) ...[
            ..._buildHoldToTalkContent(l10n),
          ] else if (_isRecording) ...[
            ..._buildAutoRecordingContent(l10n),
          ] else ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status ?? l10n.voiceRecordingPreparing),
          ],
        ],
      ),
      actions: [
        // 自动检测模式提供「完成」按钮手动结束；按住说话靠松手结束，不需要。
        if (_isRecording && !_isHoldToTalk)
          TextButton(
            onPressed: _stopAndProcess,
            child: Text(l10n.commonFinish),
          ),
        if (!_isProcessing)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
      ],
    );
  }
}
