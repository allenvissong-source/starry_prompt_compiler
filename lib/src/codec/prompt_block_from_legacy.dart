library;

import '../models/prompt_block.dart';
import '../models/prompt_manager.dart';

/// V1 to V2 prompt block conversion.
///
/// Implements the V1->V2 rules in `openspec/specs/prompt-block-schema/spec.md`:
/// field mapping, the 15 `core:*` kind mappings, verbatim placement copy, the
/// `isMarker` drop, and unknown-key passthrough into `extensions.legacy_v1`.
///
/// The conversion is deliberately **per-block and pure**. That is safe only
/// because §4 was corrected first: `placement` now restates V1's input fields
/// rather than a resolved insertion position, so nothing here needs profile-wide
/// context. If a future change reintroduces a resolved `placement.kind`, this
/// function becomes the wrong shape — resolution needs the marker-order map that
/// only the planner builds.
/// Reserved namespace for V1 keys this version does not model.
const String kLegacyV1ExtensionNamespace = 'legacy_v1';

/// Keys the V1 `LegacyPromptBlock` shape owns. Anything outside this set is unknown
/// and is preserved under `extensions.legacy_v1` rather than dropped.
const Set<String> _knownV1BlockKeys = <String>{
  'id',
  'promptProfileId',
  'kind',
  'name',
  'enabled',
  'content',
  'role',
  'placementPolicy',
  'activationPolicy',
  'priorityPolicy',
  'protectionPolicy',
  'provenance',
  // §5: V1 tooling may emit this convenience field. It is ignored rather than
  // carried, because V2 answers the question from `kind` and a stale boolean
  // would be a second source of truth.
  'isMarker',
};

/// Converts one V1 [LegacyPromptBlock] into its V2 form.
///
/// [rawJson] is the block's original JSON when available. It is used only to
/// recover keys the V1 model itself drops on parse (§7) — the typed fields are
/// read from [block], not re-parsed.
PromptBlock promptBlockFromLegacy(
  LegacyPromptBlock block, {
  Map<String, dynamic>? rawJson,
}) {
  final extensions = <String, dynamic>{};
  final legacy = _unknownV1Keys(rawJson);
  if (legacy.isNotEmpty) {
    extensions[kLegacyV1ExtensionNamespace] = legacy;
  }

  return PromptBlock(
    id: block.id,
    promptProfileId: block.promptProfileId,
    // §3: every V1 enum value becomes "core:<v1-name>". `kind.name` is the
    // enum's own spelling, so the 15 mappings are exhaustive by construction
    // rather than by a hand-maintained switch that could drift.
    kind: normalizePromptBlockKind(block.kind.name),
    name: block.name,
    enabled: block.enabled,
    content: block.content,
    role: block.role,
    // §4.1: verbatim copy, nulls preserved. No normalisation, no discriminator.
    // §4.2: the injectionOrder mirror is unconditional.
    placement: PromptBlockPlacement(
      anchor: block.placementPolicy.anchor,
      injectionPosition: block.placementPolicy.injectionPosition,
      depth: block.placementPolicy.depth,
      injectionOrder: block.priorityPolicy.injectionOrder,
    ),
    activation: PromptBlockActivation(
      generationTriggers: block.activationPolicy.generationTriggers,
    ),
    priority: PromptBlockPriority(
      sortOrder: block.priorityPolicy.sortOrder,
      injectionOrder: block.priorityPolicy.injectionOrder,
    ),
    protection: PromptBlockProtection(
      locked: block.protectionPolicy.locked,
      forbidOverride: block.protectionPolicy.forbidOverride,
    ),
    provenance: PromptBlockProvenance(
      source: block.provenance.source,
      identifier: block.provenance.identifier,
      extension: block.provenance.extension,
    ),
    extensions: extensions,
  );
}

/// Converts a whole V1 block list.
List<PromptBlock> promptBlocksFromLegacy(
  List<LegacyPromptBlock> blocks, {
  List<Map<String, dynamic>>? rawJson,
}) {
  return List<PromptBlock>.unmodifiable(<PromptBlock>[
    for (var i = 0; i < blocks.length; i++)
      promptBlockFromLegacy(
        blocks[i],
        rawJson: rawJson != null && i < rawJson.length ? rawJson[i] : null,
      ),
  ]);
}

/// §4.1 note: a V1 anchor of `"relative"` with no position and no depth is the
/// default policy, and it converts to a placement whose fields are all null
/// except the injectionOrder mirror. That is intentional — it is precisely what
/// the planner reads today for such a block.
Map<String, dynamic> _unknownV1Keys(Map<String, dynamic>? rawJson) {
  if (rawJson == null || rawJson.isEmpty) return const <String, dynamic>{};
  final unknown = <String, dynamic>{};
  for (final entry in rawJson.entries) {
    if (_knownV1BlockKeys.contains(entry.key)) continue;
    unknown[entry.key] = entry.value;
  }
  return unknown;
}
