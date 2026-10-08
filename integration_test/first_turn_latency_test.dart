// Where Demo 1's first-turn latency goes with the skills system
// prompt (macOS). Drives the app's own LlmService and
// EdgeAiConversationRepository (no UI, no speech, no retrieval) so only the
// LLM side is measured:
//
//   fvm flutter test integration_test/first_turn_latency_test.dart -d macos \
//     --dart-define=GEMMA_MODEL_PATH=$HOME/Work/gemma-4-E2B-it.litertlm
//
// Optional: --dart-define=LAT_VARIANTS=app,v0 (default: app; the first one
// also pays the process's first long prefill) and
// --dart-define=LAT_ROUNDS=6, --dart-define=LAT_WARMUP_WORDS=400,900 (extra
// plain prefills after the app's warm-up, an experiment).
//
// Variants (each turn on a freshly opened chat, the way entering Demo 1
// opens one):
// - plain: the voice-chat profile without skills (Demo 1 before Inc 6);
// - app: the agent chat exactly as the app builds it now (Inc 8 template,
//   tool wording and skill descriptions; image turns carry the responder's
//   direct-answer hint);
// - v0: the Inc 7 agent chat (library tool declarations, Inc 7 template and
//   camera-watch description), kept to compare against.
// Per variant and round: a text question, an image question, and two skill
// requests (which must call a tool). Prints one `LAT …` line per turn with
// its tool calls (`calls=`), the tokenizer cost of the budget guard, and a
// `LAT summary` line per variant: spurious tool-call rate on the non-skill
// turns, skill hit rate, median time to first text and to the first
// sentence, median prefill.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart' show Message, Tool;
import 'package:flutter_edge_ai_agent/flutter_edge_ai_agent.dart'
    show AgentSession, Skill, SkillRegistry, loadSkillTool, runIntentTool;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:litert_hackathon/config/bootstrap.dart';
import 'package:litert_hackathon/config/env.dart';
import 'package:litert_hackathon/config/model_catalog.dart';
import 'package:litert_hackathon/data/repositories/conversation_repository_edge_ai.dart';
import 'package:litert_hackathon/data/repositories/skill_repository.dart';
import 'package:litert_hackathon/data/services/images/image_normalizer.dart';
import 'package:litert_hackathon/data/services/llm/llm_service.dart';
import 'package:litert_hackathon/data/services/model_store/local_files.dart';
import 'package:litert_hackathon/data/services/skills/skill_store_service.dart';
import 'package:litert_hackathon/domain/models/assistant_event.dart';
import 'package:litert_hackathon/domain/models/skill_step.dart';
import 'package:litert_hackathon/domain/use_cases/prompt_builder.dart';
import 'package:litert_hackathon/utils/result.dart';

const _variants = String.fromEnvironment('LAT_VARIANTS', defaultValue: 'app');
const _rounds = int.fromEnvironment('LAT_ROUNDS', defaultValue: 6);
const _warmupWords = String.fromEnvironment('LAT_WARMUP_WORDS');
const _textQuestion = 'What is the capital of France? Answer in one sentence.';
const _imageQuestion = 'What animal is this? Answer in one sentence.';
const _skillRequests = ['Set a timer for 10 seconds', 'What time is it?'];

/// The Inc 7 agent system prompt, verbatim (variant v0).
const _inc7Template =
    'You are a helpful on-device voice assistant. Replies are read aloud: a '
    'few short sentences, plain text.\n'
    'If the request matches one of these skills, call loadSkill with its '
    'name, then follow its instructions:\n'
    '__SKILLS__\n'
    'Otherwise answer directly without calling any tool.\n'
    'Live facts about this device and this app (the loaded models, their '
    'backends and accelerators, memory), the time and date, timers and the '
    'camera come only from skills. Knowledge-base excerpts in a message are '
    'general documentation and never replace a skill.';

/// The Inc 7 camera-watch description (variant v0).
const _inc7CameraWatch =
    "Watch the camera and say when an everyday object such as a person, cup, "
    "dog or phone appears ('tell me when you see a cup'), or stop watching.";

final class _Variant {
  const _Variant(this.name, this.profile, this.tools, this.skills);

  final String name;
  final ConversationProfile profile;
  final List<Tool> tools;
  final List<Skill>? Function(List<Skill> scanned) skills;
}

/// One measured turn.
final class _Turn {
  _Turn(
    this.variant,
    this.kind,
    this.ttft,
    this.prefill,
    this.firstSentence,
    this.calls,
  );

  final String variant;
  final String kind;

  /// From `ask()` to the first text delta (budget guard included).
  final Duration? ttft;

  /// Tokens prefilled by this turn (conversation input-token delta; null
  /// when the turn had tool rounds).
  final int? prefill;

