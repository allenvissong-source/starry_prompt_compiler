import 'dart:convert';

import '../codec/prompt_plan_wire.dart';
import 'conversation_turns_models.dart';
import 'prompt_execution_models.dart';

const promptCompilerContract = 'domain_prompt_v1';
const promptPlanSchema = 'structured_prompt_plan_v1';

/// Changes to wire semantics must change this descriptor in Dart and Rust.
final String promptPlanSchemaDigest = promptDigest({
  'contract': promptCompilerContract,
  'schema': promptPlanSchema,
  'roles': ['system', 'user', 'assistant'],
  'placements': PromptPlacement.values.map(promptEnumName).toList(),
  'retention': PromptRetention.values.map(promptEnumName).toList(),
  'semantic_kinds': PromptSemanticKind.values.map(promptEnumName).toList(),
  'sources': ExecutionSourceKind.values.map(promptEnumName).toList(),
  'speaker_kinds': PromptSpeakerKind.values.map(promptEnumName).toList(),
  'budget_tiers': ExecutionBudgetTier.values.map(promptEnumName).toList(),
  'fields': {
    'speaker': 'kind:enum,resource_id?:id,snapshot_key?:id',
    'source': 'key:id,locator:id,resource_id:id,revision:id,content_hash:id',
    'input':
        'canonical_input_digest:id,scan_history_digest:id,variables_digest:id,environment_digest:id',
    'unit':
        'unit_id:id,source_kind:enum,source_resource_id:id,source_snapshot_key:id,semantic_kind:enum,role:enum,expanded_text:text,retention:enum,budget_tier:enum,worldbook_id?:id,ignore_worldbook_budget:bool,injection_order:order,source_order:order',
    'emission':
        'emission_id:id,unit_id:id,placement:enum,sequence:uint,depth?:uint,outlet_name?:id',
    'trace':
        'unit_id:id,stage:id,reason:id,source_resource_id?:id,target_unit_id?:id,anchor_id?:id,outlet_name?:id,matched_key?:id',
    'candidates':
        'schema_digest:id,compiler_contract:id,compilation_id:id,source_snapshots:source[],input_snapshot:input,speaker_ref:speaker,units:unit[],emissions:emission[],transformed_input:text,history_transform_digest:id,trace:trace[]',
    'plan':
        'schema_digest:id,candidate_digest:id,source_snapshots:source[],speaker_ref:speaker,selected_units:unit[],emissions:emission[],budget_snapshot_digest:id,costs_digest:id,layout_history_digest:id,requires_compaction:bool,admission_trace:trace[]',
    'admission':
        'schema_digest:id,candidate_digest:id,budget_snapshot_digest:id,layout_history_digest:id,input_limit:uint,worldbook_available_tokens:uint,emission_costs:map<uint>,admitted_non_worldbook_unit_ids:id[],fixed_context_cost:uint,non_worldbook_prompt_cost:uint,protected_history_cost:uint,requires_compaction:bool,trace:trace[],costs_digest:id',
  },
  'validation': {
    'max_items': 16384,
    'max_text_bytes': 4194304,
    'max_id_utf16_units': 1024,
    'max_integer': 9007199254740991,
    'min_order': -2147483648,
    'optional_null': false,
    'unknown_fields': false,
    'depth_basis': 'frozen_dialogue_slots_current_zero_tools_excluded',
  },
});

enum PromptRetention { required, optional }

enum PromptPlacement {
  beforeHistory,
  afterHistory,
  atDepth,
  historyStart,
  tail,
}

enum PromptSpeakerKind { assistant, character, builtin }

class PromptSpeakerRef {
  const PromptSpeakerRef({
    required this.kind,
    this.resourceId,
    this.snapshotKey,
  });

  final PromptSpeakerKind kind;
  final String? resourceId;
  final String? snapshotKey;

