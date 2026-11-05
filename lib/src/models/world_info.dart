// Package-internal model: world info entries + runtime policy + resolution.
//
// Provenance: verbatim copy of
//   lib/features/chat_character/data/models/world_info.dart
// Import rewrite only:
//   package:starry/features/starry/domain/models/worldbook_entities.dart
//     as starry_worldbook
//   -> 'worldbook_entities.dart' as starry_worldbook
// The `starry_worldbook.WorldbookEntry` alias inside
// `WorldInfoEntry.fromCanonicalEntry` is preserved so downstream call
// sites remain byte-identical to the Starry source. Class/field/enum
// names are byte-identical to the Starry source.

import 'worldbook_entities.dart' as starry_worldbook;

enum WorldInfoPosition {
  before,
  after,
  anTop,
  anBottom,
  atDepth,
  emTop,
  emBottom,
  outlet,
}

WorldInfoPosition worldInfoPositionFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'after':
    case 'after_char':
    case 'afterchardefs':
      return WorldInfoPosition.after;
    case 'before_author_note':
    case 'antop':
      return WorldInfoPosition.anTop;
    case 'after_author_note':
    case 'anbottom':
      return WorldInfoPosition.anBottom;
    case 'at_depth':
    case 'atdepth':
      return WorldInfoPosition.atDepth;
    case 'before_example':
    case 'emtop':
      return WorldInfoPosition.emTop;
    case 'after_example':
    case 'embottom':
      return WorldInfoPosition.emBottom;
    case 'outlet':
      return WorldInfoPosition.outlet;
    case 'before':
    case 'before_char':
    case 'beforechardefs':
    default:
      return WorldInfoPosition.before;
  }
}

enum WorldInfoScanSource {
  history,
  personaDescription,
  characterDescription,
  characterPersonality,
  characterDepthPrompt,
  scenario,
  creatorNotes,
  authorNote,
}

WorldInfoScanSource? worldInfoScanSourceFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'history':
      return WorldInfoScanSource.history;
    case 'persona_description':
      return WorldInfoScanSource.personaDescription;
    case 'character_description':
      return WorldInfoScanSource.characterDescription;
    case 'character_personality':
      return WorldInfoScanSource.characterPersonality;
    case 'character_depth_prompt':
      return WorldInfoScanSource.characterDepthPrompt;
    case 'scenario':
      return WorldInfoScanSource.scenario;
    case 'creator_notes':
      return WorldInfoScanSource.creatorNotes;
    case 'author_note':
      return WorldInfoScanSource.authorNote;
    default:
      return null;
  }
}

class WorldInfoActivationPolicy {
  const WorldInfoActivationPolicy({
    this.generationTriggers = const <String>[],
    this.delayLevel,
  });

  final List<String> generationTriggers;

  /// Recursion level at which a delayed entry unlocks, or `null` for none.
  ///
  /// Populated when the source dialect carries an explicit level (SillyTavern
  /// types `delayUntilRecursion` as `bool | number`, the number being the level;
  /// the inbound translator splits that into the boolean gate plus this value).
  /// `null` means "no explicit level", so a delayed entry unlocks at the first
  /// recursion pass — which is also how SillyTavern reads its own `true`.
  ///
  /// Meaningless on its own: an entry is delayed only if the boolean gate says
  /// so, and consumers must check that first.
  final int? delayLevel;

  bool supportsGenerationTrigger(String? trigger) {
    if (generationTriggers.isEmpty) return true;
    final normalized = (trigger ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return generationTriggers.any(
      (item) => item.trim().toLowerCase() == normalized,
    );
  }
}

class WorldInfoBudgetPolicy {
  const WorldInfoBudgetPolicy({this.ignoreLimit = false, this.tier});

  final bool ignoreLimit;

  /// Budget precedence tier (`mandatory` / `high` / `normal` / `low`).
  ///
  /// Populated when the source dialect carries an explicit allocation priority
  /// (SillyTavern's `weight`, translated to a tier at import time). `null` means
  /// "no explicit tier", and the planner falls back to deriving one from
  /// [ignoreLimit].
  final String? tier;
}

class WorldInfoTargetingPolicy {
  const WorldInfoTargetingPolicy({
    this.scanSources = const <WorldInfoScanSource>[],
  });

  final List<WorldInfoScanSource> scanSources;
}

class WorldInfoOutputPolicy {
  const WorldInfoOutputPolicy({this.outlet});

