import 'package:flutter_edge_ai/flutter_edge_ai.dart'
    show ModelType, PreferredBackend;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/data/repositories/chat_model/custom_chat_model_codec.dart';
import 'package:litert_hackathon/domain/models/chat_model.dart';

void main() {
  final sha = 'a1' * 32;
  final model = CustomChatModel(
    displayName: 'Gemma 3 1B NPU',
    source: UrlModelSource(
      Uri.parse('https://example.com/g3_ekv1280.litertlm'),
      sha256: sha,
      sizeBytes: 1234,
    ),
    file: CustomModelFile(
      name: 'g3_ekv1280.litertlm',
      sizeBytes: 1234,
      sha256: sha,
      checksumMatched: true,
    ),
    modelType: ModelType.gemmaIt,
    backend: PreferredBackend.npu,
    maxTokens: 1280,
    tools: true,
  );

  test('round-trips through its saved JSON', () {
    final back = CustomChatModelCodec.decode(
      CustomChatModelCodec.encode(model),
    );
    expect(back.displayName, model.displayName);
    expect(back.modelType, ModelType.gemmaIt);
    expect(back.backend, PreferredBackend.npu);
    expect(back.maxTokens, 1280);
    expect(back.supportImage, isFalse);
    expect(back.tools, isTrue);
    final source = back.source as UrlModelSource;
    expect(source.url, Uri.parse('https://example.com/g3_ekv1280.litertlm'));
    expect(source.sha256, sha);
    expect(source.sizeBytes, 1234);
    expect(back.file?.sha256, sha);
    expect(back.file?.checksumMatched, isTrue);
  });

  test('an imported model without a file yet round-trips too', () {
    const imported = CustomChatModel(
      displayName: 'mine',
      source: ImportedModelSource('/Users/me/Downloads/mine.litertlm'),
      backend: PreferredBackend.gpu,
      maxTokens: 4096,
    );
    final back = CustomChatModelCodec.decode(
      CustomChatModelCodec.encode(imported),
    );
    expect(
      (back.source as ImportedModelSource).pickedPath,
      '/Users/me/Downloads/mine.litertlm',
    );
    expect(back.file, isNull);
  });

  test('decoding is strict: every problem is named, nothing defaulted', () {
    void rejects(String json, String why) => expect(
      () => CustomChatModelCodec.decode(json),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains(why),
        ),
      ),
    );
    final good = CustomChatModelCodec.encode(model);
    rejects('{', 'not JSON');
    rejects(good.replaceFirst('"v":1', '"v":2'), 'version 2');
    rejects(good.replaceFirst('"backend":"npu"', '"backend":"tpu"'), 'backend');
    rejects(
      good.replaceFirst('"modelType":"gemmaIt"', '"modelType":"gemma9"'),
      'modelType',
    );
    rejects(
      good.replaceFirst('"maxTokens":1280', '"maxTokens":64'),
      'maxTokens',
    );
    rejects(good.replaceFirst('"tools":true', '"tools":"yes"'), 'bools');
    rejects(
      good.replaceFirst('"v":1', '"v":1,"extra":0'),
      'unknown key "extra"',
    );
    rejects(
      good.replaceFirst('"name":"g3_ekv1280.litertlm"', '"name":"../x"'),
      'file.name',
    );
  });
}
