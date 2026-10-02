/// V2 prompt block shape.
///
/// Mirrors the prompt-block schema and its V1->V2 field mapping in
/// `openspec/specs/prompt-block-schema/spec.md`.
///
/// Two properties of this shape are load-bearing and easy to erode, so they are
/// stated here rather than left to the schema file:
///
/// **`kind` is an open string, not an enum.** V1's closed 15-value enum becomes
/// `"core:<name>"`. Third-party kinds are representable without a compiler
/// change; unknown namespaces are carried, not coerced.
///
/// **`placement` is a verbatim restatement of the V1 input fields, NOT a
/// resolved insertion position.** It holds `anchor`, `injectionPosition` and
/// `depth` exactly as V1 supplied them, including nulls. Resolution stays in
/// `PromptExecutionPlanner._blockInsertionMode`, which needs whole-profile state
/// (the marker-order map and the history marker's position) that no per-block
/// value can carry. An earlier draft of the compat matrix specified a `kind`
/// discriminator with a `before`/`after` enum computed per block; that was
/// unsound, and §4.4 of the matrix records the measurement that showed it would
/// have flipped placement for 45 of the corpus's 46 blocks.
library;

/// Namespace prefix applied to every kind migrated from the V1 enum.
const String kCorePromptBlockKindNamespace = 'core';

/// Serialized schema version for every block this file produces.
const int kPromptBlockSchemaVersion = 2;

/// Placement intent, carried verbatim from V1.
///
/// All three fields are nullable and a block that carried no `placementPolicy`
/// in V1 produces all three as `null` — which is exactly what the planner reads
/// when the V1 policy sits at its defaults.
class PromptBlockPlacement {
  const PromptBlockPlacement({
    this.anchor,
    this.injectionPosition,
    this.depth,
    this.injectionOrder,
  });

  factory PromptBlockPlacement.fromJson(Map<String, dynamic> json) {
    return PromptBlockPlacement(
      anchor: _stringOrNull(json['anchor']),
      injectionPosition: _intOrNull(json['injectionPosition']),
      depth: _intOrNull(json['depth']),
      injectionOrder: _intOrNull(json['injectionOrder']),
    );
  }

  /// Copied verbatim from `placementPolicy.anchor`. Deliberately NOT
  /// normalised: the planner trims and lower-cases at its own read site, and
  /// normalising here would create a second, divergent notion of the same
  /// string.
  final String? anchor;

  /// Copied verbatim from `placementPolicy.injectionPosition`.
  final int? injectionPosition;

  /// Copied verbatim from `placementPolicy.depth`.
  final int? depth;

  /// Mirror of `priority.injectionOrder`, copied unconditionally.
  ///
  /// The mirror is redundant-but-harmless: the planner reads the tiebreak from
  /// `priority.injectionOrder`. Keeping it unconditional is what makes the
  /// placement copy lossless — with the variants gone there is no block-local
  /// fact that could decide to omit it.
  final int? injectionOrder;

  bool get isEmpty =>
      anchor == null &&
      injectionPosition == null &&
      depth == null &&
      injectionOrder == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (anchor != null) 'anchor': anchor,
    if (injectionPosition != null) 'injectionPosition': injectionPosition,
    if (depth != null) 'depth': depth,
    if (injectionOrder != null) 'injectionOrder': injectionOrder,
  };
}

class PromptBlockActivation {
  const PromptBlockActivation({this.generationTriggers = const <String>[]});

  factory PromptBlockActivation.fromJson(Map<String, dynamic> json) {
    final raw = json['generationTriggers'];
    return PromptBlockActivation(
      generationTriggers: raw is List
          ? raw
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }

  final List<String> generationTriggers;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'generationTriggers': generationTriggers,
  };
}

class PromptBlockPriority {
  const PromptBlockPriority({this.sortOrder = 0, this.injectionOrder});

  factory PromptBlockPriority.fromJson(Map<String, dynamic> json) {
    return PromptBlockPriority(
      sortOrder: _intOrNull(json['sortOrder']) ?? 0,
      injectionOrder: _intOrNull(json['injectionOrder']),
    );
  }

  final int sortOrder;
  final int? injectionOrder;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'sortOrder': sortOrder,
    if (injectionOrder != null) 'injectionOrder': injectionOrder,
  };
}

class PromptBlockProtection {
  const PromptBlockProtection({
    this.locked = false,
    this.forbidOverride = false,
  });

  factory PromptBlockProtection.fromJson(Map<String, dynamic> json) {
    return PromptBlockProtection(
      locked: json['locked'] == true,
      forbidOverride: json['forbidOverride'] == true,
    );
  }

  final bool locked;
  final bool forbidOverride;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'locked': locked,
    'forbidOverride': forbidOverride,
  };
}

class PromptBlockProvenance {
  const PromptBlockProvenance({
    this.source = 'app',
    this.identifier,
    this.extension = false,
  });

  factory PromptBlockProvenance.fromJson(Map<String, dynamic> json) {
    return PromptBlockProvenance(
      source: (json['source'] ?? 'app').toString(),
      identifier: _stringOrNull(json['identifier']),
      extension: json['extension'] == true,
    );
  }

  final String source;
  final String? identifier;
  final bool extension;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'source': source,
    if (identifier != null) 'identifier': identifier,
    'extension': extension,
  };
}

/// A prompt block in the V2 shape.
class PromptBlock {
  const PromptBlock({
    required this.id,
    required this.kind,
    required this.name,
    this.promptProfileId,
    this.enabled = true,
    this.content = '',
    this.role,
    this.placement = const PromptBlockPlacement(),
    this.activation = const PromptBlockActivation(),
    this.priority = const PromptBlockPriority(),
    this.protection = const PromptBlockProtection(),
    this.provenance = const PromptBlockProvenance(),
    this.extensions = const <String, dynamic>{},
  });