  final String? outlet;
}

class WorldInfoRuntimePolicy {
  const WorldInfoRuntimePolicy({
    this.activation = const WorldInfoActivationPolicy(),
    this.budget = const WorldInfoBudgetPolicy(),
    this.targeting = const WorldInfoTargetingPolicy(),
    this.output = const WorldInfoOutputPolicy(),
  });

  factory WorldInfoRuntimePolicy.fromEntryExtensions(
    Map<String, dynamic> extensions,
  ) {
    final activationPolicy = _map(extensions['activationPolicy']);
    final budgetPolicy = _map(extensions['budgetPolicy']);
    final targetingPolicy = _map(extensions['targetingPolicy']);
    final outputPolicy = _map(extensions['outputPolicy']);
    return WorldInfoRuntimePolicy(
      activation: WorldInfoActivationPolicy(
        generationTriggers: _stringList(
          activationPolicy['generationTriggers'] ?? extensions['triggers'],
        ),
        delayLevel: _delayLevelOrNull(activationPolicy['delayLevel']),
      ),
      budget: WorldInfoBudgetPolicy(
        ignoreLimit:
            budgetPolicy['ignoreLimit'] == true ||
            extensions['ignoreBudget'] == true,
        tier: _normalizedOrNull(budgetPolicy['tier']),
      ),
      targeting: WorldInfoTargetingPolicy(
        scanSources: _scanSourceList(
          targetingPolicy['scanSources'] ?? extensions['scanSources'],
        ),
      ),
      output: WorldInfoOutputPolicy(
        outlet: _normalizedOrNull(
          outputPolicy['outlet'] ?? extensions['outletName'],
        ),
      ),
    );
  }

  final WorldInfoActivationPolicy activation;
  final WorldInfoBudgetPolicy budget;
  final WorldInfoTargetingPolicy targeting;
  final WorldInfoOutputPolicy output;
}

class WorldInfoMatchContext {
  const WorldInfoMatchContext({
    this.history = '',
    this.historyMessages,
    this.personaDescription = '',
    this.characterDescription = '',
    this.characterPersonality = '',
    this.characterDepthPrompt = '',
    this.scenario = '',
    this.creatorNotes = '',
    this.authorNote = '',
  });

  final String history;

  /// Ordered message text, including the pending user message. A flattened
  /// external context may omit this when it has no message boundaries.
  final List<String>? historyMessages;
  final String personaDescription;
  final String characterDescription;
  final String characterPersonality;
  final String characterDepthPrompt;
  final String scenario;
  final String creatorNotes;
  final String authorNote;

  String get mergedText => scopedText();

  String scopedText([
    List<WorldInfoScanSource> sources = const [],
    int? historyDepth,
  ]) {
    final scopedSources = sources.isEmpty
        ? WorldInfoScanSource.values
        : sources;
    final buffer = StringBuffer();
    for (final source in scopedSources) {
      final messages = historyMessages;
      final value = source == WorldInfoScanSource.history && messages != null
          ? (historyDepth == null
                    ? messages
                    : messages.skip(
                        (messages.length -
                            historyDepth.clamp(0, messages.length)),
                      ))
                .join('\n')
          : valueFor(source);
      if (value.trim().isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(value);
    }
    return buffer.toString();
  }

  String valueFor(WorldInfoScanSource source) {
    switch (source) {
      case WorldInfoScanSource.history:
        return history;
      case WorldInfoScanSource.personaDescription:
        return personaDescription;
      case WorldInfoScanSource.characterDescription:
        return characterDescription;
      case WorldInfoScanSource.characterPersonality:
        return characterPersonality;
      case WorldInfoScanSource.characterDepthPrompt:
        return characterDepthPrompt;
      case WorldInfoScanSource.scenario:
        return scenario;
      case WorldInfoScanSource.creatorNotes:
        return creatorNotes;
      case WorldInfoScanSource.authorNote:
        return authorNote;
    }
  }
}

class WorldInfoEntry {
  WorldInfoEntry({
    required this.id,
    required this.worldbookId,
    required this.keys,
    required this.secondaryKeys,
    required this.content,
    required this.comment,
    required this.enabled,
    required this.constant,
    required this.selective,
    required this.insertionOrder,
    required this.caseSensitive,
    required this.matchWholeWords,
    required this.useGroupScoring,
    required this.probability,
    required this.useProbability,
    required this.position,
    required this.depth,
    required this.group,
    required this.groupWeight,
    required this.preventRecursion,
    required this.delayUntilRecursion,
    required this.scanDepth,
    required this.role,
    required this.sticky,
    required this.cooldown,
    required this.delay,
    required this.characterFilter,
    this.selectiveLogic = 0,
    this.excludeRecursion = false,
    this.delayUntilRecursionLevel,
    this.generationTriggers = const <String>[],
    this.ignoreBudget = false,
    this.outletName,
    this.scanSources = const <String>[],
    WorldInfoRuntimePolicy? runtimePolicy,
  }) : runtimePolicy =
           runtimePolicy ??
           WorldInfoRuntimePolicy(
             activation: WorldInfoActivationPolicy(
               generationTriggers: generationTriggers,
               delayLevel: delayUntilRecursionLevel,
             ),
             budget: WorldInfoBudgetPolicy(ignoreLimit: ignoreBudget),
             targeting: WorldInfoTargetingPolicy(
               scanSources: _scanSourceList(scanSources),
             ),
             output: WorldInfoOutputPolicy(outlet: outletName),
           );