  Map<String, dynamic> toJson() => {
    'kind': promptEnumName(kind),
    if (resourceId != null) 'resource_id': resourceId,
    if (snapshotKey != null) 'snapshot_key': snapshotKey,
  };

  factory PromptSpeakerRef.fromJson(Object? value) {
    final json = promptObject(value, {'kind', 'resource_id', 'snapshot_key'});
    return PromptSpeakerRef(
      kind: promptEnum(json['kind'], PromptSpeakerKind.values),
      resourceId: json.containsKey('resource_id')
          ? promptString(json, 'resource_id')
          : null,
      snapshotKey: json.containsKey('snapshot_key')
          ? promptString(json, 'snapshot_key')
          : null,
    );
  }
}

class PromptSourceSnapshot {
  const PromptSourceSnapshot({
    required this.key,
    required this.locator,
    required this.resourceId,
    required this.revision,
    required this.contentHash,
  });

  final String key;
  final String locator;
  final String resourceId;
  final String revision;
  final String contentHash;

  Map<String, dynamic> toJson() => {
    'key': key,
    'locator': locator,
    'resource_id': resourceId,
    'revision': revision,
    'content_hash': contentHash,
  };

  factory PromptSourceSnapshot.fromJson(Object? value) {
    final json = promptObject(value, {
      'key',
      'locator',
      'resource_id',
      'revision',
      'content_hash',
    });
    return PromptSourceSnapshot(
      key: promptString(json, 'key'),
      locator: promptString(json, 'locator'),
      resourceId: promptString(json, 'resource_id'),
      revision: promptString(json, 'revision'),
      contentHash: promptString(json, 'content_hash'),
    );
  }
}

class PromptInputSnapshot {
  const PromptInputSnapshot({
    required this.canonicalInputDigest,
    required this.scanHistoryDigest,
    required this.variablesDigest,
    required this.environmentDigest,
  });

  final String canonicalInputDigest;
  final String scanHistoryDigest;
  final String variablesDigest;
  final String environmentDigest;

  Map<String, dynamic> toJson() => {
    'canonical_input_digest': canonicalInputDigest,
    'scan_history_digest': scanHistoryDigest,
    'variables_digest': variablesDigest,
    'environment_digest': environmentDigest,
  };

  factory PromptInputSnapshot.fromJson(Object? value) {
    final json = promptObject(value, {
      'canonical_input_digest',
      'scan_history_digest',
      'variables_digest',
      'environment_digest',
    });
    return PromptInputSnapshot(
      canonicalInputDigest: promptString(json, 'canonical_input_digest'),
      scanHistoryDigest: promptString(json, 'scan_history_digest'),
      variablesDigest: promptString(json, 'variables_digest'),
      environmentDigest: promptString(json, 'environment_digest'),
    );
  }
}

class CompiledPromptUnit {
  const CompiledPromptUnit({
    required this.unitId,
    required this.sourceKind,
    required this.sourceResourceId,
    required this.sourceSnapshotKey,
    required this.semanticKind,
    required this.role,
    required this.expandedText,
    required this.retention,
    this.budgetTier = ExecutionBudgetTier.normal,
    this.worldbookId,
    this.ignoreWorldbookBudget = false,
    this.injectionOrder = 0,
    this.sourceOrder = 0,
  });

  final String unitId;
  final ExecutionSourceKind sourceKind;
  final String sourceResourceId;
  final String sourceSnapshotKey;
  final PromptSemanticKind semanticKind;
  final TurnMessageRole role;
  final String expandedText;
  final PromptRetention retention;
  final ExecutionBudgetTier budgetTier;
  final String? worldbookId;
  final bool ignoreWorldbookBudget;
  final int injectionOrder;
  final int sourceOrder;

