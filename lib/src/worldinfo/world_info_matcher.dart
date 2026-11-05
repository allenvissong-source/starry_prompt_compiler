// Package-internal service: WorldInfoMatcher.
//
// Provenance: extracted verbatim from
//   lib/features/chat_character/presentation/providers/world_info_providers.dart
// (class `WorldInfoMatcher`, lines 13..153 in the Starry source, sibling
// class `WorldInfoContextResolver` intentionally left behind because it
// depends on Repositories / Riverpod / Persona / CharacterEntities —
// host-side concerns that belong to host-side wiring).
//
// Imports: only `world_info.dart` — the Starry source pulled in Flutter
// foundation, Riverpod, session_prompt_context, character_assembly_models,
// persona, starry_providers, preset_repository, resource_binding_repository,
// worldbook_repository, character_entities exclusively for the Resolver
// class; the Matcher itself is pure Dart over WorldInfoEntry /
// WorldInfoMatchContext / WorldInfoPosition / WorldInfoScanSource.
//
// Class / method / field / parameter names byte-identical to the Starry
// source, including the `const` ctor, so downstream call sites and
// characterization goldens stay valid under SUT=package.

import 'dart:collection';

import '../models/world_info.dart';
import '../models/worldbook_entities.dart';
import 'text_recall.dart';

/// Why an entry entered the match set.
enum WorldInfoActivationReason {
  /// A primary key matched the scanned text (secondary-key logic satisfied).
  keyword,

  /// The entry is always-on: `constant == true`, or it declares no keys.
  constant,

  /// No key matched literally, but lexical recall scored the entry as relevant.
  ///
  /// A supplement to keyword matching, never a replacement: entries reached this
  /// way still pass every gate a keyword match passes.
  semantic,
}

/// Lexical-recall reach settings for one matching pass.
///
/// **There is no on/off field, by design.** Recall is not a feature — it is the
/// repair for substring matching being broken in Chinese. An author writing the key
/// 「米雪儿的父亲」 means it to fire when the user says 「你父亲怎么了」, and
/// `contains` cannot see the shared 父亲. A switch would leave the broken behavior
/// reachable, and since the symptom is a *missing* injection — no error, no
/// warning, just a character that seems not to know its own backstory — a switch
/// left in the wrong position would never be discovered.
///
/// Two measurements make always-on safe rather than merely principled:
///
///  * **precision** — with [requireKeyOverlap] the bundled assets show 7 wanted
///    recalls and **zero** false ones; small talk such as 「今天天气不错」 recalls
///    nothing (`text_recall_calibration_test.dart`);
///  * **cost** — key screening keeps this at ~0.3ms for a typical binding and
///    ~10ms at 1100 entries, against an end-to-end budget measured in seconds.
///
/// What remains configurable is *reach*: [minScore] and [maxCandidates] widen or
/// narrow the channel, the way `recursive_scanning`'s depth tunes cascading. Those
/// are creative judgments an author can reasonably make; "should Chinese matching
/// work" is not.
class WorldInfoRecallOptions {
  const WorldInfoRecallOptions({
    this.minScore = defaultMinScore,
    this.maxCandidates = defaultMaxCandidates,
    this.requireKeyOverlap = true,
  });

  /// Score floor. Deliberately low: it only discards near-zero noise, because a
  /// raw BM25 score cannot decide relevance on its own — the real gate is
  /// [requireKeyOverlap].
  ///
  /// Calibrated on the bundled assets, where the wanted and unwanted score
  /// ranges overlap outright (see `text_recall_calibration_test.dart`):
  /// 「欧泊是干什么的」 recalls the right entry at **0.727** while 「晚饭吃什么」
  /// scores junk at **2.198**. Any floor admitting the former also admits the
  /// latter, so raising this value cannot fix precision — it would only start
  /// dropping correct recalls.
  static const double defaultMinScore = 0.3;

  /// Cap on recall-only entries per pass. Recall is a supplement, so it must not
  /// be able to flood a turn with low-confidence lore.
  static const int defaultMaxCandidates = 3;

  /// The shipped defaults, stated explicitly for readability at call sites.
  static const WorldInfoRecallOptions standard = WorldInfoRecallOptions();

