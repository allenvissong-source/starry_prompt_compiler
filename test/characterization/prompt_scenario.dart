import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';

class PromptScenarioUserInput {
  const PromptScenarioUserInput({required this.text});
  final String text;
}

/// Test data; budgets are explicit host input limits, not compiler decisions.
class PromptScenarioInput {
  const PromptScenarioInput({
    required this.sessionId,
    required this.topicId,
    required this.characterId,
    required this.history,
    required this.pendingUserInput,
    this.generationType = 'chat',
    this.inputLimit = 100000,
    this.worldInfoBudgetPlan = const WorldInfoBudgetPlan(),
    this.promptContext = const SessionPromptContext(),
    this.sessionDisableOverlay = const PromptDisableOverlay(),
    this.characterDisableOverlay = const PromptDisableOverlay(),
  });

  final String sessionId;
  final String topicId;
  final String characterId;
  final List<CharacterHistoryMessage> history;
  final PromptScenarioUserInput pendingUserInput;
  final String generationType;
  final int inputLimit;
  final WorldInfoBudgetPlan worldInfoBudgetPlan;
  final SessionPromptContext promptContext;
  final PromptDisableOverlay sessionDisableOverlay;
  final PromptDisableOverlay characterDisableOverlay;
}

/// A fixture view keeps context assertions separate from the submitted input.
class ScenarioAssembly {
  ScenarioAssembly(this.assembly);

  final StandalonePromptAssembly assembly;
  List<StandalonePromptMessage> get contextMessages =>
      assembly.messages.sublist(0, assembly.messages.length - 1);
  StandalonePromptMessage get submittedMessage => assembly.messages.last;
  List<PromptCompilationTrace> get trace => assembly.trace;
}

ScenarioAssembly assembleScenario({
  required PromptScenarioInput request,
  required Character character,
  required ResolvedPromptContext resolvedContext,
  PromptExecutionPlan? executionPlan,
  List<CharacterHistoryMessage>? assembledHistory,
  MacroService? macroService,
}) {
  final history = assembledHistory == null
      ? request.history
      : assembledHistory.take(assembledHistory.length - 1).toList();
  final plan =
      executionPlan ??
      const PromptExecutionPlanner().buildDomainPlan(
        DomainPromptPlanningInput(
          character: character,
          persona: resolvedContext.persona,
          promptBlocks: resolvedContext.resolvedPromptBlocks,
          worldInfoEntries: resolvedContext.worldInfoEntries,
          promptContext: request.promptContext,
          historyLength: history.length,
          generationType: request.generationType,
          sessionDisableOverlay: request.sessionDisableOverlay,
          characterDisableOverlay: request.characterDisableOverlay,
          worldInfoBudgetPlan: request.worldInfoBudgetPlan,
        ),
      );
  final units = [
    ...plan.shellSequence,
    ...plan.outletMap.values.expand((units) => units),
    ...plan.historySplicePoints.expand((point) => point.units),
  ].where((unit) => unit.sourceKind != ExecutionSourceKind.marker).toList();
  final sourceIds = {character.id, ...units.map((unit) => unit.sourceRef)};
  final sources = [
    for (final id in sourceIds)
      PromptSourceSnapshot(
        key: id,
        locator: 'fixture:$id',
        resourceId: id,
        revision: '1',
        contentHash: promptDigest(
          units
              .where((unit) => unit.sourceRef == id)
              .map((unit) => [unit.id, unit.contentTemplate])
              .toList(),
        ),
      ),
  ];
  final candidates = const DomainPromptCompiler().prepareCandidates(
    compilationId: request.topicId,
    executionPlan: plan,
    sourceSnapshots: sources,
    unitSnapshotKeys: {for (final unit in units) unit.id: unit.sourceRef},
    inputSnapshot: PromptInputSnapshot(
      canonicalInputDigest: promptDigest(request.pendingUserInput.text),
      scanHistoryDigest: promptDigest(
        history.map((m) => m.textContent).toList(),
      ),
      variablesDigest: promptDigest(resolvedContext.resolvedVariables),
      environmentDigest: promptDigest('fixture'),
    ),
    speakerRef: PromptSpeakerRef(
      kind: PromptSpeakerKind.character,
      resourceId: character.id,
      snapshotKey: character.id,
    ),
    transformer: PromptContentTransformer(
      macroService:
          macroService ??
          MacroService(
            MacroContext.fromData(
              character: character,
              persona: resolvedContext.persona,
              chatId: request.topicId,
              messages: history,
              currentInput: request.pendingUserInput.text,
              resolvedVariables: resolvedContext.resolvedVariables,
              clock: FrozenClock(DateTime.utc(2026)),
            ),
            clock: FrozenClock(DateTime.utc(2026)),
            random: SeededRandomSource(0),
          ),
      chatId: request.topicId,
      globalVariables: resolvedContext.resolvedVariables,
      regexProfile: resolvedContext.regexProfile,
    ),
    currentInput: request.pendingUserInput.text,
    historyTransformDigest: promptDigest('fixture'),
  );
  final layoutHistory = [
    for (var i = 0; i < history.length; i++)
      StandaloneHistoryGroup(
        id: 'group:$i',
        messages: [
          StandalonePromptMessage(
            role: switch (history[i].role) {
              TurnMessageRole.system => StandaloneMessageRole.system,
              TurnMessageRole.user => StandaloneMessageRole.user,
              TurnMessageRole.assistant => StandaloneMessageRole.assistant,
            },
            content: history[i].textContent,
            slotId: history[i].messageId ?? 'history:$i',
            sourceId: history[i].messageId,
          ),
        ],
      ),
  ];
  final limit = request.inputLimit;
  final context = limit * 2 + 100;
  final policy = StandalonePromptBudgetPolicy(
    contextTokens: context,
    outputReserveTokens: context - ((context + 19) ~/ 20) - limit,
  );
  const assembler = StandalonePromptAssembler();
  final budget = assembler.prepareAdmission(
    candidates: candidates,
    policy: policy,
    history: layoutHistory,
  );
  final compiled = const DomainPromptCompiler().admitCandidates(
    candidates,
    budget,
    worldInfoPolicy: request.worldInfoBudgetPlan,
    worldbookTokenBudgets: resolvedContext.worldbookTokenBudgets,
  );
  return ScenarioAssembly(
    assembler.assemble(
      candidates: candidates,
      plan: compiled,
      policy: policy,
      history: layoutHistory,
    ),
  );
}