  Map<String, dynamic> toJson() => {
    'unit_id': unitId,
    'source_kind': promptEnumName(sourceKind),
    'source_resource_id': sourceResourceId,
    'source_snapshot_key': sourceSnapshotKey,
    'semantic_kind': promptEnumName(semanticKind),
    'role': role.wireValue,
    'expanded_text': expandedText,
    'retention': promptEnumName(retention),
    'budget_tier': promptEnumName(budgetTier),
    if (worldbookId != null) 'worldbook_id': worldbookId,
    'ignore_worldbook_budget': ignoreWorldbookBudget,
    'injection_order': injectionOrder,
    'source_order': sourceOrder,
  };

  factory CompiledPromptUnit.fromJson(Object? value) {
    final json = promptObject(value, {
      'unit_id',
      'source_kind',
      'source_resource_id',
      'source_snapshot_key',
      'semantic_kind',
      'role',
      'expanded_text',
      'retention',
      'budget_tier',
      'worldbook_id',
      'ignore_worldbook_budget',
      'injection_order',
      'source_order',
    });
    return CompiledPromptUnit(
      unitId: promptString(json, 'unit_id'),
      sourceKind: promptEnum(json['source_kind'], ExecutionSourceKind.values),
      sourceResourceId: promptString(json, 'source_resource_id'),
      sourceSnapshotKey: promptString(json, 'source_snapshot_key'),
      semanticKind: promptEnum(
        json['semantic_kind'],
        PromptSemanticKind.values,
      ),
      role: promptEnum(json['role'], TurnMessageRole.values),
      expandedText: promptText(json, 'expanded_text'),
      retention: promptEnum(json['retention'], PromptRetention.values),
      budgetTier: promptEnum(json['budget_tier'], ExecutionBudgetTier.values),
      worldbookId: json.containsKey('worldbook_id')
          ? promptString(json, 'worldbook_id')
          : null,
      ignoreWorldbookBudget: promptBool(json, 'ignore_worldbook_budget'),
      injectionOrder: promptInt(json, 'injection_order', min: -2147483648),
      sourceOrder: promptInt(json, 'source_order', min: -2147483648),
    );
  }
}

class PromptEmission {
  const PromptEmission({
    required this.emissionId,
    required this.unitId,
    required this.placement,
    required this.sequence,
    this.depth,
    this.outletName,
  });

  final String emissionId;
  final String unitId;
  final PromptPlacement placement;
  final int sequence;
  final int? depth;
  final String? outletName;

  Map<String, dynamic> toJson() => {
    'emission_id': emissionId,
    'unit_id': unitId,
    'placement': promptEnumName(placement),
    'sequence': sequence,
    if (depth != null) 'depth': depth,
    if (outletName != null) 'outlet_name': outletName,
  };

  factory PromptEmission.fromJson(Object? value) {
    final json = promptObject(value, {
      'emission_id',
      'unit_id',
      'placement',
      'sequence',
      'depth',
      'outlet_name',
    });
    return PromptEmission(
      emissionId: promptString(json, 'emission_id'),
      unitId: promptString(json, 'unit_id'),
      placement: promptEnum(json['placement'], PromptPlacement.values),
      sequence: promptInt(json, 'sequence'),
      depth: json.containsKey('depth') ? promptInt(json, 'depth') : null,
      outletName: json.containsKey('outlet_name')
          ? promptString(json, 'outlet_name')
          : null,
    );
  }
}

/// A diagnostic is data, never an instruction or authorization grant.
class PromptCompilationTrace {
  const PromptCompilationTrace({
    required this.unitId,
    required this.stage,
    required this.reason,
    this.sourceResourceId,
    this.targetUnitId,
    this.anchorId,
    this.outletName,
    this.matchedKey,
  });

  final String unitId;
  final String stage;
  final String reason;
  final String? sourceResourceId;
  final String? targetUnitId;
  final String? anchorId;
  final String? outletName;
  final String? matchedKey;

  Map<String, dynamic> toJson() => {
    'unit_id': unitId,
    'stage': stage,
    'reason': reason,
    if (sourceResourceId != null) 'source_resource_id': sourceResourceId,
    if (targetUnitId != null) 'target_unit_id': targetUnitId,
    if (anchorId != null) 'anchor_id': anchorId,
    if (outletName != null) 'outlet_name': outletName,
    if (matchedKey != null) 'matched_key': matchedKey,
  };