  /// Zero-reach settings, used only by [WorldInfoMatcher.findMatchingEntries] to
  /// describe the keyword engine on its own.
  ///
  /// Expressed as "admit no candidates" rather than as a disable flag: a cap of
  /// zero is a coherent point on the same scale as a cap of three, whereas a
  /// boolean would reintroduce exactly the switch this class does not want to
  /// offer. It is **not** a supported production configuration — see
  /// [WorldInfoMatcher.findMatchingEntries] for why the legacy projection needs it.
  static const WorldInfoRecallOptions keywordOnlyBaseline =
      WorldInfoRecallOptions(maxCandidates: 0);

  final double minScore;
  final int maxCandidates;

  /// Require the query to share a token with one of the entry's own keys.
  ///
  /// This — not the score — is what makes recall precise. It keeps recall
  /// anchored to what the author actually declared: the channel widens *how* a
  /// key can be reached (「你父亲怎么了」 now finds the key 「米雪儿的父亲」 via
  /// the shared 父亲 bigram) without inventing relevance the author never
  /// expressed. Body-only matches are exactly the junk case: 「晚饭吃什么」 hits
  /// an entry's prose through the function word 什么 and would otherwise inject
  /// unrelated lore into small talk.
  ///
  /// Measured on the bundled assets, this gate removes every false recall in the
  /// control set while keeping every wanted one.
  final bool requireKeyOverlap;
}

/// One matched entry plus the metadata callers need to explain the match.
///
/// [matchedKey] is the primary key that actually fired, taken from the entry's
/// own `keys` list verbatim (never lower-cased), so hosts can show *why* an
/// entry was injected. It is `null` for [WorldInfoActivationReason.constant].
class WorldInfoMatch {
  const WorldInfoMatch({
    required this.entry,
    required this.activationReason,
    this.matchedKey,
    this.score,
  });

  final WorldInfoEntry entry;
  final WorldInfoActivationReason activationReason;
  final String? matchedKey;

  /// Lexical-recall score, set only for [WorldInfoActivationReason.semantic].
  ///
  /// Logged by hosts so a probabilistic injection can be explained after the
  /// fact — a requirement once matching stops being purely literal.
  final double? score;
}

class WorldInfoMatcher {
  const WorldInfoMatcher({this.tokenizer = const BigramRecallTokenizer()});

  /// How recall splits text into tokens.
  ///
  /// Defaults to [BigramRecallTokenizer]. Omitting it reproduces the previous
  /// behavior exactly; supplying one is how a host raises Chinese segmentation
  /// precision without this package taking on a dependency or doing I/O.
  final RecallTokenizer tokenizer;

  /// Entry-only projection of [findMatchingEntriesWithMetadata].
  ///
  /// Kept as the original signature so existing call sites and the
  /// characterization goldens stay valid; it delegates so the matching rules
  /// (recursion, probability, selective logic, scan scoping) exist exactly once.
  ///
  /// Runs the **keyword engine alone**, unlike the metadata variant. Two reasons,
  /// and neither is "recall is optional":
  ///
  ///  * the characterization goldens pin this method, and their job is to detect
  ///    unintended drift in keyword matching. Folding recall in would rewrite the
  ///    very baseline they compare against;
  ///  * this signature cannot report *why* an entry matched, and a recall hit that
  ///    cannot be explained is precisely what should not reach a caller.
  ///
  /// Production paths use [findMatchingEntriesWithMetadata], where recall always
  /// runs.
  ///
  List<WorldInfoEntry> findMatchingEntries({
    required WorldInfoMatchContext context,
    required List<WorldInfoEntry> entries,
    required String characterId,
    required List<String> characterTags,
    int maxRecursionDepth = 3,
    Map<String, Worldbook> worldbooks = const <String, Worldbook>{},
    String? generationTrigger,
  }) {
    return findMatchingEntriesWithMetadata(
      context: context,
      entries: entries,
      characterId: characterId,
      characterTags: characterTags,
      maxRecursionDepth: maxRecursionDepth,
      worldbooks: worldbooks,
      generationTrigger: generationTrigger,
      recall: WorldInfoRecallOptions.keywordOnlyBaseline,
    ).map((match) => match.entry).toList(growable: false);
  }

