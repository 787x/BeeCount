import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/services/ai/assistant_image_service.dart';
import 'package:beecount/services/ai/billing_image_service.dart';

class _Images extends BillingImageService {
  final Directory parent;
  final directories = <Directory>[];
  _Images(this.parent);
  @override
  Future<BillingImageFiles> prepare(File file,
      {required bool keepOriginal}) async {
    expect(keepOriginal, true);
    final dir = await parent.createTemp('recognition-');
    directories.add(dir);
    final copy = await file.copy('${dir.path}/image.jpg');
    return BillingImageFiles(file, copy, dir);
  }
}

void main() {
  for (final fail in [false, true]) {
    test(
        'assistant preprocessing cleans recognition resources on ${fail ? 'failure' : 'success'}',
        () async {
      final parent = await Directory.systemTemp.createTemp('assistant-test-');
      try {
        final files = [
          await File('${parent.path}/A').writeAsString('A'),
          await File('${parent.path}/B').writeAsString('B')
        ];
        final images = _Images(parent);
        var calls = 0;
        final service = AssistantImageService(
            images: images,
            vision: (copies, prompt) async {
              calls++;
              expect(copies, hasLength(2));
              expect(await copies.first.readAsString(), 'A');
              expect(await copies.last.readAsString(), 'B');
              if (fail) throw StateError('offline');
              return 'factual context';
            });
        if (fail) {
          await expectLater(service.describe(files, ''), throwsStateError);
        } else {
          final metadata = await service.describe(files, '');
          expect(metadata.imageOnly, true);
          expect(metadata.imageCount, 2);
          expect(metadata.toJson().containsKey('images'), false);
        }
        expect(calls, 1);
        for (final dir in images.directories) {
          expect(await dir.exists(), false);
        }
        for (final file in files) {
          expect(await file.exists(), true);
        }
      } finally {
        await parent.delete(recursive: true);
      }
    });
  }
}
