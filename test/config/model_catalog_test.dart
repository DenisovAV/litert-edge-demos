import 'package:flutter_edge_ai/flutter_edge_ai.dart' show ActivationDataType;
import 'package:flutter_test/flutter_test.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/config/model_catalog.dart';

void main() {
  group('GEMMA_ACTIVATION', () {
    test("maps to the engine argument; empty keeps the engine's own choice; "
        'anything else is refused', () {
      expect(activationFor(''), isNull);
      expect(activationFor('fp16'), ActivationDataType.float16);
      expect(activationFor('fp32'), ActivationDataType.float32);
      expect(() => activationFor('fp8'), throwsFormatException);
    });

    test("this build's value: accepted at startup, and the same in the "
        'load config the app passes', () {
      expect(checkGemmaActivation, returnsNormally);
      expect(kGemmaActivationType, activationFor(kGemmaActivation));
      expect(kLlmConfig.activation, kGemmaActivationType);
      expect(kDefineChatModel.llm.activation, kGemmaActivationType);
    });
  });
}