  factory PromptCompilationTrace.fromJson(Object? value) {
    final json = promptObject(value, {
      'unit_id',
      'stage',
      'reason',
      'source_resource_id',
      'target_unit_id',
      'anchor_id',
      'outlet_name',
      'matched_key',
    });
    String? optional(String key) =>
        json.containsKey(key) ? promptString(json, key) : null;
    return PromptCompilationTrace(
      unitId: promptString(json, 'unit_id'),
      stage: promptString(json, 'stage'),
      reason: promptString(json, 'reason'),
      sourceResourceId: optional('source_resource_id'),
      targetUnitId: optional('target_unit_id'),
      anchorId: optional('anchor_id'),
      outletName: optional('outlet_name'),
      matchedKey: optional('matched_key'),
    );
  }
}

class PreparedPromptCandidates {
  PreparedPromptCandidates({
    required this.compilationId,
    required List<PromptSourceSnapshot> sourceSnapshots,
    required this.inputSnapshot,
    required this.speakerRef,
    required List<CompiledPromptUnit> units,
    required List<PromptEmission> emissions,
    required this.transformedInput,
    required this.historyTransformDigest,
    List<PromptCompilationTrace> trace = const [],
  }) : sourceSnapshots = List.unmodifiable(sourceSnapshots),
       units = List.unmodifiable(units),
       emissions = List.unmodifiable(emissions),
       trace = List.unmodifiable(trace) {
    validatePromptReferences(
      this.sourceSnapshots,
      speakerRef,
      this.units,
      this.emissions,
    );
    // Apply the exact wire validation to in-process callers as well.
    promptString({'compilation_id': compilationId}, 'compilation_id');
    PromptInputSnapshot.fromJson(inputSnapshot.toJson());
    promptText({'text': transformedInput}, 'text');
    promptString({'digest': historyTransformDigest}, 'digest');
    for (final entry in this.trace) {
      PromptCompilationTrace.fromJson(entry.toJson());
    }
  }

  final String compilationId;
  final List<PromptSourceSnapshot> sourceSnapshots;
  final PromptInputSnapshot inputSnapshot;
  final PromptSpeakerRef speakerRef;
  final List<CompiledPromptUnit> units;
  final List<PromptEmission> emissions;
  final String transformedInput;
  final String historyTransformDigest;
  final List<PromptCompilationTrace> trace;

  late final String digest = promptDigest(toJson());

  Map<String, dynamic> toJson() => {
    'schema_digest': promptPlanSchemaDigest,
    'compiler_contract': promptCompilerContract,
    'compilation_id': compilationId,
    'source_snapshots': sourceSnapshots.map((s) => s.toJson()).toList(),
    'input_snapshot': inputSnapshot.toJson(),
    'speaker_ref': speakerRef.toJson(),
    'units': units.map((u) => u.toJson()).toList(),
    'emissions': emissions.map((e) => e.toJson()).toList(),
    'transformed_input': transformedInput,
    'history_transform_digest': historyTransformDigest,
    'trace': trace.map((t) => t.toJson()).toList(),
  };

  factory PreparedPromptCandidates.fromJson(Object? value) {
    final json = promptObject(value, {
      'schema_digest',
      'compiler_contract',
      'compilation_id',
      'source_snapshots',
      'input_snapshot',
      'speaker_ref',
      'units',
      'emissions',
      'transformed_input',
      'history_transform_digest',
      'trace',
    });
    validatePromptSchema(json);
    if (json['compiler_contract'] != promptCompilerContract) {
      throw FormatException('prompt_plan.compiler_contract_mismatch');
    }
    return PreparedPromptCandidates(
      compilationId: promptString(json, 'compilation_id'),
      sourceSnapshots: promptList(
        json,
        'source_snapshots',
        PromptSourceSnapshot.fromJson,
      ),
      inputSnapshot: PromptInputSnapshot.fromJson(json['input_snapshot']),
      speakerRef: PromptSpeakerRef.fromJson(json['speaker_ref']),
      units: promptList(json, 'units', CompiledPromptUnit.fromJson),
      emissions: promptList(json, 'emissions', PromptEmission.fromJson),
      transformedInput: promptText(json, 'transformed_input'),
      historyTransformDigest: promptString(json, 'history_transform_digest'),
      trace: promptList(json, 'trace', PromptCompilationTrace.fromJson),
    );
  }
}

