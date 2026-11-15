// Package-internal service: PromptExecutionPlanner.
//
// Provenance: verbatim copy of
//   lib/features/chat_character/domain/services/prompt_execution_planner.dart
// Imports rewritten to relative in-package model paths (7 rewrites).
// Class / enum / field / method names byte-identical to the Starry source.
// The `const` ctor takes no Ports (Planner is already pure: no clock,
// random, locale, or logger surface).
import '../models/session_prompt_context.dart';
import '../models/world_info.dart';
import '../models/prompt_execution_models.dart';
import '../models/persona.dart';
import '../models/prompt_block.dart';
import '../models/prompt_manager.dart';
import '../models/character_entities.dart';
import '../models/domain_prompt_inputs.dart';

class PromptExecutionPlanner {
  const PromptExecutionPlanner();

  PromptExecutionPlan buildDomainPlan(DomainPromptPlanningInput input) {
    final units = _collectUnits(input);
    final filtering = _filterUnits(
      units,
      generationType: input.generationType,
      sessionOverlay: _mergeOverlay(
        input.promptContext.sessionDisableOverlay,
        input.sessionDisableOverlay,
      ),
      characterOverlay: _mergeOverlay(
        input.promptContext.characterDisableOverlay,
        input.characterDisableOverlay,
      ),
    );
    final overrideResolution = _applyOverrides(
      filtering.enabledUnits,
      persona: input.persona,
    );
    final shellSequence = _buildShellSequence(overrideResolution.units);
    final outletValidation = _validateOutletAnchors(
      shellSequence: shellSequence,
      outletMap: _buildOutletMap(overrideResolution.units),
    );
    final historySplicePoints = _buildHistorySplicePoints(
      overrideResolution.units,
    );
    return PromptExecutionPlan(
      shellSequence: shellSequence,
      historySplicePoints: historySplicePoints,
      disabledUnits: <ResolvedExecutionUnit>[
        ...filtering.disabledUnits,
        ...outletValidation.disabledUnits,
      ],
      outletMap: outletValidation.outletMap,
      worldInfoBudgetPlan: input.worldInfoBudgetPlan,
      trace: <ExecutionTraceEntry>[
        ...filtering.trace,
        ...overrideResolution.trace,
        ...outletValidation.trace,
        ..._buildRoutingTrace(
          shellSequence,
          outletValidation.outletMap,
          historySplicePoints,
        ),
      ],
    );
  }

  List<ResolvedExecutionUnit> _collectUnits(DomainPromptPlanningInput input) {
    final units = <ResolvedExecutionUnit>[
      if (input.identityContent case final identity?)
        ResolvedExecutionUnit(
          id: '${identity.resourceId}:identity',
          sourceKind: ExecutionSourceKind.characterCore,
          sourceRef: identity.resourceId,
          enabled: true,
          contentTemplate: identity.text,
          role: 'system',
          insertionMode: ExecutionInsertionMode.beforeHistory,
          mandatory: true,
          budgetTier: ExecutionBudgetTier.mandatory,
          semanticKind: PromptSemanticKind.identity,
          locked: true,
          forbidOverride: true,
        ),
      ..._collectPromptBlockUnits(input.promptBlocks, input.character),
      ..._collectPersonaUnits(input.persona),
      ..._collectAuthorNoteUnits(
        input.promptContext.authorNotePolicy,
        historyLength: input.historyLength,
      ),
      ..._collectWorldInfoUnits(
        input.worldInfoEntries,
        mode: input.worldInfoPlanningMode,
      ),
      if (input.character != null)
        ..._collectCharacterDepthPromptUnits(input.character!),
    ];
    return units;
  }

  List<ResolvedExecutionUnit> _collectPromptBlockUnits(
    List<PromptBlock> blocks,
    Character? character,
  ) {
    final orderedBlocks = List<PromptBlock>.from(blocks)
      ..sort(_comparePromptBlocks);
    final markerOrders = _promptMarkerOrders(orderedBlocks);
    final historyMarkerOrder = markerOrders['history'];
    final units = <ResolvedExecutionUnit>[];

    for (var index = 0; index < orderedBlocks.length; index++) {
      final block = orderedBlocks[index];
      final sourceOrder = block.priority.sortOrder;

      if (block.isMarker || _isHistoryMarker(block)) {
        units.add(
          ResolvedExecutionUnit(
            id: block.id,
            sourceKind: ExecutionSourceKind.marker,
            sourceRef: block.provenance.identifier ?? block.name,
            enabled: block.enabled,
            contentTemplate: '',
            role: 'system',
            insertionMode: ExecutionInsertionMode.replaceMarker,
            sourceOrder: sourceOrder,
            markerId: _markerIdentityForBlock(block),
            generationTriggers: block.activation.generationTriggers,
          ),
        );
        continue;
      }

      final explicitAnchorId = _explicitAnchorId(
        block.placement.anchor ?? 'relative',
      );
      final insertionMode = _blockInsertionMode(
        block,
        sourceOrder: sourceOrder,
        historyMarkerOrder: historyMarkerOrder,
        explicitAnchorId: explicitAnchorId,
        markerOrders: markerOrders,
      );

      units.add(
        ResolvedExecutionUnit(
          id: block.id,
          sourceKind: _characterBlockContent(block, character)
              ? ExecutionSourceKind.characterCore
              : ExecutionSourceKind.promptBlock,
          sourceRef: _characterBlockContent(block, character)
              ? character!.id
              : (block.promptProfileId ??
                    block.provenance.identifier ??
                    block.name),
          enabled: block.enabled,
          contentTemplate: _resolveBlockTemplate(block, character),
          role: block.role ?? 'system',
          insertionMode: insertionMode,
          sourceOrder: sourceOrder,
          hasExplicitAnchor: explicitAnchorId != null,
          markerId: _markerIdentityForBlock(block),
          anchorId: _anchorIdForBlock(
            block,
            insertionMode: insertionMode,
            explicitAnchorId: explicitAnchorId,
          ),
          depth: insertionMode == ExecutionInsertionMode.historySplice
              ? (block.placement.depth ?? 0)
              : null,
          injectionOrder:
              block.priority.injectionOrder ?? block.priority.sortOrder,
          generationTriggers: block.activation.generationTriggers,
          locked: block.protection.locked,
          forbidOverride: block.protection.forbidOverride,
          mandatory:
              _isMandatoryPromptBlock(block) ||
              (_characterBlockContent(block, character) &&
                  block.kindName != 'exampleMessages' &&
                  block.kindName != 'postHistoryInstructions'),
          budgetTier: _budgetTierForBlock(block),
          semanticKind: block.kindName == 'exampleMessages'
              ? PromptSemanticKind.example
              : _characterBlockContent(block, character) &&
                    block.kindName != 'postHistoryInstructions'
              ? PromptSemanticKind.identity
              : PromptSemanticKind.instruction,
        ),
      );
    }

    return units;
  }

