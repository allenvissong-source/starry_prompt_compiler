// Package-internal service: WorldInfoBudgetAdmissionService.
//
// Provenance: verbatim copy of
//   lib/features/chat_character/domain/services/world_info_budget_admission.dart
// Imports rewritten to relative in-package model paths (2 rewrites).
// Class / method / field names byte-identical to the Starry source.
// The `const` ctor takes no Ports (Admission is already pure).
import '../models/message_budget_models.dart';
import '../models/prompt_execution_models.dart';

class WorldInfoBudgetAdmissionResult {
  const WorldInfoBudgetAdmissionResult({
    required this.plan,
    required this.trace,
  });

  final PromptExecutionPlan plan;
  final List<CroppingTrace> trace;
}

class WorldInfoBudgetAdmissionService {
  const WorldInfoBudgetAdmissionService();

  WorldInfoBudgetAdmissionResult admitWorldInfoUnits(
    PromptExecutionPlan plan, {
    Map<String, int> worldbookTokenBudgets = const <String, int>{},
  }) {
    final wiBudget = plan.worldInfoBudgetPlan.resolveBudgetTokens(
      plan.budgetPlan.resolvedAvailableInputTokens,
    );
    if (wiBudget == null && worldbookTokenBudgets.isEmpty) {
      return WorldInfoBudgetAdmissionResult(
        plan: plan,
        trace: const <CroppingTrace>[],
      );
    }

    final wiUnits = <ResolvedExecutionUnit>[
      ...plan.shellSequence.where(
        (unit) => unit.sourceKind == ExecutionSourceKind.worldInfoEntry,
      ),
      ...plan.outletMap.values.expand(
        (units) => units.where(
          (unit) => unit.sourceKind == ExecutionSourceKind.worldInfoEntry,
        ),
      ),
      ...plan.historySplicePoints.expand(
        (point) => point.units.where(
          (unit) => unit.sourceKind == ExecutionSourceKind.worldInfoEntry,
        ),
      ),
    ]..sort(_compareWorldInfoBudgetPriority);

    var remaining = wiBudget;
    final bookRemaining = <String, int>{
      for (final entry in worldbookTokenBudgets.entries)
        entry.key: entry.value < 0 ? 0 : entry.value,
    };
    final trace = <CroppingTrace>[];
    final retainedWorldInfoIds = <String>{};
    for (final unit in wiUnits) {
      final bookBudget = bookRemaining[unit.sourceRef];
      final limit = remaining == null
          ? bookBudget
          : bookBudget == null || remaining < bookBudget
          ? remaining
          : bookBudget;
      final decision = _admitWorldInfoUnit(unit, remainingBudget: limit);
      trace.addAll(decision.trace);
      if (decision.retained) {
        retainedWorldInfoIds.add(unit.id);
        if (!unit.ignoreBudget) {
          if (remaining != null) {
            remaining = (remaining - decision.estimatedTokens).clamp(
              0,
              remaining,
            );
          }
          if (bookBudget != null) {
            bookRemaining[unit.sourceRef] =
                (bookBudget - decision.estimatedTokens).clamp(0, bookBudget);
          }
        }
      }
    }

    final retainedShell = plan.shellSequence
        .where(
          (unit) =>
              unit.sourceKind != ExecutionSourceKind.worldInfoEntry ||
              retainedWorldInfoIds.contains(unit.id),
        )
        .toList(growable: false);
    final retainedSplice = plan.historySplicePoints
        .map((point) {
          final retainedUnits = point.units
              .where(
                (unit) =>
                    unit.sourceKind != ExecutionSourceKind.worldInfoEntry ||
                    retainedWorldInfoIds.contains(unit.id),
              )
              .toList(growable: false);
          if (retainedUnits.isEmpty) {
            return null;
          }
          return HistorySplicePoint(
            offsetFromEnd: point.offsetFromEnd,
            units: retainedUnits,
          );
        })
        .whereType<HistorySplicePoint>()
        .toList(growable: false);
    final retainedOutletMap = <String, List<ResolvedExecutionUnit>>{
      for (final entry in plan.outletMap.entries)
        entry.key: entry.value
            .where(
              (unit) =>
                  unit.sourceKind != ExecutionSourceKind.worldInfoEntry ||
                  retainedWorldInfoIds.contains(unit.id),
            )
            .toList(growable: false),
    }..removeWhere((key, value) => value.isEmpty);

    return WorldInfoBudgetAdmissionResult(
      plan: plan.copyWith(
        shellSequence: retainedShell,
        historySplicePoints: retainedSplice,
        outletMap: retainedOutletMap,
        croppingTrace: <CroppingTrace>[...plan.croppingTrace, ...trace],
      ),
      trace: List<CroppingTrace>.unmodifiable(trace),
    );
  }

