import '../codec/prompt_plan_wire.dart';
import '../models/compiled_prompt_plan.dart';
import '../models/conversation_turns_models.dart';
import '../models/prompt_budget_diagnostics.dart';
import '../models/prompt_admission_budget.dart';
import 'heuristic_cost_estimator.dart';
import 'prompt_budget_policy.dart';

enum StandaloneMessageRole { system, user, assistant, tool }

class StandaloneToolCall {
  const StandaloneToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;
}

class StandalonePromptMessage {
  StandalonePromptMessage({
    required this.role,
    required this.content,
    this.sourceId,
    this.slotId,
    this.toolCallId,
    List<StandaloneToolCall> toolCalls = const [],
  }) : toolCalls = List.unmodifiable(toolCalls) {
    if ((role == StandaloneMessageRole.tool) != (toolCallId != null) ||
        (toolCalls.isNotEmpty && role != StandaloneMessageRole.assistant)) {
      throw ArgumentError('prompt_plan.invalid_tool_message');
    }
  }

  final StandaloneMessageRole role;
  final String content;
  final String? sourceId;

  /// Stable ordinary dialogue slot; tool-loop messages can share one slot.
  final String? slotId;
  final String? toolCallId;
  final List<StandaloneToolCall> toolCalls;

  Map<String, dynamic> toModelJson() => {
    'role': role.name,
    'content': content,
    if (toolCallId != null) 'tool_call_id': toolCallId,
    if (toolCalls.isNotEmpty)
      'tool_calls': toolCalls
          .map(
            (call) => {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
          )
          .toList(),
  };

  Map<String, dynamic> toSnapshotJson() => {
    ...toModelJson(),
    if (sourceId != null) 'source_id': sourceId,
    if (slotId != null) 'slot_id': slotId,
  };

  int cost(PromptCostEstimator estimator) =>
      estimator.message(content) +
      toolCalls.fold<int>(
        0,
        (sum, call) =>
            sum +
            6 +
            estimator.text(call.id) +
            estimator.text(call.name) +
            estimator.text(call.arguments),
      ) +
      (toolCallId == null ? 0 : 4 + estimator.text(toolCallId!));
}

class StandaloneHistoryGroup {
  StandaloneHistoryGroup({
    required this.id,
    required List<StandalonePromptMessage> messages,
  }) : messages = List.unmodifiable(messages) {
    if (id.isEmpty || messages.isEmpty) {
      throw ArgumentError('prompt_plan.invalid_history_group');
    }
    final pending = <String, String>{};
    final seenCalls = <String>{};
    for (final message in messages) {
      if (message.slotId == null ||
          message.slotId!.isEmpty ||
          message.role == StandaloneMessageRole.system) {
        throw ArgumentError('prompt_plan.invalid_history_slot');
      }
      if (message.role == StandaloneMessageRole.tool) {
        if (pending.remove(message.toolCallId) != message.slotId) {
          throw ArgumentError('prompt_plan.unpaired_tool_result');
        }
      } else {
        if (pending.isNotEmpty) {
          throw ArgumentError('prompt_plan.open_tool_group');
        }
        for (final call in message.toolCalls) {
          if (call.id.isEmpty || !seenCalls.add(call.id)) {
            throw ArgumentError('prompt_plan.duplicate_tool_call');
          }
          pending[call.id] = message.slotId!;
        }
      }
    }
    if (pending.isNotEmpty) throw ArgumentError('prompt_plan.open_tool_group');
  }

  final String id;
  final List<StandalonePromptMessage> messages;

  int cost(PromptCostEstimator estimator) =>
      messages.fold(0, (sum, m) => sum + m.cost(estimator));
}

class StandalonePromptAssembly {
  StandalonePromptAssembly({
    required List<StandalonePromptMessage> messages,
    required List<String> retainedHistoryGroupIds,
    required this.estimatedTokens,
    required List<PromptCompilationTrace> trace,
  }) : messages = List.unmodifiable(messages),
       retainedHistoryGroupIds = List.unmodifiable(retainedHistoryGroupIds),
       trace = List.unmodifiable(trace);