  /// Same matching pass as [findMatchingEntries], but reports the key that fired
  /// and runs lexical recall — which always runs, because substring matching is
  /// broken for Chinese and [WorldInfoRecallOptions] offers no way to disable it.
  List<WorldInfoMatch> findMatchingEntriesWithMetadata({
    required WorldInfoMatchContext context,
    required List<WorldInfoEntry> entries,
    required String characterId,
    required List<String> characterTags,
    int maxRecursionDepth = 3,
    Map<String, Worldbook> worldbooks = const <String, Worldbook>{},
    String? generationTrigger,
    WorldInfoRecallOptions recall = WorldInfoRecallOptions.standard,
  }) {
    final allMatched = <WorldInfoMatch>[];
    final processedIds = <String>{};
    final cascade = <String>[];
    var recursionDepth = 0;
    final recursionLimit = worldbooks.isEmpty
        ? maxRecursionDepth
        : entries.fold<int>(0, (depth, entry) {
            final book = worldbooks[entry.worldbookId];
            final limit = book == null
                ? maxRecursionDepth
                : book.recursiveScanning
                ? book.maxRecursionDepth
                : 0;
            return limit > depth ? limit : depth;
          });
    final scanText = <String, String>{
      for (final entry in entries)
        entry.id: context.scopedText(
          entry.runtimePolicy.targeting.scanSources,
          entry.scanDepth ?? worldbooks[entry.worldbookId]?.scanDepth,
        ),
    };

    // Delay levels open one at a time, lowest first, mirroring SillyTavern's
    // `availableRecursionDelayLevels`. Deduplicated and sorted so the order is a
    // pure function of the entry set rather than of map iteration.
    final pendingDelayLevels = SplayTreeSet<int>();
    for (final entry in entries) {
      final level = entry.effectiveDelayLevel;
      if (level != null) pendingDelayLevels.add(level);
    }
    // The lowest level is consumed up front, exactly as SillyTavern does
    // (`currentRecursionDelayLevel = available.shift() ?? 0`). Two behaviors
    // depend on this and both would be wrong if the loop opened it instead:
    // level 1 must already be open during the *first* recursion pass rather than
    // costing a depth step, and only the levels still queued afterwards may
    // extend scanning past the point where cascading stops.
    var currentDelayLevel = 0;
    if (pendingDelayLevels.isNotEmpty) {
      currentDelayLevel = pendingDelayLevels.first;
      pendingDelayLevels.remove(currentDelayLevel);
    }

    while (recursionDepth <= recursionLimit) {
      final isRecursionPass = recursionDepth != 0;
      final newMatches = <WorldInfoMatch>[];
      for (final entry in entries) {
        if (processedIds.contains(entry.id)) continue;
        final book = worldbooks[entry.worldbookId];
        if (isRecursionPass &&
            book != null &&
            (!book.recursiveScanning ||
                recursionDepth > book.maxRecursionDepth)) {
          continue;
        }
        // "Non-recursable": refuses to be activated *by another entry*. A direct
        // hit on the user's own text still counts, which is why this is scoped to
        // recursion passes only.
        if (entry.excludeRecursion && isRecursionPass) continue;
        // "Delay until recursion": invisible outside recursion, and inside it
        // only once its level has been opened.
        final delayLevel = entry.effectiveDelayLevel;
        if (delayLevel != null &&
            (!isRecursionPass || delayLevel > currentDelayLevel)) {
          continue;
        }
        final matchedKey = _matchedPrimaryKey(
          entry: entry,
          scopedContext: [
            scanText[entry.id]!,
            if (entry.runtimePolicy.targeting.scanSources.isEmpty ||
                entry.runtimePolicy.targeting.scanSources.contains(
                  WorldInfoScanSource.history,
                ))
              ...cascade,
          ].join('\n'),
          characterId: characterId,
          characterTags: characterTags,
          generationTrigger: generationTrigger,
        );
        if (matchedKey == null) continue;
        newMatches.add(
          WorldInfoMatch(
            entry: entry,
            activationReason: WorldInfoActivationReason.keyword,
            matchedKey: matchedKey,
          ),
        );
      }

      // Only entries that may feed the cascade extend the scan text. This is
      // SillyTavern's `successfulNewEntries.filter(x => !x.preventRecursion)`:
      // "Prevent further recursion" still injects the entry, it just withholds
      // its text from the next pass.
      final cascadeText = <String>[];
      for (final match in newMatches) {
        processedIds.add(match.entry.id);
        allMatched.add(match);
        if (!match.entry.preventRecursion &&
            (worldbooks[match.entry.worldbookId]?.allowEntryCascade ?? true)) {
          cascadeText.add(match.entry.content);
        }
      }

      if (cascadeText.isEmpty) {
        // Cascading has stalled. SillyTavern's escape hatch — advance to the next
        // queued delay level and keep scanning — applies only when a level is
        // still queued, so a lone delayed entry with nothing to trigger it stays
        // silent instead of quietly firing anyway.
        final nextLevel = pendingDelayLevels.firstOrNull;
        if (nextLevel == null || recursionDepth >= recursionLimit) break;
        pendingDelayLevels.remove(nextLevel);
        currentDelayLevel = nextLevel;
        // Delayed entries only activate inside a recursion pass, so make sure the
        // next iteration is one even if the very first pass matched nothing.
        recursionDepth = recursionDepth == 0 ? 1 : recursionDepth + 1;
        continue;
      }

      cascade.addAll(cascadeText);
      recursionDepth++;
    }

    allMatched.addAll(
      _recallMatches(
        context: context,
        entries: entries,
        characterId: characterId,
        characterTags: characterTags,
        generationTrigger: generationTrigger,
        processedIds: processedIds,
        recall: recall,
        scanText: scanText,
      ),
    );

    for (final entry in entries) {
      final isConstant = entry.constant || entry.keys.isEmpty;
      if (!entry.enabled || !isConstant || processedIds.contains(entry.id)) {
        continue;
      }
      if (!entry.appliesToCharacter(characterId, characterTags)) {
        continue;
      }
      if (!entry.supportsGenerationTrigger(generationTrigger)) {
        continue;
      }
      allMatched.add(
        WorldInfoMatch(
          entry: entry,
          activationReason: WorldInfoActivationReason.constant,
        ),
      );
      processedIds.add(entry.id);
    }

    allMatched.sort(
      (a, b) => a.entry.insertionOrder.compareTo(b.entry.insertionOrder),
    );
    return allMatched;
  }