  ({bool retained, int estimatedTokens, List<CroppingTrace> trace})
  _admitWorldInfoUnit(
    ResolvedExecutionUnit unit, {
    required int? remainingBudget,
  }) {
    if (unit.sourceKind != ExecutionSourceKind.worldInfoEntry) {
      return (
        retained: true,
        estimatedTokens: 0,
        trace: const <CroppingTrace>[],
      );
    }

    final estimated = _estimateTextTokens(unit.contentTemplate);
    if (unit.ignoreBudget) {
      return (
        retained: true,
        estimatedTokens: estimated,
        trace: <CroppingTrace>[
          CroppingTrace(
            unitId: unit.id,
            stage: CroppingStage.preBudgetAdmission,
            decision: RetainDecision.retain,
            reason: 'world_info_ignore_budget',
          ),
        ],
      );
    }
    if (remainingBudget == null || estimated <= remainingBudget) {
      return (
        retained: true,
        estimatedTokens: estimated,
        trace: <CroppingTrace>[
          CroppingTrace(
            unitId: unit.id,
            stage: CroppingStage.preBudgetAdmission,
            decision: RetainDecision.retain,
            reason: 'world_info_budget_admitted',
          ),
        ],
      );
    }
    return (
      retained: false,
      estimatedTokens: estimated,
      trace: <CroppingTrace>[
        CroppingTrace(
          unitId: unit.id,
          stage: CroppingStage.preBudgetAdmission,
          decision: RetainDecision.dropOverSubBudget,
          reason: 'world_info_budget_exceeded',
        ),
      ],
    );
  }

  int _compareWorldInfoBudgetPriority(
    ResolvedExecutionUnit a,
    ResolvedExecutionUnit b,
  ) {
    final mandatoryCompare = _boolDescending(
      a.mandatory,
    ).compareTo(_boolDescending(b.mandatory));
    if (mandatoryCompare != 0) {
      return mandatoryCompare;
    }
    final ignoreCompare = _boolDescending(
      a.ignoreBudget,
    ).compareTo(_boolDescending(b.ignoreBudget));
    if (ignoreCompare != 0) {
      return ignoreCompare;
    }
    final tierCompare = _tierPrecedence(
      a.budgetTier,
    ).compareTo(_tierPrecedence(b.budgetTier));
    if (tierCompare != 0) {
      return tierCompare;
    }
    final orderCompare = a.injectionOrder.compareTo(b.injectionOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
    if (sourceCompare != 0) {
      return sourceCompare;
    }
    return a.id.compareTo(b.id);
  }

  int _boolDescending(bool value) => value ? 0 : 1;

  int _tierPrecedence(ExecutionBudgetTier tier) {
    return switch (tier) {
      ExecutionBudgetTier.mandatory => 0,
      ExecutionBudgetTier.high => 1,
      ExecutionBudgetTier.normal => 2,
      ExecutionBudgetTier.low => 3,
    };
  }

  int _estimateTextTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }
    return (normalized.length / 4).ceil() + 4;
  }
}