  factory WorldInfoEntry.fromCanonicalEntry(
    starry_worldbook.WorldbookEntry entry,
  ) {
    final policy = WorldInfoRuntimePolicy.fromEntryExtensions(entry.extensions);
    return WorldInfoEntry(
      id: entry.id,
      worldbookId: entry.worldbookId,
      keys: entry.keys,
      secondaryKeys: entry.secondaryKeys,
      content: entry.content,
      comment: entry.comment,
      enabled: entry.enabled,
      constant: entry.constant,
      selective: entry.selective,
      selectiveLogic: entry.selectiveLogic,
      insertionOrder: entry.insertionOrder,
      caseSensitive: entry.caseSensitive,
      matchWholeWords: entry.matchWholeWords,
      useGroupScoring: entry.useGroupScoring,
      probability: entry.probability,
      useProbability: entry.useProbability,
      position: worldInfoPositionFromString(entry.position),
      depth: entry.depth,
      group: entry.groupName.isEmpty ? null : entry.groupName,
      groupWeight: entry.groupWeight,
      preventRecursion: entry.preventRecursion,
      excludeRecursion: entry.excludeRecursion,
      delayUntilRecursion: entry.delayUntilRecursion,
      delayUntilRecursionLevel: policy.activation.delayLevel,
      scanDepth: entry.entryScanDepth,
      role: entry.role,
      sticky: entry.sticky,
      cooldown: entry.cooldown,
      delay: entry.delay,
      characterFilter: entry.characterFilter,
      generationTriggers: policy.activation.generationTriggers,
      ignoreBudget: policy.budget.ignoreLimit,
      outletName: policy.output.outlet,
      scanSources: policy.targeting.scanSources
          .map(_scanSourceToWireValue)
          .toList(growable: false),
      runtimePolicy: policy,
    );
  }

  final String id;
  final String worldbookId;
  final List<String> keys;
  final List<String> secondaryKeys;
  final String content;
  final String comment;
  final bool enabled;
  final bool constant;
  final bool selective;

  /// Multi-key activation logic: 0=AND_ANY, 1=NOT_ALL, 2=NOT_ANY, 3=AND_ALL.
  final int selectiveLogic;
  final int insertionOrder;
  final bool caseSensitive;
  final bool matchWholeWords;
  final bool useGroupScoring;
  final int probability;
  final bool useProbability;
  final WorldInfoPosition position;
  final int depth;
  final String? group;
  final int groupWeight;

  /// Whether this entry's content is withheld from the cascade after it fires.
  ///
  /// SillyTavern's "Prevent further recursion": the entry is injected normally,
  /// but its text is not appended to the scan buffer, so it cannot activate
  /// anything downstream. It closes the *exit*, not the entrance.
  final bool preventRecursion;

  /// Whether this entry refuses to be activated by another entry's content.
  ///
  /// SillyTavern's "Non-recursable": a direct hit from the user's own text still
  /// activates it; only recursion passes skip it. It closes the *entrance*, not
  /// the exit — the mirror image of [preventRecursion].
  final bool excludeRecursion;

  /// Whether this entry only activates during a recursion pass.
  ///
  /// The authoritative gate. [delayUntilRecursionLevel] refines *when* within
  /// recursion, but is meaningless while this is `false`.
  final bool delayUntilRecursion;

