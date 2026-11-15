import '../models/compiled_prompt_plan.dart';
import '../models/prompt_admission_budget.dart';
import '../models/prompt_execution_models.dart';
import '../models/conversation_turns_models.dart';
import '../models/regex_script.dart';
import '../worldinfo/world_info_budget_admission.dart';
import 'prompt_content_transformer.dart';

enum PromptContentPolicy { expandedDomainText, literalInjectionText }

/// Compiles domain text and placement constraints, never final model messages.
class DomainPromptCompiler {
  const DomainPromptCompiler();

  PreparedPromptCandidates prepareCandidates({
    required String compilationId,
    required PromptExecutionPlan executionPlan,
    required List<PromptSourceSnapshot> sourceSnapshots,
    required PromptInputSnapshot inputSnapshot,
    required PromptSpeakerRef speakerRef,
    required Map<String, String> unitSnapshotKeys,
    required PromptContentTransformer transformer,
    required String currentInput,
    required String historyTransformDigest,
    List<PromptCompilationTrace> matchTrace = const [],
    PromptContentPolicy contentPolicy = PromptContentPolicy.expandedDomainText,
  }) {
    final units = <String, CompiledPromptUnit>{};
    final sourceUnits = <String, ResolvedExecutionUnit>{};
    final expandedIds = <String>{};
    final emissions = <PromptEmission>[];
    final trace = <PromptCompilationTrace>[
      ...executionPlan.trace.map(
        (entry) => PromptCompilationTrace(
          unitId: entry.unitId,
          stage: entry.stage.name,
          reason: entry.reason,
          sourceResourceId: entry.sourceRef,
          targetUnitId: entry.targetUnitId,
          anchorId: entry.anchorId,
          outletName: entry.outletId,
        ),
      ),
      ...matchTrace,
    ];
    final sources = {for (final source in sourceSnapshots) source.key: source};

    void emit(
      ResolvedExecutionUnit unit,
      PromptPlacement placement, {
      int? depth,
      String? outlet,
    }) {
      if (unit.sourceKind == ExecutionSourceKind.marker) {
        throw FormatException('prompt_plan.marker_cannot_emit');
      }
      final previous = sourceUnits[unit.id];
      if (previous != null && !_sameUnit(previous, unit)) {
        throw FormatException('prompt_plan.conflicting_unit_id');
      }
      sourceUnits[unit.id] = unit;
      if (!unit.enabled || unit.contentTemplate.trim().isEmpty) return;
      if (expandedIds.add(unit.id)) {
        final key = unitSnapshotKeys[unit.id];
        final source = sources[key];
        if (key == null ||
            source == null ||
            source.resourceId != unit.sourceRef) {
          throw FormatException('prompt_plan.missing_source_snapshot');
        }
        final literal =
            contentPolicy == PromptContentPolicy.literalInjectionText;
        final text = literal
            ? unit.contentTemplate
            : transformer.expand(
                unit.contentTemplate.trim(),
                placement: unit.sourceKind == ExecutionSourceKind.worldInfoEntry
                    ? RegexPlacement.worldInfo
                    : null,
                depth: unit.depth,
              );
        // A regex or macro may intentionally remove a complete contribution.
        if (text.isEmpty) return;
        final semantic =
            unit.semanticKind ??
            switch (unit.sourceKind) {
              ExecutionSourceKind.characterCore => PromptSemanticKind.identity,
              ExecutionSourceKind.persona => PromptSemanticKind.persona,
              ExecutionSourceKind.worldInfoEntry =>
                PromptSemanticKind.knowledge,
              _ => PromptSemanticKind.instruction,
            };
        units[unit.id] = CompiledPromptUnit(
          unitId: unit.id,
          sourceKind: unit.sourceKind,
          sourceResourceId: source.resourceId,
          sourceSnapshotKey: key,
          semanticKind: semantic,
          role: _role(unit.role),
          expandedText: text,
          retention:
              unit.mandatory || unit.budgetTier == ExecutionBudgetTier.mandatory
              ? PromptRetention.required
              : PromptRetention.optional,
          budgetTier: unit.budgetTier,
          worldbookId: unit.sourceKind == ExecutionSourceKind.worldInfoEntry
              ? source.resourceId
              : null,
          ignoreWorldbookBudget: unit.ignoreBudget,
          injectionOrder: unit.injectionOrder,
          sourceOrder: unit.sourceOrder,
        );
        if (!literal &&
            RegExp(
              r'\{\{(?:set|add|inc|dec)(?:global)?var::',
              caseSensitive: false,
            ).hasMatch(unit.contentTemplate)) {
          trace.add(
            PromptCompilationTrace(
              unitId: unit.id,
              stage: 'expansion',
              reason: 'scratch_variable_operation',
            ),
          );
        }
      }
      if (!units.containsKey(unit.id)) return;
      emissions.add(
        PromptEmission(
          emissionId: '${unit.id}@${emissions.length}',
          unitId: unit.id,
          placement: placement,
          sequence: emissions.length,
          depth: depth,
          outletName: outlet,
        ),
      );
    }

    var afterHistory = false;
    for (final unit in executionPlan.shellSequence) {
      if (unit.sourceKind == ExecutionSourceKind.marker) {
        final marker = (unit.markerId ?? '').trim();
        if (marker == 'history') afterHistory = true;
        for (final outlet
            in executionPlan.outletMap[marker] ?? <ResolvedExecutionUnit>[]) {
          emit(
            outlet,
            afterHistory
                ? PromptPlacement.afterHistory
                : PromptPlacement.beforeHistory,
            outlet: marker,
          );
        }
      } else {
        emit(
          unit,
          afterHistory ||
                  unit.insertionMode == ExecutionInsertionMode.afterHistory
              ? PromptPlacement.afterHistory
              : PromptPlacement.beforeHistory,
        );
      }
    }
    for (final point in executionPlan.historySplicePoints) {
      if (point.offsetFromEnd < 0) {
        throw FormatException('prompt_plan.invalid_depth');
      }
      for (final unit in point.units) {
        emit(unit, PromptPlacement.atDepth, depth: point.offsetFromEnd);
      }
    }
    return PreparedPromptCandidates(
      compilationId: compilationId,
      sourceSnapshots: sourceSnapshots,
      inputSnapshot: inputSnapshot,
      speakerRef: speakerRef,
      units: units.values.toList(),
      emissions: emissions,
      transformedInput: transformer.applyRegex(
        currentInput,
        placement: RegexPlacement.userInput,
      ),
      historyTransformDigest: historyTransformDigest,
      trace: trace,
    );
  }