  /// Lexical-recall candidates for entries no keyword reached.
  ///
  /// Runs after keyword matching and before the constant sweep, and mutates
  /// [processedIds] so the sweep does not re-add an entry recall already took.
  ///
  /// Four deliberate limits:
  ///
  ///  * every gate a keyword match must pass is enforced here too — `enabled`,
  ///    character filter, generation trigger, probability, and the entry's
  ///    `selectiveLogic` against its secondary keys. Recall widens *how* an entry
  ///    can be reached, never *whether* its author-declared conditions apply;
  ///  * recall candidates never feed the cascade. Cascading already over-expands
  ///    on cross-referencing books (one 「崩溃症」 once pulled in 21 entries), and
  ///    seeding it with probabilistic hits would compound that;
  ///  * a delayed entry is skipped entirely. Its author said "reach me only
  ///    through another entry", and recall fires straight off the user's text, so
  ///    scoring it would route around the very gate that was requested. The
  ///    recursion flags need no such rule: `excludeRecursion` only blocks other
  ///    *entries* (recall is not one), and `preventRecursion` restricts what an
  ///    entry emits, which recall never uses;
  ///  * the query is the entry's own scan scope, so an entry that opted into
  ///    scanning the card description is scored against the same text a keyword
  ///    would have been.
  List<WorldInfoMatch> _recallMatches({
    required WorldInfoMatchContext context,
    required List<WorldInfoEntry> entries,
    required String characterId,
    required List<String> characterTags,
    required String? generationTrigger,
    required Set<String> processedIds,
    required WorldInfoRecallOptions recall,
    required Map<String, String> scanText,
  }) {
    if (recall.maxCandidates <= 0) return const <WorldInfoMatch>[];

    final eligible = <WorldInfoEntry>[];
    for (final entry in entries) {
      if (processedIds.contains(entry.id)) continue;
      if (!entry.enabled) continue;
      // A constant entry is already unconditionally admitted by the sweep below;
      // scoring it would only risk reporting it as a recall hit instead.
      if (entry.constant || entry.keys.isEmpty) continue;
      if (entry.effectiveDelayLevel != null) continue;
      if (!entry.appliesToCharacter(characterId, characterTags)) continue;
      if (!entry.supportsGenerationTrigger(generationTrigger)) continue;
      if (!entry.shouldTriggerByProbability()) continue;
      eligible.add(entry);
    }
    if (eligible.isEmpty) return const <WorldInfoMatch>[];

    // The corpus is every eligible entry, so IDF reflects this request only and a
    // repeated request scores identically.
    final documents = <RecallDocument>[
      for (final entry in eligible)
        RecallDocument(
          id: entry.id,
          text: '${entry.comment}\n${entry.content}',
          keys: <String>[...entry.keys, ...entry.secondaryKeys],
        ),
    ];
    final byId = <String, WorldInfoEntry>{
      for (final entry in eligible) entry.id: entry,
    };

    final matches = <WorldInfoMatch>[];
    final ranker = Bm25Ranker(tokenizer: tokenizer);
    final scopedHits =
        [
          for (final query
              in eligible.map((entry) => scanText[entry.id]!).toSet())
            for (final hit in ranker.rank(
              query: query,
              documents: documents,
              requireKeyOverlap: recall.requireKeyOverlap,
            ))
              if (scanText[hit.documentId] == query) hit,
        ]..sort((a, b) {
          final score = b.score.compareTo(a.score);
          return score != 0 ? score : a.documentId.compareTo(b.documentId);
        });
    for (final hit in scopedHits) {
      if (matches.length >= recall.maxCandidates) break;
      // sorted desc: no later hit passes
      if (hit.score < recall.minScore) break;
      // The precision gate. Without it recall drifts into body-text similarity
      // and injects lore on function words alone (「晚饭吃什么」 → an entry whose
      // prose contains 什么). Note this cannot be a score threshold instead:
      // wanted hits score as low as 0.727 while that junk hit scores 2.198.
      //
      // The ranker applies the same gate while screening (so it can skip
      // tokenizing ineligible bodies); this re-check keeps the rule true here
      // regardless of how the ranker is implemented.
      if (recall.requireKeyOverlap && hit.bestKey == null) continue;
      final entry = byId[hit.documentId];
      if (entry == null) continue;
      final scoped = scanText[entry.id]!;
      final haystack = entry.caseSensitive ? scoped : scoped.toLowerCase();
      if (!_satisfiesSecondaryKeys(entry: entry, haystack: haystack)) continue;
      processedIds.add(entry.id);
      matches.add(
        WorldInfoMatch(
          entry: entry,
          activationReason: WorldInfoActivationReason.semantic,
          matchedKey: hit.bestKey,
          score: hit.score,
        ),
      );
    }
    return matches;
  }