  List<ResolvedExecutionUnit> _collectPersonaUnits(Persona? persona) {
    if (persona == null || !_personaHasContent(persona)) {
      return const <ResolvedExecutionUnit>[];
    }
    if (persona.descriptionSettings.position ==
        PersonaDescriptionPosition.inSystemPrompt) {
      return const <ResolvedExecutionUnit>[];
    }

    final insertionMode = switch (persona.descriptionSettings.position) {
      PersonaDescriptionPosition.atDepth =>
        ExecutionInsertionMode.historySplice,
      PersonaDescriptionPosition.beforeChar =>
        ExecutionInsertionMode.relativeBefore,
      PersonaDescriptionPosition.afterChar =>
        ExecutionInsertionMode.relativeAfter,
      PersonaDescriptionPosition.topAN => ExecutionInsertionMode.authorNoteTop,
      PersonaDescriptionPosition.bottomAN =>
        ExecutionInsertionMode.authorNoteBottom,
      _ => ExecutionInsertionMode.relativeAfter,
    };

    return <ResolvedExecutionUnit>[
      ResolvedExecutionUnit(
        id: 'persona:${persona.id}',
        sourceKind: ExecutionSourceKind.persona,
        sourceRef: persona.id,
        enabled: true,
        contentTemplate: _buildPersonaContent(persona),
        role: _personaRole(persona),
        insertionMode: insertionMode,
        sourceOrder: _personaSourceOrder(persona),
        hasExplicitAnchor: true,
        markerId: 'persona',
        anchorId: _personaAnchorId(persona),
        depth: insertionMode == ExecutionInsertionMode.historySplice
            ? persona.descriptionSettings.depth
            : null,
      ),
    ];
  }

  List<ResolvedExecutionUnit> _collectAuthorNoteUnits(
    AuthorNotePolicy policy, {
    required int historyLength,
  }) {
    if (!_shouldInjectAuthorNote(policy, historyLength: historyLength)) {
      return const <ResolvedExecutionUnit>[];
    }

    final insertionMode = _authorNoteInsertionMode(policy.placement);
    return <ResolvedExecutionUnit>[
      ResolvedExecutionUnit(
        id: 'author_note',
        sourceKind: ExecutionSourceKind.authorNote,
        sourceRef: 'session_prompt_context.author_note_policy',
        enabled: true,
        contentTemplate: '[Author\'s Note]\n${policy.text}',
        role: policy.role,
        insertionMode: insertionMode,
        sourceOrder: 1100,
        hasExplicitAnchor: true,
        markerId: 'authorNote',
        anchorId: _authorNoteAnchorId(insertionMode),
        depth: insertionMode == ExecutionInsertionMode.historySplice
            ? policy.depth
            : null,
        injectionOrder: 1,
      ),
    ];
  }

