import '../codec/prompt_plan_wire.dart';
import 'compiled_prompt_plan.dart';

/// Host-resolved costs and limits. The compiler never derives a model window.
class PromptAdmissionBudget {
  PromptAdmissionBudget({
    required this.candidateDigest,
    required this.budgetSnapshotDigest,
    required this.layoutHistoryDigest,
    required this.inputLimit,
    required this.worldbookAvailableTokens,
    required Map<String, int> emissionCosts,
    required List<String> admittedNonWorldbookUnitIds,
    required this.fixedContextCost,
    required this.nonWorldbookPromptCost,
    required this.protectedHistoryCost,
    this.requiresCompaction = false,
    List<PromptCompilationTrace> trace = const [],
  }) : emissionCosts = Map.unmodifiable(emissionCosts),
       admittedNonWorldbookUnitIds = List.unmodifiable(
         admittedNonWorldbookUnitIds,
       ),
       trace = List.unmodifiable(trace) {
    for (final value in [
      inputLimit,
      worldbookAvailableTokens,
      fixedContextCost,
      nonWorldbookPromptCost,
      protectedHistoryCost,
      ...emissionCosts.values,
    ]) {
      promptInt({'cost': value}, 'cost');
    }
    if (inputLimit == 0 ||
        worldbookAvailableTokens > inputLimit ||
        fixedContextCost +
                nonWorldbookPromptCost +
                protectedHistoryCost +
                worldbookAvailableTokens >
            inputLimit) {
      throw FormatException('prompt_plan.invalid_admission_budget');
    }
    promptUnique(this.admittedNonWorldbookUnitIds);
    for (final entry in this.trace) {
      PromptCompilationTrace.fromJson(entry.toJson());
    }
  }

  final String candidateDigest;
  final String budgetSnapshotDigest;
  final String layoutHistoryDigest;
  final int inputLimit;
  final int worldbookAvailableTokens;
  final Map<String, int> emissionCosts;
  final List<String> admittedNonWorldbookUnitIds;
  final int fixedContextCost;
  final int nonWorldbookPromptCost;
  final int protectedHistoryCost;
  final bool requiresCompaction;
  final List<PromptCompilationTrace> trace;

  String get costsDigest => promptDigest({
    'candidate_digest': candidateDigest,
    'layout_history_digest': layoutHistoryDigest,
    'budget_snapshot_digest': budgetSnapshotDigest,
    'emission_costs': emissionCosts,
    'admitted_non_worldbook_unit_ids': admittedNonWorldbookUnitIds,
    'fixed_context_cost': fixedContextCost,
    'non_worldbook_prompt_cost': nonWorldbookPromptCost,
    'protected_history_cost': protectedHistoryCost,
    'worldbook_available_tokens': worldbookAvailableTokens,
    'requires_compaction': requiresCompaction,
  });

  Map<String, dynamic> toJson() => {
    'schema_digest': promptPlanSchemaDigest,
    'candidate_digest': candidateDigest,
    'budget_snapshot_digest': budgetSnapshotDigest,
    'layout_history_digest': layoutHistoryDigest,
    'input_limit': inputLimit,
    'worldbook_available_tokens': worldbookAvailableTokens,
    'emission_costs': emissionCosts,
    'admitted_non_worldbook_unit_ids': admittedNonWorldbookUnitIds,
    'fixed_context_cost': fixedContextCost,
    'non_worldbook_prompt_cost': nonWorldbookPromptCost,
    'protected_history_cost': protectedHistoryCost,
    'requires_compaction': requiresCompaction,
    'trace': trace.map((t) => t.toJson()).toList(),
    'costs_digest': costsDigest,
  };

  factory PromptAdmissionBudget.fromJson(Object? value) {
    final json = promptObject(value, {
      'schema_digest',
      'candidate_digest',
      'budget_snapshot_digest',
      'layout_history_digest',
      'input_limit',
      'worldbook_available_tokens',
      'emission_costs',
      'admitted_non_worldbook_unit_ids',
      'fixed_context_cost',
      'non_worldbook_prompt_cost',
      'protected_history_cost',
      'requires_compaction',
      'trace',
      'costs_digest',
    });
    validatePromptSchema(json);
    final rawCosts = json['emission_costs'];
    if (rawCosts is! Map<String, dynamic> || rawCosts.length > 16384) {
      throw FormatException('prompt_plan.invalid_emission_costs');
    }
    final budget = PromptAdmissionBudget(
      candidateDigest: promptString(json, 'candidate_digest'),
      budgetSnapshotDigest: promptString(json, 'budget_snapshot_digest'),
      layoutHistoryDigest: promptString(json, 'layout_history_digest'),
      inputLimit: promptInt(json, 'input_limit', min: 1),
      worldbookAvailableTokens: promptInt(json, 'worldbook_available_tokens'),
      emissionCosts: {
        for (final key in rawCosts.keys) key: promptInt(rawCosts, key),
      },
      admittedNonWorldbookUnitIds: promptList(
        json,
        'admitted_non_worldbook_unit_ids',
        (v) => promptString({'id': v}, 'id'),
      ),
      fixedContextCost: promptInt(json, 'fixed_context_cost'),
      nonWorldbookPromptCost: promptInt(json, 'non_worldbook_prompt_cost'),
      protectedHistoryCost: promptInt(json, 'protected_history_cost'),
      requiresCompaction: promptBool(json, 'requires_compaction'),
      trace: promptList(json, 'trace', PromptCompilationTrace.fromJson),
    );
    if (json['costs_digest'] != budget.costsDigest) {
      throw FormatException('prompt_plan.costs_digest_mismatch');
    }
    return budget;
  }

  Map<String, int> validateFor(PreparedPromptCandidates candidates) {
    if (candidateDigest != candidates.digest) {
      throw FormatException('prompt_plan.context_snapshot_stale');
    }
    final emissionIds = candidates.emissions.map((e) => e.emissionId).toSet();
    if (emissionCosts.length != emissionIds.length ||
        !emissionCosts.keys.every(emissionIds.contains)) {
      throw FormatException('prompt_plan.incomplete_cost_vector');
    }
    final byId = {for (final u in candidates.units) u.unitId: u};
    if (admittedNonWorldbookUnitIds.any(
      (id) => byId[id] == null || byId[id]!.worldbookId != null,
    )) {
      throw FormatException('prompt_plan.invalid_host_admission');
    }
    final unitCosts = <String, int>{};
    for (final emission in candidates.emissions) {
      unitCosts.update(
        emission.unitId,
        (cost) => cost + emissionCosts[emission.emissionId]!,
        ifAbsent: () => emissionCosts[emission.emissionId]!,
      );
    }
    final admitted = admittedNonWorldbookUnitIds.toSet();
    if (candidates.units.any(
      (u) =>
          u.worldbookId == null &&
          u.retention == PromptRetention.required &&
          !admitted.contains(u.unitId),
    )) {
      throw FormatException('prompt_plan.required_unit_rejected');
    }
    final actualCost = admitted.fold<int>(0, (sum, id) => sum + unitCosts[id]!);
    if (actualCost != nonWorldbookPromptCost) {
      throw FormatException('prompt_plan.non_worldbook_cost_mismatch');
    }
    return Map.unmodifiable(unitCosts);
  }
}
