import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';

/// Run with `dart run example/standalone.dart`. No Flutter, Rust or database.
void main() {
  const source = PromptSourceSnapshot(
    key: 'profile:1',
    locator: 'example',
    resourceId: 'profile',
    revision: '1',
    contentHash: 'example-profile',
  );
  final planningInput = DomainPromptPlanningInput(
    promptBlocks: const [
      PromptBlock(
        id: 'instruction',
        kind: 'app:instruction',
        name: 'instruction',
        promptProfileId: 'profile',
        content: '请用中文回答。{{setvar::style::简洁}}{{getvar::style}}',
      ),
    ],
  );
  final candidates = const DomainPromptCompiler().prepareCandidates(
    compilationId: 'example-turn',
    executionPlan: const PromptExecutionPlanner().buildDomainPlan(
      planningInput,
    ),
    sourceSnapshots: [source],
    inputSnapshot: PromptInputSnapshot(
      canonicalInputDigest: promptDigest('你好'),
      scanHistoryDigest: promptDigest([]),
      variablesDigest: promptDigest({}),
      environmentDigest: promptDigest({
        'now': '2026-11-11T00:00:00Z',
        'seed': 1,
      }),
    ),
    speakerRef: const PromptSpeakerRef(kind: PromptSpeakerKind.assistant),
    unitSnapshotKeys: {'instruction': source.key},
    transformer: PromptContentTransformer(
      macroService: MacroService(
        const MacroContext(),
        clock: FrozenClock(DateTime.utc(2026, 11, 11)),
        random: SeededRandomSource(1),
      ),
      chatId: 'example',
    ),
    currentInput: '你好',
    historyTransformDigest: promptDigest(null),
  );
  final policy = StandalonePromptBudgetPolicy(
    contextTokens: 4096,
    outputReserveTokens: 512,
  );
  const assembler = StandalonePromptAssembler();
  final budget = assembler.prepareAdmission(
    candidates: candidates,
    policy: policy,
  );
  final plan = const DomainPromptCompiler().admitCandidates(candidates, budget);
  final result = assembler.assemble(
    candidates: candidates,
    plan: plan,
    policy: policy,
  );
  for (final message in result.messages) {
    stdout.writeln('${message.role.name}: ${message.content}');
  }
  stdout.writeln(
    'estimated tokens: ${result.estimatedTokens}/${policy.inputLimit}',
  );
}