  final List<StandalonePromptMessage> messages;
  final List<String> retainedHistoryGroupIds;
  final int estimatedTokens;
  final List<PromptCompilationTrace> trace;
}

String standaloneHistoryDigest(List<StandaloneHistoryGroup> history) =>
    promptDigest(
      history
          .map(
            (group) => {
              'id': group.id,
              'messages': group.messages
                  .map((m) => m.toSnapshotJson())
                  .toList(),
            },
          )
          .toList(),
    );

/// Consumes the same domain plan as Rust. No macro execution, matching,
/// resource loading or model calls occur in this final assembly stage.
class StandalonePromptAssembler {
  const StandalonePromptAssembler();

  PromptAdmissionBudget prepareAdmission({
    required PreparedPromptCandidates candidates,
    required StandalonePromptBudgetPolicy policy,
    List<StandaloneHistoryGroup> history = const [],
    List<StandalonePromptMessage> fixedMessages = const [],
    int toolSchemaTokens = 0,
  }) {
    _validateHistory(history);
    if (toolSchemaTokens < 0) {
      throw ArgumentError('prompt_plan.invalid_tool_cost');
    }
    final estimator = policy.estimator;
    final units = {for (final u in candidates.units) u.unitId: u};
    final costs = <String, int>{};
    final unitCosts = <String, int>{};
    for (final emission in candidates.emissions) {
      final cost = estimator.message(units[emission.unitId]!.expandedText);
      costs[emission.emissionId] = cost;
      unitCosts.update(emission.unitId, (v) => v + cost, ifAbsent: () => cost);
    }
    final protectedHistory = history.skip(_protectedHistoryStart(history));
    final protectedCost = protectedHistory.fold<int>(
      0,
      (sum, g) => sum + g.cost(estimator),
    );
    final fixedCost =
        estimator.message(candidates.transformedInput) +
        toolSchemaTokens +
        fixedMessages.fold<int>(0, (sum, m) => sum + m.cost(estimator));
    final requiredLore = candidates.units
        .where(
          (u) =>
              u.worldbookId != null &&
              (u.retention == PromptRetention.required ||
                  u.ignoreWorldbookBudget),
        )
        .fold<int>(0, (sum, u) => sum + unitCosts[u.unitId]!);
    final nonLore =
        candidates.units.where((u) => u.worldbookId == null).toList()
          ..sort((a, b) {
            final required = (a.retention == PromptRetention.required ? 0 : 1)
                .compareTo(b.retention == PromptRetention.required ? 0 : 1);
            if (required != 0) return required;
            final tier = a.budgetTier.index.compareTo(b.budgetTier.index);
            return tier != 0
                ? tier
                : candidates.units
                      .indexOf(a)
                      .compareTo(candidates.units.indexOf(b));
          });
    var remaining =
        policy.inputLimit - fixedCost - protectedCost - requiredLore;
    if (remaining < 0) _overflow('required_floor');
    var nonLoreCost = 0;
    final admitted = <String>[];
    final trace = <PromptCompilationTrace>[];
    for (final unit in nonLore) {
      final cost = unitCosts[unit.unitId]!;
      if (cost <= remaining) {
        admitted.add(unit.unitId);
        nonLoreCost += cost;
        remaining -= cost;
      } else if (unit.retention == PromptRetention.required) {
        _overflow(unit.unitId);
      } else {
        trace.add(
          PromptCompilationTrace(
            unitId: unit.unitId,
            stage: 'budget',
            reason: 'optional_non_worldbook_rejected',
          ),
        );
      }
    }
    return PromptAdmissionBudget(
      candidateDigest: candidates.digest,
      budgetSnapshotDigest: policy.digest,
      layoutHistoryDigest: standaloneHistoryDigest(history),
      inputLimit: policy.inputLimit,
      worldbookAvailableTokens:
          policy.inputLimit - fixedCost - protectedCost - nonLoreCost,
      emissionCosts: costs,
      admittedNonWorldbookUnitIds: admitted,
      fixedContextCost: fixedCost,
      nonWorldbookPromptCost: nonLoreCost,
      protectedHistoryCost: protectedCost,
      requiresCompaction:
          fixedCost +
              nonLoreCost +
              unitCosts.entries
                  .where((entry) => units[entry.key]!.worldbookId != null)
                  .fold<int>(0, (sum, entry) => sum + entry.value) +
              history.fold<int>(0, (sum, g) => sum + g.cost(estimator)) >
          policy.autoTrigger,
      trace: trace,
    );
  }

