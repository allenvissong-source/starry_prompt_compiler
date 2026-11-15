// inside this package. All class / enum / field / literal names remain
// byte-identical to the source.

class WorldInfoBudgetPlan {
  const WorldInfoBudgetPlan({
    this.enabled = false,
    this.percent = 0.25,
    this.capTokens,
    this.minTokens = 0,
  });

  final bool enabled;
  final double percent;
  final int? capTokens;
  final int minTokens;

  int? resolveBudgetTokens(int? availableInputTokens) {
    if (!enabled || availableInputTokens == null) {
      return null;
    }
    final raw = (availableInputTokens * percent).floor();
    final minApplied = raw < minTokens ? minTokens : raw;
    final cap = capTokens;
    if (cap == null) {
      return minApplied;
    }
    return minApplied > cap ? cap : minApplied;
  }
}

enum ExecutionSourceKind {
  marker,
  promptBlock,
  persona,
  authorNote,
  worldInfoEntry,
  characterCore,
  characterDepthPrompt,
}

enum ExecutionInsertionMode {
  // Planner uses replaceMarker as a shell scaffold anchor. Marker units define
  // insertion points in shellSequence but do not emit standalone prompt text.
  replaceMarker,
  relativeBefore,
  relativeAfter,
  beforeHistory,
  afterHistory,
  historySplice,
  authorNoteTop,
  authorNoteBottom,
  outlet,
}

enum ExecutionBudgetTier { mandatory, high, normal, low }

enum PromptSemanticKind { identity, persona, knowledge, instruction, example }

enum ExecutionDisableSource {
  blockConfig,
  sessionOverlay,
  characterOverlay,
  generationTrigger,
  overridePolicy,
  missingAnchor,
}

enum ExecutionTraceStage { filtering, override, routing, budget }

class ResolvedExecutionUnit {
  const ResolvedExecutionUnit({
    required this.id,
    required this.sourceKind,
    required this.sourceRef,
    required this.enabled,
    required this.contentTemplate,
    required this.role,
    required this.insertionMode,
    this.sourceOrder = 0,
    this.hasExplicitAnchor = false,
    this.markerId,
    this.anchorId,
    this.depth,
    this.injectionOrder = 0,
    this.generationTriggers = const <String>[],
    this.locked = false,
    this.forbidOverride = false,
    this.ignoreBudget = false,
    this.mandatory = false,
    this.budgetTier = ExecutionBudgetTier.normal,
    this.disableSource,
    this.disableReason,
    this.semanticKind,
  });

  final String id;
  final ExecutionSourceKind sourceKind;
  final String sourceRef;
  final bool enabled;
  final String contentTemplate;
  final String role;
  final ExecutionInsertionMode insertionMode;
  final int sourceOrder;
  final bool hasExplicitAnchor;
  final String? markerId;
  final String? anchorId;
  final int? depth;
  final int injectionOrder;
  final List<String> generationTriggers;
  final bool locked;
  final bool forbidOverride;
  final bool ignoreBudget;
  final bool mandatory;
  final ExecutionBudgetTier budgetTier;
  final ExecutionDisableSource? disableSource;
  final String? disableReason;
  final PromptSemanticKind? semanticKind;

  ResolvedExecutionUnit copyWith({
    String? id,
    ExecutionSourceKind? sourceKind,
    String? sourceRef,
    bool? enabled,
    String? contentTemplate,
    String? role,
    ExecutionInsertionMode? insertionMode,
    int? sourceOrder,
    bool? hasExplicitAnchor,
    String? markerId,
    String? anchorId,
    int? depth,
    int? injectionOrder,
    List<String>? generationTriggers,
    bool? locked,
    bool? forbidOverride,
    bool? ignoreBudget,
    bool? mandatory,
    ExecutionBudgetTier? budgetTier,
    ExecutionDisableSource? disableSource,
    String? disableReason,
    PromptSemanticKind? semanticKind,
  }) {
    return ResolvedExecutionUnit(
      id: id ?? this.id,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceRef: sourceRef ?? this.sourceRef,
      enabled: enabled ?? this.enabled,
      contentTemplate: contentTemplate ?? this.contentTemplate,
      role: role ?? this.role,
      insertionMode: insertionMode ?? this.insertionMode,
      sourceOrder: sourceOrder ?? this.sourceOrder,
      hasExplicitAnchor: hasExplicitAnchor ?? this.hasExplicitAnchor,
      markerId: markerId ?? this.markerId,
      anchorId: anchorId ?? this.anchorId,
      depth: depth ?? this.depth,
      injectionOrder: injectionOrder ?? this.injectionOrder,
      generationTriggers: generationTriggers ?? this.generationTriggers,
      locked: locked ?? this.locked,
      forbidOverride: forbidOverride ?? this.forbidOverride,
      ignoreBudget: ignoreBudget ?? this.ignoreBudget,
      mandatory: mandatory ?? this.mandatory,
      budgetTier: budgetTier ?? this.budgetTier,
      disableSource: disableSource ?? this.disableSource,
      disableReason: disableReason ?? this.disableReason,
      semanticKind: semanticKind ?? this.semanticKind,
    );
  }
}