  factory PromptBlock.fromJson(Map<String, dynamic> json) {
    return PromptBlock(
      id: (json['id'] ?? '').toString(),
      promptProfileId: _stringOrNull(json['promptProfileId']),
      kind: normalizePromptBlockKind((json['kind'] ?? '').toString()),
      name: (json['name'] ?? '').toString(),
      enabled: json['enabled'] != false,
      content: (json['content'] ?? '').toString(),
      role: _stringOrNull(json['role']),
      placement: PromptBlockPlacement.fromJson(_asMap(json['placement'])),
      activation: PromptBlockActivation.fromJson(_asMap(json['activation'])),
      priority: PromptBlockPriority.fromJson(_asMap(json['priority'])),
      protection: PromptBlockProtection.fromJson(_asMap(json['protection'])),
      provenance: PromptBlockProvenance.fromJson(_asMap(json['provenance'])),
      extensions: _asMap(json['extensions']),
    );
  }

  final String id;
  final String? promptProfileId;

  /// Open string in `"<namespace>:<name>"` form. Migrated V1 kinds carry the
  /// `core:` namespace.
  final String kind;

  final String name;
  final bool enabled;
  final String content;
  final String? role;
  final PromptBlockPlacement placement;
  final PromptBlockActivation activation;
  final PromptBlockPriority priority;
  final PromptBlockProtection protection;
  final PromptBlockProvenance provenance;

  /// Opaque third-party payloads, keyed by namespace. The compiler never reads,
  /// mutates, reorders or drops anything in here. Unknown V1 keys land under
  /// the reserved `legacy_v1` namespace.
  final Map<String, dynamic> extensions;

  /// V1 exposed an `isMarker` convenience getter. V2 does not carry a boolean;
  /// this is the one supported spelling of the question.
  bool get isMarker => kind == '$kCorePromptBlockKindNamespace:marker';

  /// Bare name with the namespace stripped, for call sites that switch on the
  /// core vocabulary. Returns the whole string when there is no namespace.
  String get kindName {
    final idx = kind.indexOf(':');
    return idx < 0 ? kind : kind.substring(idx + 1);
  }

  bool get isCoreKind =>
      kind.startsWith('$kCorePromptBlockKindNamespace:') || !kind.contains(':');

  PromptBlock copyWith({
    String? id,
    String? kind,
    String? name,
    String? promptProfileId,
    bool? enabled,
    String? content,
    String? role,
    PromptBlockPlacement? placement,
    PromptBlockActivation? activation,
    PromptBlockPriority? priority,
    PromptBlockProtection? protection,
    PromptBlockProvenance? provenance,
    Map<String, dynamic>? extensions,
  }) {
    return PromptBlock(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      promptProfileId: promptProfileId ?? this.promptProfileId,
      enabled: enabled ?? this.enabled,
      content: content ?? this.content,
      role: role ?? this.role,
      placement: placement ?? this.placement,
      activation: activation ?? this.activation,
      priority: priority ?? this.priority,
      protection: protection ?? this.protection,
      provenance: provenance ?? this.provenance,
      extensions: extensions ?? this.extensions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schemaVersion': kPromptBlockSchemaVersion,
    'id': id,
    if (promptProfileId != null) 'promptProfileId': promptProfileId,
    'kind': kind,
    'name': name,
    'enabled': enabled,
    'content': content,
    if (role != null) 'role': role,
    'placement': placement.toJson(),
    'activation': activation.toJson(),
    'priority': priority.toJson(),
    'protection': protection.toJson(),
    'provenance': provenance.toJson(),
    if (extensions.isNotEmpty) 'extensions': extensions,
  };
}

/// The fifteen built-in kind names, bare.
///
/// `core:` is a reserved namespace (see
/// `openspec/specs/prompt-block-schema/spec.md`), so
/// only these fifteen may carry it. Held as bare names because both the wire
/// format and the V1 enum spell them that way.
const Set<String> kCorePromptBlockKindNames = <String>{
  'systemPrompt',
  'persona',
  'characterDescription',
  'characterPersonality',
  'characterScenario',
  'exampleMessages',
  'worldInfo',
  'worldInfoAfter',
  'authorNote',
  'postHistoryInstructions',
  'nsfw',
  'chatHistory',
  'enhanceDefinitions',
  'marker',
  'custom',
};

/// Resolves a raw `kind` string to its V2 form.
///
/// Three cases, per `openspec/specs/prompt-block-schema/spec.md`:
///
/// * A bare name that IS one of the fifteen built-ins gains the `core:`
///   namespace.
/// * A bare name that is NOT built-in normalises to `core:custom`, the routing
///   table's default rule. It must not be minted into a `core:` kind of its
///   own: `core:` is reserved for the built-in vocabulary, so
///   `core:someFutureKindV9` would claim that namespace for a kind the
///   planner's marker mapping has no arm for. This also reproduces V1, whose
///   `firstWhere(..., orElse: () => custom)` filed an unrecognised kind as
///   `custom`.
/// * A string that already carries a namespace is returned untouched, which is
///   what keeps a third-party `vendorx:thing` from being reclassified.
String normalizePromptBlockKind(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return '$kCorePromptBlockKindNamespace:custom';
  }
  if (trimmed.contains(':')) {
    return trimmed;
  }
  if (!kCorePromptBlockKindNames.contains(trimmed)) {
    return '$kCorePromptBlockKindNamespace:custom';
  }
  return '$kCorePromptBlockKindNamespace:$trimmed';
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