  CompiledPromptPlan admitCandidates(
    PreparedPromptCandidates candidates,
    PromptAdmissionBudget budget, {
    WorldInfoBudgetPlan worldInfoPolicy = const WorldInfoBudgetPlan(),
    Map<String, int> worldbookTokenBudgets = const {},
  }) => const WorldInfoBudgetAdmissionService().admitCandidates(
    candidates,
    budget,
    worldInfoPolicy: worldInfoPolicy,
    worldbookTokenBudgets: worldbookTokenBudgets,
  );

  TurnMessageRole _role(String role) => switch (role.trim().toLowerCase()) {
    'system' => TurnMessageRole.system,
    'user' => TurnMessageRole.user,
    'assistant' => TurnMessageRole.assistant,
    _ => throw FormatException('prompt_plan.invalid_role'),
  };

  bool _sameUnit(ResolvedExecutionUnit a, ResolvedExecutionUnit b) =>
      a.sourceKind == b.sourceKind &&
      a.sourceRef == b.sourceRef &&
      a.contentTemplate == b.contentTemplate &&
      a.role == b.role &&
      a.depth == b.depth &&
      a.enabled == b.enabled &&
      a.mandatory == b.mandatory &&
      a.budgetTier == b.budgetTier &&
      a.semanticKind == b.semanticKind &&
      a.ignoreBudget == b.ignoreBudget &&
      a.sourceOrder == b.sourceOrder &&
      a.injectionOrder == b.injectionOrder;
}