class PromptDisableOverlay {
  const PromptDisableOverlay({
    this.disabledUnitIds = const <String>[],
    this.disabledSourceRefs = const <String>[],
  });

  final List<String> disabledUnitIds;
  final List<String> disabledSourceRefs;

  bool matches(ResolvedExecutionUnit unit) {
    if (disabledUnitIds.contains(unit.id)) {
      return true;
    }
    return disabledSourceRefs.contains(unit.sourceRef);
  }
}

class HistorySplicePoint {
  HistorySplicePoint({
    required this.offsetFromEnd,
    required List<ResolvedExecutionUnit> units,
  }) : units = List<ResolvedExecutionUnit>.unmodifiable(units);

  final int offsetFromEnd;
  final List<ResolvedExecutionUnit> units;
}

class ExecutionTraceEntry {
  const ExecutionTraceEntry({
    required this.unitId,
    required this.stage,
    required this.reason,
    this.sourceKind,
    this.sourceRef,
    this.disableSource,
    this.targetUnitId,
    this.anchorId,
    this.outletId,
    this.insertionMode,
  });

  final String unitId;
  final ExecutionTraceStage stage;
  final String reason;
  final ExecutionSourceKind? sourceKind;
  final String? sourceRef;
  final ExecutionDisableSource? disableSource;
  final String? targetUnitId;
  final String? anchorId;
  final String? outletId;
  final ExecutionInsertionMode? insertionMode;
}

class ExecutionOverrideDecision {
  const ExecutionOverrideDecision({
    required this.targetUnitId,
    required this.overrideSourceId,
    required this.applied,
    required this.reason,
  });

  final String targetUnitId;
  final String overrideSourceId;
  final bool applied;
  final String reason;
}

class PromptExecutionPlan {
  PromptExecutionPlan({
    required List<ResolvedExecutionUnit> shellSequence,
    required List<HistorySplicePoint> historySplicePoints,
    required List<ResolvedExecutionUnit> disabledUnits,
    Map<String, List<ResolvedExecutionUnit>> outletMap =
        const <String, List<ResolvedExecutionUnit>>{},
    this.worldInfoBudgetPlan = const WorldInfoBudgetPlan(),
    List<ExecutionTraceEntry> trace = const <ExecutionTraceEntry>[],
  }) : shellSequence = List<ResolvedExecutionUnit>.unmodifiable(shellSequence),
       historySplicePoints = List<HistorySplicePoint>.unmodifiable(
         historySplicePoints,
       ),
       disabledUnits = List<ResolvedExecutionUnit>.unmodifiable(disabledUnits),
       outletMap = Map<String, List<ResolvedExecutionUnit>>.unmodifiable(
         outletMap.map(
           (key, value) =>
               MapEntry(key, List<ResolvedExecutionUnit>.unmodifiable(value)),
         ),
       ),
       trace = List<ExecutionTraceEntry>.unmodifiable(trace);

  final List<ResolvedExecutionUnit> shellSequence;
  final List<HistorySplicePoint> historySplicePoints;
  final List<ResolvedExecutionUnit> disabledUnits;
  final Map<String, List<ResolvedExecutionUnit>> outletMap;
  final WorldInfoBudgetPlan worldInfoBudgetPlan;
  final List<ExecutionTraceEntry> trace;

  PromptExecutionPlan copyWith({
    List<ResolvedExecutionUnit>? shellSequence,
    List<HistorySplicePoint>? historySplicePoints,
    List<ResolvedExecutionUnit>? disabledUnits,
    Map<String, List<ResolvedExecutionUnit>>? outletMap,
    WorldInfoBudgetPlan? worldInfoBudgetPlan,
    List<ExecutionTraceEntry>? trace,
  }) {
    return PromptExecutionPlan(
      shellSequence: shellSequence ?? this.shellSequence,
      historySplicePoints: historySplicePoints ?? this.historySplicePoints,
      disabledUnits: disabledUnits ?? this.disabledUnits,
      outletMap: outletMap ?? this.outletMap,
      worldInfoBudgetPlan: worldInfoBudgetPlan ?? this.worldInfoBudgetPlan,
      trace: trace ?? this.trace,
    );
  }
}