  List<ResolvedExecutionUnit> _collectWorldInfoUnits(
    List<WorldInfoEntry> entries, {
    required WorldInfoPlanningMode mode,
  }) {
    final units = <ResolvedExecutionUnit>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final flat = mode == WorldInfoPlanningMode.flatInjections;
      final insertionMode = flat
          ? ExecutionInsertionMode.beforeHistory
          : switch (entry.position) {
              WorldInfoPosition.before => ExecutionInsertionMode.relativeBefore,
              WorldInfoPosition.atDepth => ExecutionInsertionMode.historySplice,
              WorldInfoPosition.anTop => ExecutionInsertionMode.authorNoteTop,
              WorldInfoPosition.anBottom =>
                ExecutionInsertionMode.authorNoteBottom,
              WorldInfoPosition.outlet => ExecutionInsertionMode.outlet,
              WorldInfoPosition.emTop => ExecutionInsertionMode.relativeBefore,
              WorldInfoPosition.emBottom =>
                ExecutionInsertionMode.relativeAfter,
              WorldInfoPosition.after => ExecutionInsertionMode.relativeAfter,
            };

      units.add(
        ResolvedExecutionUnit(
          id: 'wi:${entry.worldbookId}:${entry.id}',
          sourceKind: ExecutionSourceKind.worldInfoEntry,
          sourceRef: entry.worldbookId,
          enabled: entry.enabled,
          contentTemplate: flat
              ? entry.content
              : '[${entry.comment.isNotEmpty ? entry.comment : "World Info"}]\n${entry.content}',
          role: flat ? 'system' : _worldInfoRole(entry.role),
          insertionMode: insertionMode,
          sourceOrder: 1200 + index,
          hasExplicitAnchor: !flat,
          anchorId: flat ? null : _anchorIdForWorldInfo(entry, insertionMode),
          depth: insertionMode == ExecutionInsertionMode.historySplice
              ? entry.depth
              : null,
          injectionOrder: entry.insertionOrder,
          generationTriggers: flat
              ? const []
              : entry.runtimePolicy.activation.generationTriggers,
          ignoreBudget: entry.ignoreBudget,
          budgetTier: _budgetTierForWorldInfoEntry(entry),
        ),
      );
    }
    return units;
  }

  List<ResolvedExecutionUnit> _collectCharacterDepthPromptUnits(
    Character character,
  ) {
    final depthPrompt = character.depthPrompt;
    if (depthPrompt == null || depthPrompt.text.trim().isEmpty) {
      return const <ResolvedExecutionUnit>[];
    }
    return <ResolvedExecutionUnit>[
      ResolvedExecutionUnit(
        id: 'character_depth_prompt:${character.id}',
        sourceKind: ExecutionSourceKind.characterDepthPrompt,
        sourceRef: character.id,
        enabled: true,
        contentTemplate: depthPrompt.text,
        role: depthPrompt.role,
        insertionMode: ExecutionInsertionMode.historySplice,
        sourceOrder: 1300,
        hasExplicitAnchor: true,
        anchorId: 'history',
        depth: depthPrompt.depth,
        injectionOrder: 2,
      ),
    ];
  }

  ({
    List<ResolvedExecutionUnit> enabledUnits,
    List<ResolvedExecutionUnit> disabledUnits,
    List<ExecutionTraceEntry> trace,
  })
  _filterUnits(
    List<ResolvedExecutionUnit> units, {
    required String generationType,
    required PromptDisableOverlay sessionOverlay,
    required PromptDisableOverlay characterOverlay,
  }) {
    final enabledUnits = <ResolvedExecutionUnit>[];
    final disabledUnits = <ResolvedExecutionUnit>[];
    final trace = <ExecutionTraceEntry>[];
    for (final unit in units) {
      if (!unit.enabled) {
        final disabled = unit.copyWith(
          disableSource: ExecutionDisableSource.blockConfig,
          disableReason: 'block_disabled',
        );
        disabledUnits.add(disabled);
        trace.add(_disabledTrace(disabled));
        continue;
      }
      if (sessionOverlay.matches(unit)) {
        final disabled = unit.copyWith(
          disableSource: ExecutionDisableSource.sessionOverlay,
          disableReason: 'session_disable_overlay',
        );
        disabledUnits.add(disabled);
        trace.add(_disabledTrace(disabled));
        continue;
      }
      if (characterOverlay.matches(unit)) {
        final disabled = unit.copyWith(
          disableSource: ExecutionDisableSource.characterOverlay,
          disableReason: 'character_disable_overlay',
        );
        disabledUnits.add(disabled);
        trace.add(_disabledTrace(disabled));
        continue;
      }
      if (!_supportsGenerationType(unit, generationType)) {
        final disabled = unit.copyWith(
          disableSource: ExecutionDisableSource.generationTrigger,
          disableReason: 'generation_trigger_mismatch',
        );
        disabledUnits.add(disabled);
        trace.add(_disabledTrace(disabled));
        continue;
      }
      enabledUnits.add(unit);
    }
    return (
      enabledUnits: enabledUnits,
      disabledUnits: disabledUnits,
      trace: List<ExecutionTraceEntry>.unmodifiable(trace),
    );
  }

  ({
    List<ResolvedExecutionUnit> units,
    List<ExecutionOverrideDecision> decisions,
    List<ExecutionTraceEntry> trace,
  })
  _applyOverrides(
    List<ResolvedExecutionUnit> units, {
    required Persona? persona,
  }) {
    if (persona == null) {
      return (
        units: units,
        decisions: const <ExecutionOverrideDecision>[],
        trace: const <ExecutionTraceEntry>[],
      );
    }

    final updatedUnits = List<ResolvedExecutionUnit>.from(units);
    final decisions = <ExecutionOverrideDecision>[];

    _applySystemPromptOverrides(updatedUnits, decisions, persona: persona);
    _applyPostHistoryOverrides(updatedUnits, decisions, persona: persona);

    return (
      units: List<ResolvedExecutionUnit>.unmodifiable(updatedUnits),
      decisions: List<ExecutionOverrideDecision>.unmodifiable(decisions),
      trace: List<ExecutionTraceEntry>.unmodifiable(
        decisions.map(
          (decision) => ExecutionTraceEntry(
            unitId: decision.overrideSourceId,
            stage: ExecutionTraceStage.override,
            reason: decision.reason,
            targetUnitId: decision.targetUnitId,
          ),
        ),
      ),
    );
  }

  void _applySystemPromptOverrides(
    List<ResolvedExecutionUnit> units,
    List<ExecutionOverrideDecision> decisions, {
    required Persona persona,
  }) {
    final targetIndex = units.indexWhere(
      (unit) =>
          (unit.sourceKind == ExecutionSourceKind.promptBlock ||
              unit.sourceKind == ExecutionSourceKind.characterCore) &&
          unit.markerId == 'systemPrompt',
    );
    if (targetIndex < 0) {
      return;
    }
    final target = units[targetIndex];
    final blocksOverride = _blocksOverride(target);

    final systemOverride = (persona.systemPromptOverride ?? '').trim();
    if (systemOverride.isNotEmpty) {
      if (blocksOverride) {
        decisions.add(
          ExecutionOverrideDecision(
            targetUnitId: target.id,
            overrideSourceId: 'persona:${persona.id}:systemPromptOverride',
            applied: false,
            reason: 'locked_or_forbid_override',
          ),
        );
      } else {
        units[targetIndex] = target.copyWith(
          contentTemplate: systemOverride,
          sourceKind: ExecutionSourceKind.persona,
          sourceRef: persona.id,
          semanticKind: PromptSemanticKind.instruction,
        );
        decisions.add(
          ExecutionOverrideDecision(
            targetUnitId: target.id,
            overrideSourceId: 'persona:${persona.id}:systemPromptOverride',
            applied: true,
            reason: 'persona_system_prompt_override',
          ),
        );
      }
      return;
    }

    final shouldAugment =
        persona.descriptionSettings.position ==
            PersonaDescriptionPosition.inSystemPrompt &&
        persona.description.trim().isNotEmpty;
    if (!shouldAugment) {
      return;
    }
    if (blocksOverride) {
      decisions.add(
        ExecutionOverrideDecision(
          targetUnitId: target.id,
          overrideSourceId: 'persona:${persona.id}:inSystemPrompt',
          applied: false,
          reason: 'locked_or_forbid_override',
        ),
      );
      return;
    }

    final personaContent = 'User persona:\n${persona.description.trim()}';
    // Persona has its own source even when its position is the system region.
    // It must not be mislabeled as character identity or disappear with it.
    units.insert(
      targetIndex + 1,
      ResolvedExecutionUnit(
        id: 'persona:${persona.id}:inSystemPrompt',
        sourceKind: ExecutionSourceKind.persona,
        sourceRef: persona.id,
        enabled: true,
        contentTemplate: personaContent,
        role: target.role,
        insertionMode: ExecutionInsertionMode.relativeAfter,
        sourceOrder: target.sourceOrder,
        hasExplicitAnchor: true,
        markerId: 'persona',
        anchorId: target.markerId,
        mandatory: target.mandatory,
        budgetTier: target.budgetTier,
        semanticKind: PromptSemanticKind.persona,
      ),
    );
    decisions.add(
      ExecutionOverrideDecision(
        targetUnitId: target.id,
        overrideSourceId: 'persona:${persona.id}:inSystemPrompt',
        applied: true,
        reason: 'persona_description_in_system_prompt',
      ),
    );
  }

  void _applyPostHistoryOverrides(
    List<ResolvedExecutionUnit> units,
    List<ExecutionOverrideDecision> decisions, {
    required Persona persona,
  }) {
    final overrideText = (persona.postHistoryInstructions ?? '').trim();
    if (overrideText.isEmpty) {
      return;
    }

    final targetIndex = units.indexWhere(
      (unit) =>
          (unit.sourceKind == ExecutionSourceKind.promptBlock ||
              unit.sourceKind == ExecutionSourceKind.characterCore) &&
          unit.markerId == 'postHistoryInstructions',
    );
    if (targetIndex < 0) {
      return;
    }
    final target = units[targetIndex];
    if (_blocksOverride(target)) {
      decisions.add(
        ExecutionOverrideDecision(
          targetUnitId: target.id,
          overrideSourceId: 'persona:${persona.id}:postHistoryInstructions',
          applied: false,
          reason: 'locked_or_forbid_override',
        ),
      );
      return;
    }

    units[targetIndex] = target.copyWith(
      contentTemplate: overrideText,
      sourceKind: ExecutionSourceKind.persona,
      sourceRef: persona.id,
      semanticKind: PromptSemanticKind.instruction,
    );
    decisions.add(
      ExecutionOverrideDecision(
        targetUnitId: target.id,
        overrideSourceId: 'persona:${persona.id}:postHistoryInstructions',
        applied: true,
        reason: 'persona_post_history_override',
      ),
    );
  }

  List<ResolvedExecutionUnit> _buildShellSequence(
    List<ResolvedExecutionUnit> enabledUnits,
  ) {
    final shellUnits = enabledUnits
        .where(
          (unit) =>
              unit.insertionMode != ExecutionInsertionMode.historySplice &&
              unit.insertionMode != ExecutionInsertionMode.outlet,
        )
        .toList(growable: false);
    final markerUnits =
        shellUnits
            .where((unit) => unit.sourceKind == ExecutionSourceKind.marker)
            .toList(growable: true)
          ..sort(_compareShellSourceOrder);
    final scaffoldUnits =
        shellUnits
            .where(
              (unit) =>
                  unit.sourceKind != ExecutionSourceKind.marker &&
                  _isScaffoldShellUnit(unit),
            )
            .toList(growable: true)
          ..sort(_compareShellSourceOrder);
    final anchoredUnits =
        shellUnits
            .where(
              (unit) =>
                  !_isScaffoldShellUnit(unit) &&
                  unit.sourceKind != ExecutionSourceKind.marker,
            )
            .toList(growable: true)
          ..sort(_compareAnchoredShellUnits);

    final sequence = <ResolvedExecutionUnit>[...markerUnits, ...scaffoldUnits]
      ..sort(_compareShellSourceOrder);

    if (_requiresSyntheticAuthorNoteMarker(enabledUnits) &&
        !_containsMarker(sequence, 'authorNote')) {
      _insertSyntheticMarkerBeforeAnchor(
        sequence,
        _syntheticAuthorNoteMarker(),
        preferredAnchorId: 'history',
      );
    }
    if (!_containsMarker(sequence, 'history')) {
      sequence.add(_syntheticHistoryMarker());
    }

    for (final unit in anchoredUnits) {
      _insertAnchoredShellUnit(sequence, unit);
    }

    return List<ResolvedExecutionUnit>.unmodifiable(sequence);
  }

  Map<String, List<ResolvedExecutionUnit>> _buildOutletMap(
    List<ResolvedExecutionUnit> enabledUnits,
  ) {
    final grouped = <String, List<ResolvedExecutionUnit>>{};
    for (final unit in enabledUnits.where(
      (item) => item.insertionMode == ExecutionInsertionMode.outlet,
    )) {
      final outletId = (unit.anchorId ?? '').trim();
      if (outletId.isEmpty) {
        continue;
      }
      grouped.putIfAbsent(outletId, () => <ResolvedExecutionUnit>[]).add(unit);
    }
    final sortedKeys = grouped.keys.toList(growable: false)..sort();
    return <String, List<ResolvedExecutionUnit>>{
      for (final key in sortedKeys)
        key: List<ResolvedExecutionUnit>.unmodifiable(
          grouped[key]!..sort(_compareOutletUnits),
        ),
    };
  }

  ({
    Map<String, List<ResolvedExecutionUnit>> outletMap,
    List<ResolvedExecutionUnit> disabledUnits,
    List<ExecutionTraceEntry> trace,
  })
  _validateOutletAnchors({
    required List<ResolvedExecutionUnit> shellSequence,
    required Map<String, List<ResolvedExecutionUnit>> outletMap,
  }) {
    final validatedMap = <String, List<ResolvedExecutionUnit>>{};
    final disabledUnits = <ResolvedExecutionUnit>[];
    final trace = <ExecutionTraceEntry>[];

    for (final entry in outletMap.entries) {
      final outletId = entry.key.trim();
      if (_containsMarker(shellSequence, outletId)) {
        validatedMap[outletId] = entry.value;
        continue;
      }
      for (final unit in entry.value) {
        final disabled = unit.copyWith(
          disableSource: ExecutionDisableSource.missingAnchor,
          disableReason: 'missing_outlet_anchor',
        );
        disabledUnits.add(disabled);
        trace.add(
          ExecutionTraceEntry(
            unitId: disabled.id,
            stage: ExecutionTraceStage.filtering,
            reason: 'missing_outlet_anchor',
            sourceKind: disabled.sourceKind,
            sourceRef: disabled.sourceRef,
            disableSource: disabled.disableSource,
            anchorId: disabled.anchorId,
            outletId: outletId,
            insertionMode: disabled.insertionMode,
          ),
        );
      }
    }

    return (
      outletMap: Map<String, List<ResolvedExecutionUnit>>.unmodifiable(
        validatedMap.map(
          (key, value) =>
              MapEntry(key, List<ResolvedExecutionUnit>.unmodifiable(value)),
        ),
      ),
      disabledUnits: List<ResolvedExecutionUnit>.unmodifiable(disabledUnits),
      trace: List<ExecutionTraceEntry>.unmodifiable(trace),
    );
  }

  List<HistorySplicePoint> _buildHistorySplicePoints(
    List<ResolvedExecutionUnit> enabledUnits,
  ) {
    final grouped = <int, List<ResolvedExecutionUnit>>{};
    for (final unit in enabledUnits.where(
      (item) => item.insertionMode == ExecutionInsertionMode.historySplice,
    )) {
      final offset = unit.depth ?? 0;
      grouped.putIfAbsent(offset, () => <ResolvedExecutionUnit>[]).add(unit);
    }
    final offsets = grouped.keys.toList(growable: false)..sort();
    return offsets
        .map(
          (offset) => HistorySplicePoint(
            offsetFromEnd: offset,
            units: grouped[offset]!..sort(_compareSpliceUnits),
          ),
        )
        .toList(growable: false);
  }

  void _insertAnchoredShellUnit(
    List<ResolvedExecutionUnit> sequence,
    ResolvedExecutionUnit unit,
  ) {
    final anchorId = _resolveAnchorId(sequence, unit);
    final insertionMode = _effectiveInsertionModeForResolvedAnchor(
      unit,
      anchorId,
    );
    if (anchorId == null) {
      if (_shellPlacementForMode(insertionMode) ==
          _ShellPlacement.afterAnchor) {
        sequence.add(unit);
      } else {
        sequence.insert(0, unit);
      }
      return;
    }

    if (_shellPlacementForMode(insertionMode) == _ShellPlacement.afterAnchor) {
      final anchorIndex = _lastAnchorIndex(sequence, anchorId);
      var insertIndex = anchorIndex < 0 ? sequence.length : anchorIndex + 1;
      while (insertIndex < sequence.length &&
          sequence[insertIndex].anchorId == anchorId &&
          _shellPlacementForMode(sequence[insertIndex].insertionMode) ==
              _ShellPlacement.afterAnchor) {
        insertIndex++;
      }
      sequence.insert(insertIndex, unit);
      return;
    }

    final anchorIndex = _firstAnchorIndex(sequence, anchorId);
    final insertIndex = anchorIndex < 0 ? 0 : anchorIndex;
    sequence.insert(insertIndex, unit);
  }

  ExecutionInsertionMode _effectiveInsertionModeForResolvedAnchor(
    ResolvedExecutionUnit unit,
    String? resolvedAnchorId,
  ) {
    if (unit.sourceKind == ExecutionSourceKind.persona &&
        unit.insertionMode == ExecutionInsertionMode.relativeBefore &&
        unit.anchorId == 'characterDescription' &&
        resolvedAnchorId == 'systemPrompt') {
      return ExecutionInsertionMode.relativeAfter;
    }
    return unit.insertionMode;
  }

  String? _resolveAnchorId(
    List<ResolvedExecutionUnit> sequence,
    ResolvedExecutionUnit unit,
  ) {
    final candidates = <String>[
      if (unit.anchorId != null && unit.anchorId!.trim().isNotEmpty)
        unit.anchorId!.trim(),
      ..._fallbackAnchorCandidates(unit),
    ];
    for (final candidate in candidates) {
      if (_containsMarker(sequence, candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Iterable<String> _fallbackAnchorCandidates(ResolvedExecutionUnit unit) sync* {
    if (unit.insertionMode == ExecutionInsertionMode.afterHistory ||
        unit.insertionMode == ExecutionInsertionMode.beforeHistory) {
      yield 'history';
      yield 'systemPrompt';
      return;
    }
    if (unit.sourceKind == ExecutionSourceKind.persona) {
      yield 'characterDescription';
      yield 'systemPrompt';
      yield 'history';
      return;
    }
    if (unit.sourceKind == ExecutionSourceKind.worldInfoEntry) {
      final anchorId = unit.anchorId?.trim();
      if (anchorId != null &&
          (anchorId == 'authorNote' ||
              anchorId == 'exampleMessages' ||
              anchorId == 'worldInfoAfter' ||
              anchorId == 'worldInfo')) {
        yield anchorId;
      }
      yield 'systemPrompt';
      yield 'characterScenario';
      yield 'exampleMessages';
      yield 'worldInfoAfter';
      yield 'worldInfo';
      yield 'authorNote';
      yield 'history';
      return;
    }
    yield 'systemPrompt';
    yield 'history';
  }

  bool _containsMarker(List<ResolvedExecutionUnit> sequence, String markerId) {
    return sequence.any((unit) => _definesAnchor(unit, markerId));
  }

  int _firstAnchorIndex(List<ResolvedExecutionUnit> sequence, String anchorId) {
    for (var i = 0; i < sequence.length; i++) {
      if (_definesAnchor(sequence[i], anchorId)) {
        return i;
      }
    }
    return -1;
  }

  int _lastAnchorIndex(List<ResolvedExecutionUnit> sequence, String anchorId) {
    for (var i = sequence.length - 1; i >= 0; i--) {
      if (_definesAnchor(sequence[i], anchorId)) {
        return i;
      }
    }
    return -1;
  }

  bool _definesAnchor(ResolvedExecutionUnit unit, String anchorId) {
    return (unit.markerId ?? '').trim() == anchorId.trim();
  }

  ResolvedExecutionUnit _syntheticHistoryMarker() {
    return const ResolvedExecutionUnit(
      id: 'synthetic_history_marker',
      sourceKind: ExecutionSourceKind.marker,
      sourceRef: 'planner.synthetic.history',
      enabled: true,
      contentTemplate: '',
      role: 'system',
      insertionMode: ExecutionInsertionMode.replaceMarker,
      sourceOrder: 999999,
      markerId: 'history',
    );
  }

  ResolvedExecutionUnit _syntheticAuthorNoteMarker() {
    return const ResolvedExecutionUnit(
      id: 'synthetic_author_note_marker',
      sourceKind: ExecutionSourceKind.marker,
      sourceRef: 'planner.synthetic.author_note',
      enabled: true,
      contentTemplate: '',
      role: 'system',
      insertionMode: ExecutionInsertionMode.replaceMarker,
      sourceOrder: 999998,
      markerId: 'authorNote',
    );
  }

  void _insertSyntheticMarkerBeforeAnchor(
    List<ResolvedExecutionUnit> sequence,
    ResolvedExecutionUnit marker, {
    required String preferredAnchorId,
  }) {
    final anchorIndex = _firstAnchorIndex(sequence, preferredAnchorId);
    if (anchorIndex < 0) {
      sequence.add(marker);
      return;
    }
    sequence.insert(anchorIndex, marker);
  }

  bool _requiresSyntheticAuthorNoteMarker(
    List<ResolvedExecutionUnit> enabledUnits,
  ) {
    return enabledUnits.any(
      (unit) =>
          unit.insertionMode != ExecutionInsertionMode.historySplice &&
          (unit.anchorId ?? '').trim() == 'authorNote',
    );
  }

  bool _isScaffoldShellUnit(ResolvedExecutionUnit unit) {
    if (unit.sourceKind == ExecutionSourceKind.marker) {
      return true;
    }
    return (unit.sourceKind == ExecutionSourceKind.promptBlock ||
            unit.sourceKind == ExecutionSourceKind.characterCore ||
            unit.sourceKind == ExecutionSourceKind.persona) &&
        !unit.hasExplicitAnchor;
  }

  int _compareShellSourceOrder(
    ResolvedExecutionUnit a,
    ResolvedExecutionUnit b,
  ) {
    final compare = a.sourceOrder.compareTo(b.sourceOrder);
    if (compare != 0) {
      return compare;
    }
    return a.id.compareTo(b.id);
  }

  int _compareAnchoredShellUnits(
    ResolvedExecutionUnit a,
    ResolvedExecutionUnit b,
  ) {
    final sameAnchor = (a.anchorId ?? '') == (b.anchorId ?? '');
    final samePlacement =
        _shellPlacementForMode(a.insertionMode) ==
        _shellPlacementForMode(b.insertionMode);
    if (sameAnchor && samePlacement) {
      final orderCompare = a.injectionOrder.compareTo(b.injectionOrder);
      if (orderCompare != 0) {
        return orderCompare;
      }
    }
    final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
    if (sourceCompare != 0) {
      return sourceCompare;
    }
    final modeCompare = a.insertionMode.index.compareTo(b.insertionMode.index);
    if (modeCompare != 0) {
      return modeCompare;
    }
    final orderCompare = a.injectionOrder.compareTo(b.injectionOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    final anchorCompare = (a.anchorId ?? '').compareTo(b.anchorId ?? '');
    if (anchorCompare != 0) {
      return anchorCompare;
    }
    return a.id.compareTo(b.id);
  }

  int _compareOutletUnits(ResolvedExecutionUnit a, ResolvedExecutionUnit b) {
    final anchorCompare = (a.anchorId ?? '').compareTo(b.anchorId ?? '');
    if (anchorCompare != 0) {
      return anchorCompare;
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

  int _compareSpliceUnits(ResolvedExecutionUnit a, ResolvedExecutionUnit b) {
    // SillyTavern processes in-chat / absolute prompts by descending
    // injection_order within the same depth bucket. Starry keeps shell ordering
    // independent, but matches that descending rule for history_splice units.
    final orderCompare = b.injectionOrder.compareTo(a.injectionOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    final roleCompare = _rolePrecedence(
      a.role,
    ).compareTo(_rolePrecedence(b.role));
    if (roleCompare != 0) {
      return roleCompare;
    }
    return a.sourceOrder.compareTo(b.sourceOrder);
  }

  int _rolePrecedence(String role) {
    return switch (role.trim().toLowerCase()) {
      'system' => 0,
      'user' => 1,
      'assistant' => 2,
      _ => 3,
    };
  }

  bool _supportsGenerationType(
    ResolvedExecutionUnit unit,
    String generationType,
  ) {
    if (unit.generationTriggers.isEmpty) return true;
    final normalized = generationType.trim().toLowerCase();
    const chatAliases = <String>{
      'chat',
      'chat_completion',
      'chat-completion',
      'chatcompletion',
      'completion',
      'default',
    };
    final unitTriggers = unit.generationTriggers
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (unitTriggers.isEmpty) return true;
    if (chatAliases.contains(normalized)) {
      return unitTriggers.any(chatAliases.contains);
    }
    return unitTriggers.contains(normalized);
  }

  ExecutionInsertionMode _blockInsertionMode(
    PromptBlock block, {
    required int sourceOrder,
    required int? historyMarkerOrder,
    required String? explicitAnchorId,
    required Map<String, int> markerOrders,
  }) {
    final anchor = (block.placement.anchor ?? 'relative').trim().toLowerCase();
    if (block.placement.depth != null &&
        (anchor == 'absolute' || block.placement.injectionPosition == 1)) {
      return ExecutionInsertionMode.historySplice;
    }
    if (block.kind == 'core:postHistoryInstructions') {
      return ExecutionInsertionMode.afterHistory;
    }
    if (explicitAnchorId != null) {
      final markerOrder = markerOrders[explicitAnchorId];
      if (markerOrder != null && sourceOrder < markerOrder) {
        return ExecutionInsertionMode.relativeBefore;
      }
      return ExecutionInsertionMode.relativeAfter;
    }
    if (historyMarkerOrder != null && sourceOrder > historyMarkerOrder) {
      return ExecutionInsertionMode.afterHistory;
    }
    return ExecutionInsertionMode.relativeBefore;
  }

  String _resolveBlockTemplate(PromptBlock block, Character? character) {
    if (block.content.isNotEmpty) {
      return block.content;
    }
    if (character == null) return '';
    return switch (block.kindName) {
      'systemPrompt' =>
        character.systemPrompt.isNotEmpty
            ? character.systemPrompt
            : PromptSection.getDefaultContent(PromptSectionType.systemPrompt),
      'characterDescription' =>
        character.description.isEmpty
            ? ''
            : 'Description:\n${character.description}',
      'characterPersonality' =>
        character.personality.isEmpty
            ? ''
            : 'Personality:\n${character.personality}',
      'characterScenario' =>
        character.scenario.isEmpty ? '' : 'Scenario:\n${character.scenario}',
      'exampleMessages' =>
        character.exampleMessages.isEmpty
            ? ''
            : 'Example dialogue:\n${character.exampleMessages}',
      'postHistoryInstructions' =>
        character.postHistoryInstructions.isNotEmpty
            ? character.postHistoryInstructions
            : PromptSection.getDefaultContent(
                PromptSectionType.postHistoryInstructions,
              ),
      'nsfw' => PromptSection.getDefaultContent(PromptSectionType.nsfw),
      _ => '',
    };
  }

  bool _characterBlockContent(PromptBlock block, Character? character) {
    if (character == null || block.content.isNotEmpty) return false;
    return switch (block.kindName) {
      'systemPrompt' => character.systemPrompt.isNotEmpty,
      'characterDescription' => character.description.isNotEmpty,
      'characterPersonality' => character.personality.isNotEmpty,
      'characterScenario' => character.scenario.isNotEmpty,
      'exampleMessages' => character.exampleMessages.isNotEmpty,
      'postHistoryInstructions' => character.postHistoryInstructions.isNotEmpty,
      _ => false,
    };
  }

  Map<String, int> _promptMarkerOrders(List<PromptBlock> orderedBlocks) {
    final markerOrders = <String, int>{};
    for (final block in orderedBlocks) {
      if (_isHistoryMarker(block) || block.isMarker) {
        markerOrders[_markerIdentityForBlock(block)] = block.priority.sortOrder;
      }
    }
    return markerOrders;
  }

  bool _isHistoryMarker(PromptBlock block) {
    return block.kind == 'core:chatHistory' ||
        (block.isMarker &&
            (block.provenance.identifier ?? '').trim().toLowerCase() ==
                'chathistory');
  }

  String _markerIdentityForBlock(PromptBlock block) {
    if (_isHistoryMarker(block)) {
      return 'history';
    }
    final explicitIdentifier = (block.provenance.identifier ?? '').trim();
    if (explicitIdentifier.isNotEmpty) {
      return explicitIdentifier;
    }
    return _defaultMarkerForBlock(block.kindName) ?? block.id;
  }

  String? _explicitAnchorId(String anchor) {
    final normalized = anchor.trim();
    if (normalized.isEmpty) {
      return null;
    }
    switch (normalized.toLowerCase()) {
      case 'relative':
      case 'absolute':
        return null;
      case 'history':
      case 'chat_history':
      case 'chathistory':
        return 'history';
      default:
        return normalized;
    }
  }

  String? _anchorIdForBlock(
    PromptBlock block, {
    required ExecutionInsertionMode insertionMode,
    required String? explicitAnchorId,
  }) {
    if (explicitAnchorId != null) {
      return explicitAnchorId;
    }
    if (insertionMode == ExecutionInsertionMode.afterHistory ||
        insertionMode == ExecutionInsertionMode.beforeHistory) {
      return 'history';
    }
    if (insertionMode == ExecutionInsertionMode.historySplice) {
      return 'history';
    }
    if (block.kind == 'core:postHistoryInstructions') {
      return 'history';
    }
    return _defaultMarkerForBlock(block.kindName);
  }

  String? _anchorIdForWorldInfo(
    WorldInfoEntry entry,
    ExecutionInsertionMode insertionMode,
  ) {
    return switch (insertionMode) {
      ExecutionInsertionMode.authorNoteTop ||
      ExecutionInsertionMode.authorNoteBottom => 'authorNote',
      ExecutionInsertionMode.outlet => _resolvedWorldInfoOutletAnchor(entry),
      ExecutionInsertionMode.relativeAfter => switch (entry.position) {
        WorldInfoPosition.after => 'worldInfoAfter',
        WorldInfoPosition.emBottom => 'exampleMessages',
        _ => 'characterScenario',
      },
      ExecutionInsertionMode.historySplice => 'history',
      _ => switch (entry.position) {
        WorldInfoPosition.emTop => 'exampleMessages',
        _ => 'systemPrompt',
      },
    };
  }

  String _resolvedWorldInfoOutletAnchor(WorldInfoEntry entry) {
    final runtimeOutlet = entry.runtimePolicy.output.outlet?.trim() ?? '';
    if (runtimeOutlet.isNotEmpty) {
      return runtimeOutlet;
    }
    final entryOutlet = entry.outletName?.trim() ?? '';
    if (entryOutlet.isNotEmpty) {
      return entryOutlet;
    }
    return 'worldInfo';
  }

  String _worldInfoRole(int role) {
    return switch (role) {
      1 => 'assistant',
      2 => 'user',
      _ => 'system',
    };
  }

  String? _defaultMarkerForBlock(String kind) {
    return switch (kind) {
      'systemPrompt' => 'systemPrompt',
      'persona' => 'persona',
      'characterDescription' => 'characterDescription',
      'characterPersonality' => 'characterPersonality',
      'characterScenario' => 'characterScenario',
      'exampleMessages' => 'exampleMessages',
      'worldInfo' => 'worldInfo',
      'worldInfoAfter' => 'worldInfoAfter',
      'authorNote' => 'authorNote',
      'postHistoryInstructions' => 'postHistoryInstructions',
      'nsfw' => 'nsfw',
      'chatHistory' => 'history',
      'enhanceDefinitions' => 'enhanceDefinitions',
      'marker' => 'marker',
      // 'custom' and any third-party kind have no default marker. A wildcard
      // is required because kind is now an open String, not a closed enum.
      _ => null,
    };
  }

  String _buildPersonaContent(Persona persona) {
    final buffer = StringBuffer();
    if (persona.name.isNotEmpty) {
      buffer.writeln('The user is ${persona.name}.');
    }
    if (persona.description.isNotEmpty) {
      buffer.writeln('User description: ${persona.description}');
    }
    return buffer.toString().trim();
  }

  String _personaRole(Persona persona) {
    return switch (persona.descriptionSettings.role) {
      PersonaDescriptionRole.system => 'system',
      PersonaDescriptionRole.user => 'user',
      PersonaDescriptionRole.assistant => 'assistant',
    };
  }

  String? _personaAnchorId(Persona persona) {
    return switch (persona.descriptionSettings.position) {
      PersonaDescriptionPosition.inSystemPrompt => 'systemPrompt',
      PersonaDescriptionPosition.beforeChar ||
      PersonaDescriptionPosition.afterChar => 'characterDescription',
      PersonaDescriptionPosition.topAN ||
      PersonaDescriptionPosition.bottomAN => 'authorNote',
      PersonaDescriptionPosition.atDepth => 'history',
    };
  }

  int _personaSourceOrder(Persona persona) {
    return switch (persona.descriptionSettings.position) {
      PersonaDescriptionPosition.topAN => 1099,
      PersonaDescriptionPosition.bottomAN => 1101,
      _ => 1000,
    };
  }

  ExecutionInsertionMode _authorNoteInsertionMode(String placement) {
    return switch (placement.trim().toLowerCase()) {
      'before_history' => ExecutionInsertionMode.beforeHistory,
      'after_history' => ExecutionInsertionMode.afterHistory,
      _ => ExecutionInsertionMode.historySplice,
    };
  }

  String _authorNoteAnchorId(ExecutionInsertionMode insertionMode) {
    return switch (insertionMode) {
      ExecutionInsertionMode.afterHistory ||
      ExecutionInsertionMode.beforeHistory ||
      ExecutionInsertionMode.historySplice => 'history',
      _ => 'authorNote',
    };
  }

  bool _personaHasContent(Persona persona) {
    return persona.name.isNotEmpty || persona.description.trim().isNotEmpty;
  }

  bool _shouldInjectAuthorNote(
    AuthorNotePolicy policy, {
    required int historyLength,
  }) {
    if (!policy.hasContent) {
      return false;
    }
    final interval = policy.interval <= 0 ? 1 : policy.interval;
    return interval <= 1 || ((historyLength + 1) % interval == 0);
  }

  bool _isMandatoryPromptBlock(PromptBlock block) {
    return block.kind == 'core:systemPrompt';
  }

  int _comparePromptBlocks(PromptBlock a, PromptBlock b) {
    final orderCompare = a.priority.sortOrder.compareTo(b.priority.sortOrder);
    if (orderCompare != 0) {
      return orderCompare;
    }
    return a.id.compareTo(b.id);
  }

  ExecutionBudgetTier _budgetTierForBlock(PromptBlock block) {
    return switch (block.kindName) {
      'systemPrompt' => ExecutionBudgetTier.mandatory,
      'postHistoryInstructions' => ExecutionBudgetTier.high,
      _ => ExecutionBudgetTier.normal,
    };
  }

  /// Resolves a world-info entry's budget tier.
  ///
  /// Prefers an explicit tier carried by the entry's runtime policy (set at
  /// import time from the source dialect's allocation priority, e.g.
  /// SillyTavern's `weight`). Falls back to deriving a tier from `ignoreBudget`
  /// so entries without an explicit priority keep their previous behavior.
  ExecutionBudgetTier _budgetTierForWorldInfoEntry(WorldInfoEntry entry) {
    final explicit = entry.runtimePolicy.budget.tier?.trim().toLowerCase();
    return switch (explicit) {
      'mandatory' => ExecutionBudgetTier.mandatory,
      'high' => ExecutionBudgetTier.high,
      'normal' => ExecutionBudgetTier.normal,
      'low' => ExecutionBudgetTier.low,
      _ =>
        entry.ignoreBudget
            ? ExecutionBudgetTier.high
            : ExecutionBudgetTier.normal,
    };
  }

  _ShellPlacement _shellPlacementForMode(ExecutionInsertionMode mode) {
    return switch (mode) {
      ExecutionInsertionMode.relativeAfter ||
      ExecutionInsertionMode.afterHistory ||
      ExecutionInsertionMode.authorNoteBottom ||
      ExecutionInsertionMode.outlet => _ShellPlacement.afterAnchor,
      _ => _ShellPlacement.beforeAnchor,
    };
  }

  bool _blocksOverride(ResolvedExecutionUnit unit) {
    return unit.locked || unit.forbidOverride;
  }

  PromptDisableOverlay _mergeOverlay(
    PromptDisableOverlay primary,
    PromptDisableOverlay secondary,
  ) {
    return PromptDisableOverlay(
      disabledUnitIds: <String>{
        ...primary.disabledUnitIds,
        ...secondary.disabledUnitIds,
      }.toList(growable: false),
      disabledSourceRefs: <String>{
        ...primary.disabledSourceRefs,
        ...secondary.disabledSourceRefs,
      }.toList(growable: false),
    );
  }

  ExecutionTraceEntry _disabledTrace(ResolvedExecutionUnit unit) {
    return ExecutionTraceEntry(
      unitId: unit.id,
      stage: ExecutionTraceStage.filtering,
      reason: unit.disableReason ?? 'disabled',
      sourceKind: unit.sourceKind,
      sourceRef: unit.sourceRef,
      disableSource: unit.disableSource,
      anchorId: unit.anchorId,
      insertionMode: unit.insertionMode,
    );
  }

  List<ExecutionTraceEntry> _buildRoutingTrace(
    List<ResolvedExecutionUnit> shellSequence,
    Map<String, List<ResolvedExecutionUnit>> outletMap,
    List<HistorySplicePoint> historySplicePoints,
  ) {
    final trace = <ExecutionTraceEntry>[];
    for (final unit in shellSequence.where(
      (unit) => unit.sourceKind != ExecutionSourceKind.marker,
    )) {
      trace.add(
        ExecutionTraceEntry(
          unitId: unit.id,
          stage: ExecutionTraceStage.routing,
          reason: 'shell_routed',
          sourceKind: unit.sourceKind,
          sourceRef: unit.sourceRef,
          anchorId: unit.anchorId,
          insertionMode: unit.insertionMode,
        ),
      );
    }
    for (final entry in outletMap.entries) {
      for (final unit in entry.value) {
        trace.add(
          ExecutionTraceEntry(
            unitId: unit.id,
            stage: ExecutionTraceStage.routing,
            reason: 'outlet_routed',
            sourceKind: unit.sourceKind,
            sourceRef: unit.sourceRef,
            anchorId: unit.anchorId,
            outletId: entry.key,
            insertionMode: unit.insertionMode,
          ),
        );
      }
    }
    for (final point in historySplicePoints) {
      for (final unit in point.units) {
        trace.add(
          ExecutionTraceEntry(
            unitId: unit.id,
            stage: ExecutionTraceStage.routing,
            reason: 'history_splice_routed',
            sourceKind: unit.sourceKind,
            sourceRef: unit.sourceRef,
            anchorId: unit.anchorId,
            insertionMode: unit.insertionMode,
          ),
        );
      }
    }
    return List<ExecutionTraceEntry>.unmodifiable(trace);
  }
}

enum _ShellPlacement { beforeAnchor, afterAnchor }
