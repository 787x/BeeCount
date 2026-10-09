import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:beecount/ai/providers/ai_provider_factory.dart';
import 'package:beecount/ai/providers/ai_provider_config.dart';

class _Adapter implements HttpClientAdapter {
  Map<String, dynamic>? payload;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    payload = options.data as Map<String, dynamic>;
    return ResponseBody.fromString(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'ok'}
            }
          ]
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  for (final assistant in [false, true]) {
    test(
        'joint request order, MIME and ${assistant ? 'Assistant' : 'Quick'} Thinking',
        () async {
      final dir = await Directory.systemTemp.createTemp('vision-test-');
      try {
        final png = await File('${dir.path}/1.png')
            .writeAsBytes([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
        final jpg =
            await File('${dir.path}/2.jpg').writeAsBytes([0xff, 0xd8, 0xff]);
        final adapter = _Adapter();
        final dio = Dio()..httpClientAdapter = adapter;
        final config = AIServiceProviderConfig.xiaomiDefault
            .copyWith(thinkingEnabled: false, assistantThinkingEnabled: true);
        expect(
            await AIProviderFactory.visionManyForConfig(
                config, [png, jpg], 'joint',
                assistant: assistant, client: dio),
            'ok');
        final content =
            (adapter.payload!['messages'] as List).single['content'] as List;
        expect(content, hasLength(3));
        expect(content.first, {'type': 'text', 'text': 'joint'});
        expect(content[1]['image_url']['url'],
            startsWith('data:image/png;base64,'));
        expect(content[2]['image_url']['url'],
            startsWith('data:image/jpeg;base64,'));
        expect(adapter.payload!['thinking'],
            {'type': assistant ? 'enabled' : 'disabled'});
      } finally {
        await dir.delete(recursive: true);
      }
    });
  }
  test('unsupported adapter never silently drops extra images', () async {
    expect(
        () => AIProviderFactory.visionManyForConfig(
            AIServiceProviderConfig.zhipuDefault,
            [File('A'), File('B')],
            'joint'),
        throwsA(isA<AIException>()));
  });
}
