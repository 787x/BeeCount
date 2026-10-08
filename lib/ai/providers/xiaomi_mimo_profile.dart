import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// MiMo 按量 API 的 endpoint、请求差异和模型选择规则。
abstract final class XiaomiMiMoProfile {
  static const providerId = 'xiaomi_mimo';
  static const baseUrl = 'https://api.xiaomimimo.com/v1';
  static const generationModel = 'mimo-v2.6-flash';
  static const asrModel = 'mimo-v2.5-asr';

  /// Base64 音频上限为 10 MB（十进制字节数，不含 data URL 前缀）。
  static const maxAsrBase64Bytes = 10 * 1000 * 1000;

  /// 编码前按包含 padding 的 Base64 长度校验，避免为大小检查分配字符串。
  static void validateAsrSize(int rawBytes) {
    if (((rawBytes + 2) ~/ 3) * 4 > maxAsrBase64Bytes) {
      throw const XiaomiMiMoAudioTooLargeException();
    }
  }

  static Map<String, Object?> generationParameters(bool thinkingEnabled,
          {double? temperature}) =>
      {
        'thinking': {'type': thinkingEnabled ? 'enabled' : 'disabled'},
        if (!thinkingEnabled && temperature != null) 'temperature': temperature,
      };

  static Future<XiaomiMiMoModels> discover(String apiKey, {Dio? client}) async {
    final dio = client ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
        ));
    try {
      final response = await dio.get<dynamic>('$baseUrl/models',
          options: Options(headers: {'Authorization': 'Bearer $apiKey'}));
      final data = response.data;
      if (data is! Map || data['data'] is! List) {
        throw const FormatException('Invalid model list');
      }
      return XiaomiMiMoModels([
        for (final model in data['data'] as List)
          if (model is Map &&
              model['id'] is String &&
              (model['id'] as String).isNotEmpty)
            model['id'] as String,
      ]);
    } on DioException catch (error) {
      // Do not surface request options, credentials or arbitrary server bodies.
      throw XiaomiMiMoModelLoadException(error.response?.statusCode == 401 ||
          error.response?.statusCode == 403);
    }
  }

  static Future<Map<String, Object?>> asrPayload(
      String model, File audio) async {
    final extension = audio.path.toLowerCase().split('.').last;
    final mime = switch (extension) {
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      _ => throw const FormatException('MiMo ASR supports WAV / MP3'),
    };
    validateAsrSize(await audio.length());
    final bytes = await audio.readAsBytes();
    // 文件可能在 length 与读取之间增长；编码前再次验证实际读取的字节。
    validateAsrSize(bytes.length);
    return {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {
                'data': 'data:$mime;base64,${base64Encode(bytes)}',
              }
            },
          ],
        },
      ],
      'asr_options': {'language': 'auto'},
    };
  }
}

final class XiaomiMiMoAudioTooLargeException implements Exception {
  const XiaomiMiMoAudioTooLargeException();

  @override
  String toString() => '音频过长或过大，超过 MiMo ASR 10 MB 限制';
}

final class XiaomiMiMoModelLoadException implements Exception {
  const XiaomiMiMoModelLoadException(this.unauthorized);
  final bool unauthorized;
}

/// Identity-only discovery uses provider-local classification. New generation
/// IDs remain selectable without a client update; TTS is never offered as ASR.
final class XiaomiMiMoModels {
  XiaomiMiMoModels(List<String> ids) : ids = List.unmodifiable(ids.toSet());
  final List<String> ids;
  List<String> get generation => ids
      .where((id) =>
          !id.toLowerCase().contains('asr') &&
          !id.toLowerCase().contains('tts'))
      .toList();
  List<String> get speech => ids
      .where((id) =>
          id.toLowerCase().contains('asr') && !id.toLowerCase().contains('tts'))
      .toList();

  static String select(List<String> available, String saved, String preferred) {
    if (available.contains(saved)) return saved;
    if (available.contains(preferred)) return preferred;
    return available.isEmpty ? '' : available.first;
  }
}
