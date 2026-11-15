import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';

/// An independent character host with an at-depth Persona.
void main() {
  final now = DateTime.utc(2026, 11, 11);
  final character = Character(
    id: 'aria',
    ownerUserId: 'example',
    name: 'Aria',
    nickname: '',
    description: 'Aria is a librarian who answers patiently.',
    personality: '',
    scenario: '',
    firstMessage: '',
    alternateGreetings: [],
    exampleMessages: '',
    systemPrompt: '',
    postHistoryInstructions: '',
    tags: [],
    isSystem: false,
    visibilityScope: 'private',
    createdAt: now,
    updatedAt: now,
  );
  const sources = [
    PromptSourceSnapshot(
      key: 'aria:1',
      locator: 'example',
      resourceId: 'aria',
      revision: '1',
      contentHash: 'aria-content',
    ),
    PromptSourceSnapshot(
      key: 'persona:1',
      locator: 'example',
      resourceId: 'persona',
      revision: '1',
      contentHash: 'persona-content',
    ),
  ];
  final execution = const PromptExecutionPlanner().buildDomainPlan(
    DomainPromptPlanningInput(
      character: character,
      persona: const Persona(
        id: 'persona',
        name: 'Traveler',
        description: 'A curious visitor.',
        descriptionSettings: PersonaDescriptionSettings(
          position: PersonaDescriptionPosition.atDepth,
          depth: 1,
        ),
      ),
      promptBlocks: const [
        PromptBlock(
          id: 'identity',
          kind: 'core:characterDescription',
          name: 'identity',
        ),
      ],
    ),
  );
  final candidates = const DomainPromptCompiler().prepareCandidates(
    compilationId: 'character-example',
    executionPlan: execution,
    sourceSnapshots: sources,
    inputSnapshot: PromptInputSnapshot(
      canonicalInputDigest: promptDigest('Where is the atlas?'),
      scanHistoryDigest: promptDigest([]),
      variablesDigest: promptDigest({}),
      environmentDigest: promptDigest({'now': now.toIso8601String()}),
    ),
    speakerRef: const PromptSpeakerRef(
      kind: PromptSpeakerKind.character,
      resourceId: 'aria',
      snapshotKey: 'aria:1',
    ),
    unitSnapshotKeys: {'identity': 'aria:1', 'persona:persona': 'persona:1'},
    transformer: PromptContentTransformer(
      chatId: 'example',
      macroService: MacroService(
        MacroContext.fromData(character: character),
        clock: FrozenClock(now),
      ),
    ),
    currentInput: 'Where is the atlas?',
    historyTransformDigest: promptDigest(null),
  );
  const assembler = StandalonePromptAssembler();
  final policy = StandalonePromptBudgetPolicy(
    contextTokens: 4096,
    outputReserveTokens: 512,
  );
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
}