  Map<WorldInfoPosition, List<WorldInfoEntry>> groupByPosition(
    List<WorldInfoEntry> entries,
  ) {
    final grouped = <WorldInfoPosition, List<WorldInfoEntry>>{};
    for (final entry in entries) {
      grouped.putIfAbsent(entry.position, () => <WorldInfoEntry>[]).add(entry);
    }
    return grouped;
  }

  /// Returns the primary key that fired, or `null` when the entry does not match.
  ///
  /// Replaces the former boolean `_matchesEntry`: the caller needs the key
  /// itself, and running the scan twice (once to test, once to find the key)
  /// would risk the two passes disagreeing.
  String? _matchedPrimaryKey({
    required WorldInfoEntry entry,
    required String scopedContext,
    required String characterId,
    required List<String> characterTags,
    required String? generationTrigger,
  }) {
    if (!entry.enabled) return null;
    if (!entry.appliesToCharacter(characterId, characterTags)) return null;
    if (!entry.supportsGenerationTrigger(generationTrigger)) return null;
    if (!entry.shouldTriggerByProbability()) return null;
    if (entry.keys.isEmpty) return null;

    final haystack = entry.caseSensitive
        ? scopedContext
        : scopedContext.toLowerCase();

    String? matchedKey;
    for (final rawKey in entry.keys) {
      final key = rawKey.trim();
      if (key.isEmpty) continue;
      if (_matchesKey(entry: entry, haystack: haystack, key: key)) {
        matchedKey = rawKey;
        break;
      }
    }

    if (matchedKey == null) return null;
    if (!_satisfiesSecondaryKeys(entry: entry, haystack: haystack)) return null;
    return matchedKey;
  }