class CompiledPromptPlan {
  CompiledPromptPlan({
    required this.candidateDigest,
    required List<PromptSourceSnapshot> sourceSnapshots,
    required this.speakerRef,
    required List<CompiledPromptUnit> selectedUnits,
    required List<PromptEmission> emissions,
    required this.budgetSnapshotDigest,
    required this.costsDigest,
    required this.layoutHistoryDigest,
    required this.requiresCompaction,
    List<PromptCompilationTrace> admissionTrace = const [],
  }) : sourceSnapshots = List.unmodifiable(sourceSnapshots),
       selectedUnits = List.unmodifiable(selectedUnits),
       emissions = List.unmodifiable(emissions),
       admissionTrace = List.unmodifiable(admissionTrace) {
    validatePromptReferences(
      this.sourceSnapshots,
      speakerRef,
      this.selectedUnits,
      this.emissions,
    );
    for (final digest in [
      candidateDigest,
      budgetSnapshotDigest,
      costsDigest,
      layoutHistoryDigest,
    ]) {
      promptString({'digest': digest}, 'digest');
    }
    for (final entry in this.admissionTrace) {
      PromptCompilationTrace.fromJson(entry.toJson());
    }
  }

  final String candidateDigest;
  final List<PromptSourceSnapshot> sourceSnapshots;
  final PromptSpeakerRef speakerRef;
  final List<CompiledPromptUnit> selectedUnits;
  final List<PromptEmission> emissions;
  final String budgetSnapshotDigest;
  final String costsDigest;
  final String layoutHistoryDigest;
  final bool requiresCompaction;
  final List<PromptCompilationTrace> admissionTrace;

  late final String digest = promptDigest(toJson());

  Map<String, dynamic> toJson() => {
    'schema_digest': promptPlanSchemaDigest,
    'candidate_digest': candidateDigest,
    'source_snapshots': sourceSnapshots.map((s) => s.toJson()).toList(),
    'speaker_ref': speakerRef.toJson(),
    'selected_units': selectedUnits.map((u) => u.toJson()).toList(),
    'emissions': emissions.map((e) => e.toJson()).toList(),
    'budget_snapshot_digest': budgetSnapshotDigest,
    'costs_digest': costsDigest,
    'layout_history_digest': layoutHistoryDigest,
    'requires_compaction': requiresCompaction,
    'admission_trace': admissionTrace.map((t) => t.toJson()).toList(),
  };

  factory CompiledPromptPlan.fromJson(Object? value) {
    final json = promptObject(value, {
      'schema_digest',
      'candidate_digest',
      'source_snapshots',
      'speaker_ref',
      'selected_units',
      'emissions',
      'budget_snapshot_digest',
      'costs_digest',
      'layout_history_digest',
      'requires_compaction',
      'admission_trace',
    });
    validatePromptSchema(json);
    return CompiledPromptPlan(
      candidateDigest: promptString(json, 'candidate_digest'),
      sourceSnapshots: promptList(
        json,
        'source_snapshots',
        PromptSourceSnapshot.fromJson,
      ),
      speakerRef: PromptSpeakerRef.fromJson(json['speaker_ref']),
      selectedUnits: promptList(
        json,
        'selected_units',
        CompiledPromptUnit.fromJson,
      ),
      emissions: promptList(json, 'emissions', PromptEmission.fromJson),
      budgetSnapshotDigest: promptString(json, 'budget_snapshot_digest'),
      costsDigest: promptString(json, 'costs_digest'),
      layoutHistoryDigest: promptString(json, 'layout_history_digest'),
      requiresCompaction: promptBool(json, 'requires_compaction'),
      admissionTrace: promptList(
        json,
        'admission_trace',
        PromptCompilationTrace.fromJson,
      ),
    );
  }
}

