import '../models/prompt_budget_diagnostics.dart';
import '../models/prompt_execution_models.dart';
import '../models/compiled_prompt_plan.dart';
import '../models/prompt_admission_budget.dart';

/// External injection allowances use allocation tiers rather than requiring
/// a complete model context. The model host must enforce its final budget.
enum WorldInfoAdmissionMode { requiredContext, injectionAllowance }

class WorldInfoBudgetAdmissionService {
  const WorldInfoBudgetAdmissionService();

  CompiledPromptPlan admitCandidates(
    PreparedPromptCandidates candidates,
    PromptAdmissionBudget budget, {
    WorldInfoBudgetPlan worldInfoPolicy = const WorldInfoBudgetPlan(),
    Map<String, int> worldbookTokenBudgets = const {},
    WorldInfoAdmissionMode mode = WorldInfoAdmissionMode.requiredContext,
  }) {
    final costs = budget.validateFor(candidates);
    final enforceRequired = mode == WorldInfoAdmissionMode.requiredContext;
    if (!enforceRequired &&
        candidates.units.any((u) => u.worldbookId == null)) {
      throw FormatException('prompt_plan.injection_requires_worldbook_units');
    }
    if (worldInfoPolicy.percent < 0 ||
        !worldInfoPolicy.percent.isFinite ||
        worldInfoPolicy.minTokens < 0 ||
        (worldInfoPolicy.capTokens ?? 0) < 0 ||
        worldbookTokenBudgets.values.any((cost) => cost < 0)) {
      throw FormatException('prompt_plan.invalid_worldbook_budget');
    }
    final policyLimit = worldInfoPolicy.resolveBudgetTokens(budget.inputLimit);
    var globalRemaining = budget.worldbookAvailableTokens;
    var policyRemaining = policyLimit;
    final bookRemaining = Map<String, int>.from(worldbookTokenBudgets);
    final selected = budget.admittedNonWorldbookUnitIds.toSet();
    final trace = <PromptCompilationTrace>[
      ...candidates.trace,
      ...budget.trace,
    ];
    final worldbookUnits =
        candidates.units.where((u) => u.worldbookId != null).toList()..sort(
          (a, b) =>
              _compareCompiledPriority(a, b, enforceRequired: enforceRequired),
        );

    void decide(CompiledPromptUnit unit, bool retained, String reason) {
      if (retained) selected.add(unit.unitId);
      trace.add(
        PromptCompilationTrace(
          unitId: unit.unitId,
          stage: 'budget',
          reason: reason,
          sourceResourceId: unit.sourceResourceId,
        ),
      );
    }

    // Required and ignoreBudget content is globally charged before optional
    // lore. ignoreBudget bypasses only the book/policy sublimit.
    for (final unit in worldbookUnits.where(
      (u) =>
          (enforceRequired && u.retention == PromptRetention.required) ||
          u.ignoreWorldbookBudget,
    )) {
      final cost = costs[unit.unitId]!;
      final bookLimit = bookRemaining[unit.worldbookId];
      if (cost > globalRemaining ||
          (!unit.ignoreWorldbookBudget &&
              ((policyRemaining != null && cost > policyRemaining) ||
                  (bookLimit != null && cost > bookLimit)))) {
        throw PromptBudgetOverflowException(
          code: 'context_limit',
          trace: [
            CroppingTrace(
              unitId: unit.unitId,
              stage: CroppingStage.preBudgetAdmission,
              decision: RetainDecision.dropMandatoryOverflow,
              reason: 'required_world_info_budget_exceeded',
            ),
          ],
        );
      }
      globalRemaining -= cost;
      if (!unit.ignoreWorldbookBudget) {
        if (policyRemaining != null) policyRemaining = policyRemaining - cost;
        if (bookLimit != null) {
          bookRemaining[unit.worldbookId!] = bookLimit - cost;
        }
      }
      decide(
        unit,
        true,
        unit.ignoreWorldbookBudget
            ? 'world_info_ignore_subbudget'
            : 'required_world_info_admitted',
      );
    }
    for (final unit in worldbookUnits.where(
      (u) =>
          (!enforceRequired || u.retention != PromptRetention.required) &&
          !u.ignoreWorldbookBudget,
    )) {
      final cost = costs[unit.unitId]!;
      final bookLimit = bookRemaining[unit.worldbookId];
      final retained =
          cost <= globalRemaining &&
          (policyRemaining == null || cost <= policyRemaining) &&
          (bookLimit == null || cost <= bookLimit);
      if (retained) {
        globalRemaining -= cost;
        if (policyRemaining != null) policyRemaining = policyRemaining - cost;
        if (bookLimit != null) {
          bookRemaining[unit.worldbookId!] = bookLimit - cost;
        }
      }
      decide(
        unit,
        retained,
        retained ? 'world_info_budget_admitted' : 'world_info_budget_exceeded',
      );
    }
    return CompiledPromptPlan(
      candidateDigest: candidates.digest,
      sourceSnapshots: candidates.sourceSnapshots,
      speakerRef: candidates.speakerRef,
      selectedUnits: candidates.units
          .where((u) => selected.contains(u.unitId))
          .toList(),
      emissions: candidates.emissions
          .where((e) => selected.contains(e.unitId))
          .toList(),
      budgetSnapshotDigest: budget.budgetSnapshotDigest,
      costsDigest: budget.costsDigest,
      layoutHistoryDigest: budget.layoutHistoryDigest,
      requiresCompaction: budget.requiresCompaction,
      admissionTrace: trace,
    );
  }

  int _compareCompiledPriority(
    CompiledPromptUnit a,
    CompiledPromptUnit b, {
    required bool enforceRequired,
  }) {
    final mandatory = !enforceRequired
        ? 0
        : _boolDescending(
            a.retention == PromptRetention.required,
          ).compareTo(_boolDescending(b.retention == PromptRetention.required));
    if (mandatory != 0) return mandatory;
    final ignore = _boolDescending(
      a.ignoreWorldbookBudget,
    ).compareTo(_boolDescending(b.ignoreWorldbookBudget));
    if (ignore != 0) return ignore;
    final tier = _tierPrecedence(
      a.budgetTier,
    ).compareTo(_tierPrecedence(b.budgetTier));
    if (tier != 0) return tier;
    final order = a.injectionOrder.compareTo(b.injectionOrder);
    if (order != 0) return order;
    final source = a.sourceOrder.compareTo(b.sourceOrder);
    return source != 0 ? source : a.unitId.compareTo(b.unitId);
  }

  int _boolDescending(bool value) => value ? 0 : 1;

  int _tierPrecedence(ExecutionBudgetTier tier) => tier.index;
}