  /// Recursion level at which a delayed entry unlocks, or `null` for the first
  /// pass.
  ///
  /// Only consult this after [delayUntilRecursion]. The inbound translator
  /// guarantees a level implies the gate, but this layer does not depend on that:
  /// a level without a gate has no meaning, so the boolean always decides.
  final int? delayUntilRecursionLevel;

  /// Null inherits the book's depth; zero scans no history messages.
  final int? scanDepth;
  final int role;
  final int sticky;
  final int cooldown;
  final int delay;
  final Map<String, dynamic> characterFilter;
  final List<String> generationTriggers;
  final bool ignoreBudget;
  final String? outletName;
  final List<String> scanSources;
  final WorldInfoRuntimePolicy runtimePolicy;

  bool supportsGenerationTrigger(String? trigger) {
    return runtimePolicy.activation.supportsGenerationTrigger(trigger);
  }

  /// The recursion level this entry unlocks at, or `null` if it is not delayed.
  ///
  /// The single place the two fields are reconciled, so no caller has to decide
  /// how they interact. [delayUntilRecursion] is authoritative: a level attached
  /// to an undelayed entry is ignored rather than promoted into a delay, which
  /// would inject an entry the author never delayed. A delayed entry with no
  /// level unlocks at 1, matching SillyTavern's reading of its own `true`.
  int? get effectiveDelayLevel {
    if (!delayUntilRecursion) return null;
    final level = delayUntilRecursionLevel;
    if (level == null || level < 1) return 1;
    return level;
  }

  bool appliesToCharacter(String characterId, List<String> tags) {
    final type = (characterFilter['type'] ?? 'none')
        .toString()
        .trim()
        .toLowerCase();
    final ids =
        ((characterFilter['character_ids'] ?? characterFilter['characterIds'])
                as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];
    final filterTags =
        ((characterFilter['tags']) as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];

    switch (type) {
      case 'include':
        return ids.contains(characterId) || filterTags.any(tags.contains);
      case 'exclude':
        return !(ids.contains(characterId) || filterTags.any(tags.contains));
      case 'none':
      default:
        return true;
    }
  }

  bool shouldTriggerByProbability() {
    if (!useProbability || probability <= 0 || probability >= 100) {
      return true;
    }
    return (DateTime.now().millisecondsSinceEpoch % 100) < probability;
  }
}

class WorldInfoResolution {
  const WorldInfoResolution({
    required this.entries,
    required this.groupedEntries,
    required this.candidateWorldInfoIds,
    required this.contextText,
    this.worldbookTokenBudgets = const <String, int>{},
  });

  final List<WorldInfoEntry> entries;
  final Map<WorldInfoPosition, List<WorldInfoEntry>> groupedEntries;
  final List<String> candidateWorldInfoIds;
  final String contextText;
  final Map<String, int> worldbookTokenBudgets;
}

Map<String, dynamic> _map(dynamic raw) {
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<WorldInfoScanSource> _scanSourceList(dynamic raw) {
  final items = _stringList(raw);
  return items
      .map(worldInfoScanSourceFromString)
      .whereType<WorldInfoScanSource>()
      .toList(growable: false);
}

String _scanSourceToWireValue(WorldInfoScanSource source) {
  switch (source) {
    case WorldInfoScanSource.history:
      return 'history';
    case WorldInfoScanSource.personaDescription:
      return 'persona_description';
    case WorldInfoScanSource.characterDescription:
      return 'character_description';
    case WorldInfoScanSource.characterPersonality:
      return 'character_personality';
    case WorldInfoScanSource.characterDepthPrompt:
      return 'character_depth_prompt';
    case WorldInfoScanSource.scenario:
      return 'scenario';
    case WorldInfoScanSource.creatorNotes:
      return 'creator_notes';
    case WorldInfoScanSource.authorNote:
      return 'author_note';
  }
}

String? _normalizedOrNull(dynamic raw) {
  final normalized = (raw ?? '').toString().trim();
  return normalized.isEmpty ? null : normalized;
}

/// Reads a recursion delay level, rejecting anything that is not a real level.
///
/// Values below 1 are discarded rather than clamped: they carry no ordering
/// information, and the absent case already means "unlocks at the first
/// recursion pass".
int? _delayLevelOrNull(dynamic raw) {
  if (raw is bool) return null;
  final int? parsed;
  if (raw is int) {
    parsed = raw;
  } else if (raw is num) {
    parsed = raw.toInt();
  } else if (raw is String) {
    parsed = int.tryParse(raw.trim());
  } else {
    parsed = null;
  }
  if (parsed == null || parsed < 1) return null;
  return parsed;
}