  StandalonePromptAssembly assemble({
    required PreparedPromptCandidates candidates,
    required CompiledPromptPlan plan,
    required StandalonePromptBudgetPolicy policy,
    List<StandaloneHistoryGroup> history = const [],
    List<StandalonePromptMessage> fixedMessages = const [],
    int toolSchemaTokens = 0,
  }) {
    _validateHistory(history);
    if (toolSchemaTokens < 0 ||
        plan.candidateDigest != candidates.digest ||
        plan.budgetSnapshotDigest != policy.digest ||
        plan.layoutHistoryDigest != standaloneHistoryDigest(history)) {
      throw FormatException('prompt_plan.context_snapshot_stale');
    }
    final units = {for (final unit in plan.selectedUnits) unit.unitId: unit};
    final candidateUnits = {
      for (final unit in candidates.units) unit.unitId: unit,
    };
    for (final unit in plan.selectedUnits) {
      if (promptDigest(unit.toJson()) !=
          promptDigest(candidateUnits[unit.unitId]?.toJson())) {
        throw FormatException('prompt_plan.modified_admitted_unit');
      }
    }
    if (candidates.units.any(
      (u) =>
          (u.retention == PromptRetention.required ||
              u.ignoreWorldbookBudget) &&
          !units.containsKey(u.unitId),
    )) {
      throw FormatException('prompt_plan.required_unit_rejected');
    }
    final expectedEmissions = candidates.emissions
        .where((e) => units.containsKey(e.unitId))
        .toList();
    if (promptDigest(plan.emissions.map((e) => e.toJson()).toList()) !=
        promptDigest(expectedEmissions.map((e) => e.toJson()).toList())) {
      throw FormatException('prompt_plan.modified_emissions');
    }
    final estimator = policy.estimator;
    final trace = <PromptCompilationTrace>[...plan.admissionTrace];
    final fixedCost =
        estimator.message(candidates.transformedInput) +
        toolSchemaTokens +
        fixedMessages.fold<int>(0, (sum, m) => sum + m.cost(estimator)) +
        plan.emissions.fold<int>(
          0,
          (sum, e) => sum + estimator.message(units[e.unitId]!.expandedText),
        );
    var used =
        fixedCost + history.fold<int>(0, (sum, g) => sum + g.cost(estimator));
    var start = 0;
    final protectedStart = _protectedHistoryStart(history);
    while (used > policy.inputLimit && start < protectedStart) {
      used -= history[start].cost(estimator);
      trace.add(
        PromptCompilationTrace(
          unitId: history[start].id,
          stage: 'history',
          reason: 'old_history_group_dropped',
        ),
      );
      start++;
    }
    if (used > policy.inputLimit) _overflow('protected_context');
    final retained = history.skip(start).toList();
    final originalSlots = <String>[];
    final groupForSlot = <String, String>{};
    for (final group in history) {
      for (final message in group.messages) {
        if (!groupForSlot.containsKey(message.slotId)) {
          originalSlots.add(message.slotId!);
          groupForSlot[message.slotId!] = group.id;
        }
      }
    }
    final beforeMessage = <String, List<PromptEmission>>{};
    final before = <PromptEmission>[];
    final tail = <PromptEmission>[];
    final after = <PromptEmission>[];
    for (final emission
        in plan.emissions.toList()
          ..sort((a, b) => a.sequence.compareTo(b.sequence))) {
      switch (emission.placement) {
        case PromptPlacement.beforeHistory:
        case PromptPlacement.historyStart:
          before.add(emission);
        case PromptPlacement.afterHistory:
          after.add(emission);
        case PromptPlacement.tail:
          tail.add(emission);
        case PromptPlacement.atDepth:
          final depth = emission.depth!;
          if (depth == 0 || retained.isEmpty) {
            tail.add(emission);
            continue;
          }
          final slot = depth > originalSlots.length
              ? null
              : originalSlots[originalSlots.length - depth];
          final originalGroupId = slot == null ? null : groupForSlot[slot];
          final target =
              retained.where((g) => g.id == originalGroupId).firstOrNull ??
              retained.first;
          var index = 0;
          if (slot != null && target.id != originalGroupId) {
            trace.add(
              PromptCompilationTrace(
                unitId: emission.unitId,
                stage: 'layout',
                reason: 'anchor_relocated_after_compaction',
              ),
            );
          } else if (slot != null) {
            index = target.messages.indexWhere((m) => m.slotId == slot);
            // Move an anchor inside an unfinished tool exchange to its call.
            final pending = <String>{};
            var exchangeStart = 0;
            for (var i = 0; i < index; i++) {
              final message = target.messages[i];
              if (message.toolCalls.isNotEmpty && pending.isEmpty) {
                exchangeStart = i;
              }
              pending.addAll(message.toolCalls.map((c) => c.id));
              if (message.toolCallId != null) {
                pending.remove(message.toolCallId);
              }
            }
            if (pending.isNotEmpty) {
              index = exchangeStart;
              trace.add(
                PromptCompilationTrace(
                  unitId: emission.unitId,
                  stage: 'layout',
                  reason: 'anchor_adjusted_for_tool_group',
                ),
              );
            }
          }
          beforeMessage
              .putIfAbsent('${target.id}:$index', () => [])
              .add(emission);
      }
    }
    StandalonePromptMessage materialize(PromptEmission emission) {
      final unit = units[emission.unitId]!;
      return StandalonePromptMessage(
        role: switch (unit.role) {
          TurnMessageRole.system => StandaloneMessageRole.system,
          TurnMessageRole.user => StandaloneMessageRole.user,
          TurnMessageRole.assistant => StandaloneMessageRole.assistant,
        },
        content: unit.expandedText,
        sourceId: emission.emissionId,
      );
    }

    return StandalonePromptAssembly(
      messages: [
        ...fixedMessages,
        ...before.map(materialize),
        for (final group in retained) ...[
          for (var index = 0; index < group.messages.length; index++) ...[
            ...(beforeMessage['${group.id}:$index'] ?? <PromptEmission>[]).map(
              materialize,
            ),
            group.messages[index],
          ],
        ],
        ...tail.map(materialize),
        ...after.map(materialize),
        StandalonePromptMessage(
          role: StandaloneMessageRole.user,
          content: candidates.transformedInput,
        ),
      ],
      retainedHistoryGroupIds: retained.map((g) => g.id).toList(),
      estimatedTokens: used,
      trace: trace,
    );
  }

  int _protectedHistoryStart(List<StandaloneHistoryGroup> history) {
    final slots = <String>{};
    var start = history.length;
    while (start > 0 && slots.length < 2) {
      start--;
      slots.addAll(history[start].messages.map((m) => m.slotId!));
    }
    return start;
  }

  void _validateHistory(List<StandaloneHistoryGroup> history) {
    promptUnique(history.map((g) => g.id));
    final seenSlots = <String>{};
    for (final group in history) {
      String? currentSlot;
      for (final message in group.messages) {
        if (message.slotId != currentSlot) {
          if (!seenSlots.add(message.slotId!)) {
            throw ArgumentError('prompt_plan.noncontiguous_history_slot');
          }
          currentSlot = message.slotId;
        }
      }
    }
  }

  Never _overflow(String id) => throw PromptBudgetOverflowException(
    code: 'context_limit',
    trace: [
      CroppingTrace(
        unitId: id,
        stage: CroppingStage.finalRetainDrop,
        decision: RetainDecision.dropMandatoryOverflow,
        reason: 'protected_context_exceeds_input_limit',
      ),
    ],
  );
}