void validatePromptSchema(Map<String, dynamic> json) {
  if (json['schema_digest'] != promptPlanSchemaDigest) {
    throw FormatException('prompt_plan.schema_mismatch');
  }
}

void validatePromptReferences(
  List<PromptSourceSnapshot> sources,
  PromptSpeakerRef speaker,
  List<CompiledPromptUnit> units,
  List<PromptEmission> emissions,
) {
  if (sources.length > 16384 ||
      units.length > 16384 ||
      emissions.length > 16384) {
    throw FormatException('prompt_plan.excessive_size');
  }
  promptUnique(sources.map((s) => s.key));
  promptUnique(units.map((u) => u.unitId));
  promptUnique(emissions.map((e) => e.emissionId));
  promptUnique(emissions.map((e) => e.sequence.toString()));
  final sourceByKey = {for (final source in sources) source.key: source};
  for (final source in sources) {
    PromptSourceSnapshot.fromJson(source.toJson());
  }
  PromptSpeakerRef.fromJson(speaker.toJson());
  if (speaker.kind == PromptSpeakerKind.assistant) {
    if (speaker.resourceId != null || speaker.snapshotKey != null) {
      throw FormatException('prompt_plan.invalid_assistant_ref');
    }
  } else if (speaker.resourceId == null ||
      sourceByKey[speaker.snapshotKey]?.resourceId != speaker.resourceId) {
    throw FormatException('prompt_plan.invalid_speaker_ref');
  }
  final unitIds = units.map((u) => u.unitId).toSet();
  var textBytes = 0;
  for (final unit in units) {
    CompiledPromptUnit.fromJson(unit.toJson());
    if (unit.sourceKind == ExecutionSourceKind.marker ||
        sourceByKey[unit.sourceSnapshotKey]?.resourceId !=
            unit.sourceResourceId ||
        (unit.sourceKind == ExecutionSourceKind.worldInfoEntry) !=
            (unit.worldbookId != null) ||
        (unit.worldbookId != null &&
            unit.worldbookId != unit.sourceResourceId) ||
        (unit.ignoreWorldbookBudget && unit.worldbookId == null)) {
      throw FormatException('prompt_plan.invalid_unit_source');
    }
    if (unit.semanticKind == PromptSemanticKind.identity &&
        (speaker.kind == PromptSpeakerKind.assistant ||
            unit.sourceSnapshotKey != speaker.snapshotKey ||
            unit.retention != PromptRetention.required)) {
      throw FormatException('prompt_plan.invalid_identity_source');
    }
    if (unit.budgetTier == ExecutionBudgetTier.mandatory &&
        unit.retention != PromptRetention.required) {
      throw FormatException('prompt_plan.invalid_mandatory_retention');
    }
    textBytes += utf8.encode(unit.expandedText).length;
  }
  if (textBytes > 4 * 1024 * 1024) {
    throw FormatException('prompt_plan.excessive_text');
  }
  final emittedIds = <String>{};
  for (final emission in emissions) {
    PromptEmission.fromJson(emission.toJson());
    if (!unitIds.contains(emission.unitId) ||
        (emission.placement == PromptPlacement.atDepth) !=
            (emission.depth != null)) {
      throw FormatException('prompt_plan.invalid_emission');
    }
    emittedIds.add(emission.unitId);
  }
  if (emittedIds.length != unitIds.length) {
    throw FormatException('prompt_plan.unemitted_unit');
  }
}