  /// From `ask()` to the first sentence end (what TTS waits for).
  final Duration? firstSentence;

  /// The tool calls the model made (loadSkill and runIntent).
  final List<String> calls;
}

int _median(Iterable<int> values) {
  if (values.isEmpty) return -1;
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first-turn latency and spurious tool calls, plain vs '
      'agent chats', (tester) async {
    if (kGemmaModelPath.isEmpty) fail('Pass GEMMA_MODEL_PATH');
    await initEdgeAi();
    final llm = LlmService();
    addTearDown(llm.close);
    final installed = await llm.install(
      path: await resolveLocalPath(kGemmaModelPath),
      onProgress: (_) {},
    );
    expect(installed, isA<Ok<String>>(), reason: '$installed');
    final loaded = await llm.load(kDefineChatModel);
    expect(loaded, isA<Ok<LlmInfo>>(), reason: '$loaded');
    // The app's setup warm-up.
    final warm = await llm.warmUp(kSampler, withImage: true);
    expect(warm, isA<Ok<Duration>>(), reason: '$warm');
    // Experiment: extra plain-session prefills of about these many tokens,
    // to see whether the process's first long prefill is a one-time cost.
    for (final words in [
      for (final w in _warmupWords.split(','))
        if (w.trim().isNotEmpty) int.parse(w.trim()),
    ]) {
      final watch = Stopwatch()..start();
      final session = await llm.model.createSession(
        temperature: kSampler.temperature,
        topK: kSampler.topK,
        maxOutputTokens: 1,
      );
      try {
        await session.addQueryChunk(
          Message(text: List.filled(words, 'skill').join(' '), isUser: true),
        );
        await session.getResponseAsync().drain<void>();
      } finally {
        await session.close();
      }
      debugPrint('LAT warmup words=$words ${watch.elapsedMilliseconds}ms');
    }

    final scanned = (await SkillRepository(
      store: SkillStoreService(),
    ).refresh()).agentSkills;
    expect(scanned, isNotEmpty);
    final png = (await normalizeForLlm(
      (await rootBundle.load('test_assets/cats.jpg')).buffer.asUint8List(),
    )).png;

    final variants = {
      'app': _Variant('app', kVoiceChatProfile, kAgentTools, (s) => s),
      'v0': _Variant(
        'v0',
        const ConversationProfile(
          name: 'voice-chat',
          systemInstruction: '',
          maxOutputTokens: 384,
          skillsTemplate: _inc7Template,
        ),
        const [loadSkillTool, runIntentTool],
        (s) => [
          for (final skill in s)
            skill.name == 'camera-watch'
                ? Skill(
                    name: skill.name,
                    description: _inc7CameraWatch,
                    instructions: skill.instructions,
                    type: skill.type,
                  )
                : skill,
        ],
      ),
    };
    final chosen = [
      for (final name in _variants.split(','))
        variants[name.trim()] ?? fail('unknown variant $name'),
    ];

    // The budget guard's tokenizer calls on an agent chat (once per chat),
    // and the system prompt size per variant.
    for (final v in chosen) {
      final skills = v.skills(scanned)!;
      final registry = SkillRegistry()..addAll(skills, selected: true);
      final systemPrompt = AgentSession.buildSystemPrompt(
        registry,
        systemPromptTemplate: v.profile.skillsTemplate!,
      );
      final chat = await llm.model.createChat(
        temperature: kSampler.temperature,
        topK: kSampler.topK,
        maxOutputTokens: kVoiceChatProfile.maxOutputTokens,
        enableThinking: kThinking,
        supportImage: true,
        systemInstruction: systemPrompt,
      );
      final watch = Stopwatch()..start();
      final systemTokens = await chat.session.sizeInTokens(systemPrompt);
      var skillTokens = 0;
      for (final skill in skills) {
        skillTokens += await chat.session.sizeInTokens(
          '${skill.name}\n${skill.description}\n${skill.instructions}',
        );
      }
      watch.stop();
      var toolTokens = 0;
      for (final tool in v.tools) {
        toolTokens += await chat.session.sizeInTokens(
          '${tool.name} ${tool.description} ${tool.parameters}',
        );
      }
      debugPrint(
        'LAT tokenize variant=${v.name} system=$systemTokens tok '
        'tool_text=$toolTokens tok skills=$skillTokens tok over '
        '${skills.length} calls+1 in ${watch.elapsedMicroseconds} µs',
      );
      await chat.close();
    }

    Future<_Turn> turn(
      EdgeAiConversationRepository conversation,
      String variant,
      String kind,
      String prompt, {
      Uint8List? image,
    }) async {
      final watch = Stopwatch()..start();
      Duration? first;
      Duration? sentence;
      final reply = StringBuffer();
      final calls = <String>[];
      GenerationMetrics? metrics;
      Object? failure;
      await for (final event in conversation.ask(
        prompt,
        image: image,
        onStep: (step) {
          switch (step) {
            case SkillLoaded(:final name):
              calls.add('loadSkill($name)');
            case IntentCalled(:final intent):
              calls.add('runIntent($intent)');
            case _:
              break;
          }
        },
      )) {
        switch (event) {
          case AssistantTextDelta(:final text):
            first ??= watch.elapsed;
            reply.write(text);
            if (sentence == null && RegExp(r'[.!?](\s|$)').hasMatch('$reply')) {
              sentence = watch.elapsed;
            }
          case AssistantDone(metrics: final m):
            metrics = m;
          case AssistantFailed(:final error):
            failure = error;
          case AssistantContextReset():
            break;
        }
      }
      expect(failure, isNull, reason: '$kind: $failure');
      debugPrint(
        'LAT variant=$variant kind=$kind ttft=${first?.inMilliseconds}ms '
        'first_sentence=${sentence?.inMilliseconds}ms '
        'prefill=${metrics?.prefillTokens}tok ctx=${metrics?.contextTokens}tok '
        'calls=$calls total=${metrics?.total.inMilliseconds}ms '
        'reply="${reply.toString().replaceAll('\n', ' ')}"',
      );
      return _Turn(
        variant,
        kind,
        first,
        metrics?.prefillTokens,
        sentence,
        calls,
      );
    }

    final turns = <_Turn>[];
    for (final v in chosen) {
      final conversation = EdgeAiConversationRepository(
        llm: llm,
        agentTools: v.tools,
      );
      final skills = v.skills(scanned)!;
      for (var round = 1; round <= _rounds; round++) {
        expect(
          await conversation.open(v.profile, skills: skills),
          isA<Ok<void>>(),
        );
        turns.add(await turn(conversation, v.name, 'text-1', _textQuestion));
        turns.add(await turn(conversation, v.name, 'text-2', _textQuestion));
        expect(
          await conversation.open(v.profile, skills: skills),
          isA<Ok<void>>(),
        );
        turns.add(
          await turn(
            conversation,
            v.name,
            'image-1',
            // The app's responder adds the direct-answer hint to an image
            // turn that is not a skill question (Inc 8); v0 is Inc 7.
            v.name == 'app'
                ? '$_imageQuestion${PromptBuilder.directAnswerHint}'
                : _imageQuestion,
            image: png,
          ),
        );
        for (final request in _skillRequests) {
          expect(
            await conversation.open(v.profile, skills: skills),
            isA<Ok<void>>(),
          );
          turns.add(await turn(conversation, v.name, 'skill', request));
        }
      }
      await conversation.close();
    }

    // Plain chat (Demo 1 before Inc 6).
    final plain = EdgeAiConversationRepository(llm: llm);
    for (var round = 1; round <= 3; round++) {
      expect(await plain.open(kVoiceChatProfile), isA<Ok<void>>());
      turns.add(await turn(plain, 'plain', 'text-1', _textQuestion));
      expect(await plain.open(kVoiceChatProfile), isA<Ok<void>>());
      turns.add(
        await turn(plain, 'plain', 'image-1', _imageQuestion, image: png),
      );
    }
    await plain.close();

    for (final variant in {for (final t in turns) t.variant}) {
      final of = turns.where((t) => t.variant == variant).toList();
      final answers = of.where((t) => t.kind != 'skill').toList();
      final skillTurns = of.where((t) => t.kind == 'skill').toList();
      final spurious = answers.where((t) => t.calls.isNotEmpty).length;
      final hits = skillTurns
          .where((t) => t.calls.any((c) => c.startsWith('runIntent(')))
          .length;
      final summary = StringBuffer(
        'LAT summary variant=$variant spurious_calls=$spurious/'
        '${answers.length} skill_hits=$hits/${skillTurns.length}',
      );
      for (final kind in ['text-1', 'text-2', 'image-1']) {
        final k = answers.where((t) => t.kind == kind);
        if (k.isEmpty) continue;
        summary.write(
          ' | $kind ttft=${_median([for (final t in k) ?t.ttft?.inMilliseconds])}ms'
          ' sentence=${_median([for (final t in k) ?t.firstSentence?.inMilliseconds])}ms'
          ' prefill=${_median([for (final t in k) ?t.prefill])}tok'
          ' calls=${k.where((t) => t.calls.isNotEmpty).length}/${k.length}',
        );
      }
      debugPrint('$summary');
    }
    debugPrint('LAT host=${Platform.operatingSystemVersion}');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