  /// Applies the entry's multi-key activation logic against its secondary keys.
  ///
  /// Mirrors SillyTavern's `selectiveLogic` semantics:
  /// 0=AND_ANY, 1=NOT_ALL, 2=NOT_ANY, 3=AND_ALL. Called only after a primary key
  /// has matched, so each branch decides whether the secondary keys confirm or
  /// veto that match.
  bool _satisfiesSecondaryKeys({
    required WorldInfoEntry entry,
    required String haystack,
  }) {
    if (!entry.selective) return true;

    final keys = entry.secondaryKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (keys.isEmpty) return true;

    var matchedCount = 0;
    for (final key in keys) {
      if (_matchesKey(entry: entry, haystack: haystack, key: key)) {
        matchedCount++;
      }
    }
    final anyMatched = matchedCount > 0;
    final allMatched = matchedCount == keys.length;

    return switch (entry.selectiveLogic) {
      1 => !allMatched, // NOT_ALL
      2 => !anyMatched, // NOT_ANY
      3 => allMatched, // AND_ALL
      _ => anyMatched, // AND_ANY (0) and any unknown value
    };
  }

  /// Matches a single key against [haystack] using the entry's matching rules.
  ///
  /// Shared by primary and secondary keys so both honor `caseSensitive` and
  /// `matchWholeWords` identically.
  bool _matchesKey({
    required WorldInfoEntry entry,
    required String haystack,
    required String key,
  }) {
    final needle = entry.caseSensitive ? key : key.toLowerCase();
    if (needle.isEmpty) return false;
    if (entry.matchWholeWords) {
      return _matchesWholeWord(haystack: haystack, needle: needle);
    }
    return haystack.contains(needle);
  }

  /// Whole-word matching that also works for scripts written without spaces.
  ///
  /// `\b` is defined against `\w`, which contains no CJK character, so for a
  /// Chinese needle *both* sides of the assertion always fail. Measured:
  /// `RegExp(r'\b塔\b')` returns false for 「塔罗牌」 **and** for 「塔」 standing
  /// alone. So the old behavior was not "too loose" — with `matchWholeWords: true`
  /// a Chinese key could never match anything, silently disabling the entry.
  ///
  /// For a CJK needle we therefore assert our own boundary: the characters
  /// immediately around the occurrence must not themselves be CJK. That gives the
  /// flag its intended meaning — 「塔」 stops matching inside 「塔罗牌」 while a
  /// standalone 「塔」 matches — so an author finally has a way to narrow a broad
  /// key. Latin and mixed needles keep `\b`, so behavior for keys like `P.U.S.`
  /// is untouched.
  ///
  /// **The cost, measured.** Chinese is written without separators, so "neither
  /// side is CJK" is in practice "punctuation or a string boundary on both sides"
  /// — a condition mid-sentence text almost never meets. Since the flag is
  /// entry-level, it narrows *every* key on the entry: with it on,
  /// 「科摩斯塔是什么」 stops matching the key 「科摩斯塔」 (the following 是 is
  /// CJK), and only lexical recall still reaches the entry. So this is not a free
  /// win over a broad key: it trades false hits for lost hits on the same entry's
  /// longer keys, and the author is the only one who can judge that trade. The
  /// inbound translator warns about single-character CJK keys for exactly this
  /// reason instead of setting this flag on their behalf.
  ///
  /// Note the flag is opt-in and off by default, so this changes nothing for
  /// assets that never set it.
  bool _matchesWholeWord({required String haystack, required String needle}) {
    if (!_isCjkText(needle)) {
      final regex = RegExp(r'\b' + RegExp.escape(needle) + r'\b');
      return regex.hasMatch(haystack);
    }
    var from = 0;
    while (true) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) return false;
      final beforeOk =
          index == 0 || !_isCjkCodeUnit(haystack.codeUnitAt(index - 1));
      final endIndex = index + needle.length;
      final afterOk =
          endIndex >= haystack.length ||
          !_isCjkCodeUnit(haystack.codeUnitAt(endIndex));
      if (beforeOk && afterOk) return true;
      from = index + 1;
    }
  }

  /// True when every character of [text] is CJK (so `\b` cannot apply).
  bool _isCjkText(String text) {
    if (text.isEmpty) return false;
    for (final unit in text.codeUnits) {
      if (!_isCjkCodeUnit(unit)) return false;
    }
    return true;
  }

  bool _isCjkCodeUnit(int unit) {
    return (unit >= 0x4E00 && unit <= 0x9FFF) ||
        (unit >= 0x3400 && unit <= 0x4DBF) ||
        (unit >= 0xF900 && unit <= 0xFAFF) ||
        (unit >= 0x3040 && unit <= 0x30FF);
  }
}
