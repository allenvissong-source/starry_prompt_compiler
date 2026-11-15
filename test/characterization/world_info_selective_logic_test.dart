// Tests for world-info multi-key activation logic (`selectiveLogic`) and the
// budget-tier resolution added alongside it.
//
// Before this, `_matchesEntry` hard-coded AND_ANY semantics: any secondary key
// match confirmed the entry and there was no way to express exclusion. The
// matcher also applied `matchWholeWords` to primary keys only, so secondary keys
// silently fell back to substring matching.
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

WorldInfoEntry _entry({
  String id = 'e1',
  String? uid,
  List<String> keys = const <String>['alpha'],
  List<String> secondaryKeys = const <String>[],
  bool selective = true,
  int selectiveLogic = 0,
  bool caseSensitive = false,
  bool matchWholeWords = false,
  bool constant = false,
  int insertionOrder = 0,
  bool ignoreBudget = false,
  WorldInfoRuntimePolicy? runtimePolicy,
}) {
  return WorldInfoEntry(
    id: uid ?? id,
    worldbookId: 'wb_1',
    keys: keys,
    secondaryKeys: secondaryKeys,
    content: 'content',
    comment: '',
    enabled: true,
    constant: constant,
    selective: selective,
    selectiveLogic: selectiveLogic,
    insertionOrder: insertionOrder,
    caseSensitive: caseSensitive,
    matchWholeWords: matchWholeWords,
    useGroupScoring: false,
    probability: 100,
    useProbability: false,
    position: WorldInfoPosition.before,
    depth: 0,
    group: null,
    groupWeight: 100,
    preventRecursion: false,
    delayUntilRecursion: false,
    scanDepth: 0,
    role: 0,
    sticky: 0,
    cooldown: 0,
    delay: 0,
    characterFilter: const <String, dynamic>{},
    ignoreBudget: ignoreBudget,
    runtimePolicy: runtimePolicy,
  );
}

void main() {
  const matcher = WorldInfoMatcher();

  bool matches(WorldInfoEntry entry, String history) {
    final result = matcher.findMatchingEntries(
      entries: <WorldInfoEntry>[entry],
      context: WorldInfoMatchContext(history: history),
      characterId: 'char_1',
      characterTags: const <String>[],
    );
    return result.isNotEmpty;
  }

  group('selectiveLogic branches', () {
    // Primary key `alpha` is present in every haystack below, so each case
    // isolates how the secondary keys confirm or veto that primary match.
    const secondaries = <String>['beta', 'gamma'];

    test('AND_ANY (0): any secondary match confirms', () {
      final entry = _entry(secondaryKeys: secondaries, selectiveLogic: 0);
      expect(matches(entry, 'alpha beta'), isTrue);
      expect(matches(entry, 'alpha beta gamma'), isTrue);
      expect(matches(entry, 'alpha only'), isFalse);
    });

    test('NOT_ALL (1): vetoed only when every secondary matches', () {
      final entry = _entry(secondaryKeys: secondaries, selectiveLogic: 1);
      expect(matches(entry, 'alpha only'), isTrue);
      expect(matches(entry, 'alpha beta'), isTrue);
      expect(matches(entry, 'alpha beta gamma'), isFalse);
    });

    test('NOT_ANY (2): vetoed as soon as one secondary matches', () {
      final entry = _entry(secondaryKeys: secondaries, selectiveLogic: 2);
      expect(matches(entry, 'alpha only'), isTrue);
      expect(matches(entry, 'alpha beta'), isFalse);
      expect(matches(entry, 'alpha beta gamma'), isFalse);
    });

    test('AND_ALL (3): confirmed only when every secondary matches', () {
      final entry = _entry(secondaryKeys: secondaries, selectiveLogic: 3);
      expect(matches(entry, 'alpha only'), isFalse);
      expect(matches(entry, 'alpha beta'), isFalse);
      expect(matches(entry, 'alpha beta gamma'), isTrue);
    });

    test('default selectiveLogic keeps the previous AND_ANY behavior', () {
      final entry = _entry(secondaryKeys: secondaries);
      expect(entry.selectiveLogic, 0);
      expect(matches(entry, 'alpha beta'), isTrue);
      expect(matches(entry, 'alpha only'), isFalse);
    });

    test('unknown selectiveLogic falls back to AND_ANY', () {
      final entry = _entry(secondaryKeys: secondaries, selectiveLogic: 99);
      expect(matches(entry, 'alpha beta'), isTrue);
      expect(matches(entry, 'alpha only'), isFalse);
    });

    test('secondary keys are ignored when selective is false', () {
      final entry = _entry(
        secondaryKeys: secondaries,
        selective: false,
        selectiveLogic: 3,
      );
      expect(matches(entry, 'alpha only'), isTrue);
    });

    test('empty secondary keys never veto a primary match', () {
      for (final logic in <int>[0, 1, 2, 3]) {
        final entry = _entry(selectiveLogic: logic);
        expect(
          matches(entry, 'alpha only'),
          isTrue,
          reason: 'logic $logic should not veto without secondary keys',
        );
      }
    });
  });

  group('matchWholeWords applies to secondary keys too', () {
    test('substring-only secondary does not match under whole-word mode', () {
      final entry = _entry(
        keys: const <String>['alpha'],
        secondaryKeys: const <String>['beta'],
        selectiveLogic: 0,
        matchWholeWords: true,
      );
      // `betamax` contains `beta` as a substring but not as a whole word.
      expect(matches(entry, 'alpha betamax'), isFalse);
      expect(matches(entry, 'alpha beta'), isTrue);
    });

    test('caseSensitive applies to secondary keys too', () {
      final entry = _entry(
        keys: const <String>['alpha'],
        secondaryKeys: const <String>['Beta'],
        selectiveLogic: 0,
        caseSensitive: true,
      );
      expect(matches(entry, 'alpha beta'), isFalse);
      expect(matches(entry, 'alpha Beta'), isTrue);
    });
  });

  group('primary key matching', () {
    test('a later non-matching key does not erase an earlier match', () {
      // Regression: the loop previously overwrote `keyMatched` each iteration,
      // so a trailing miss could discard a hit found earlier in the list.
      final entry = _entry(
        keys: const <String>['alpha', 'zeta'],
        selective: false,
      );
      expect(matches(entry, 'alpha only'), isTrue);
    });
  });

  group('match metadata', () {
    test('reports the primary key verbatim, not the lower-cased needle', () {
      final entry = _entry(keys: <String>['Alpha']);
      final matches = matcher.findMatchingEntriesWithMetadata(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(history: 'talking about ALPHA'),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(matches, hasLength(1));
      expect(matches.single.matchedKey, 'Alpha');
      expect(
        matches.single.activationReason,
        WorldInfoActivationReason.keyword,
      );
    });

    test('reports the first firing key when several would match', () {
      final entry = _entry(keys: <String>['beta', 'alpha']);
      final matches = matcher.findMatchingEntriesWithMetadata(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(history: 'alpha and beta'),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(matches.single.matchedKey, 'beta');
    });

    test('constant entries report constant with no matched key', () {
      final entry = _entry(keys: const <String>[], constant: true);
      final matches = matcher.findMatchingEntriesWithMetadata(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(history: 'anything'),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(matches, hasLength(1));
      expect(matches.single.matchedKey, isNull);
      expect(
        matches.single.activationReason,
        WorldInfoActivationReason.constant,
      );
    });

    test('entry-only projection matches the metadata pass exactly', () {
      final entries = <WorldInfoEntry>[
        _entry(uid: 'a', keys: <String>['alpha'], insertionOrder: 2),
        _entry(uid: 'b', keys: const <String>[], constant: true),
        _entry(uid: 'c', keys: <String>['zeta'], insertionOrder: -5),
      ];
      const context = WorldInfoMatchContext(history: 'alpha and zeta');
      final projected = matcher.findMatchingEntries(
        entries: entries,
        context: context,
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      final detailed = matcher.findMatchingEntriesWithMetadata(
        entries: entries,
        context: context,
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(
        projected.map((entry) => entry.id).toList(),
        detailed.map((match) => match.entry.id).toList(),
      );
    });
  });

  group('canonical scanSources', () {
    test('history remains matchable when history is the only source', () {
      final entry = _entry(
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions(
          <String, dynamic>{
            'targetingPolicy': <String, dynamic>{
              'scanSources': <String>['history'],
            },
          },
        ),
      );
      expect(matches(entry, 'alpha in history'), isTrue);
    });

    test('sources not selected by policy do not participate', () {
      final entry = _entry(
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions(
          <String, dynamic>{
            'targetingPolicy': <String, dynamic>{
              'scanSources': <String>['history'],
            },
          },
        ),
      );
      final result = matcher.findMatchingEntries(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(
          history: 'nothing here',
          scenario: 'alpha in scenario',
          characterDescription: 'alpha in description',
        ),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(result, isEmpty);
    });

    test('explicit scenario source participates in matching', () {
      final entry = _entry(
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions(
          <String, dynamic>{
            'targetingPolicy': <String, dynamic>{
              'scanSources': <String>['history', 'scenario'],
            },
          },
        ),
      );
      final result = matcher.findMatchingEntries(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(
          history: 'nothing here',
          scenario: 'alpha in scenario',
        ),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(result, hasLength(1));
    });

    test('explicit character_description source participates in matching', () {
      // The codec translates SillyTavern's `matchCharacterDescription` into this
      // canonical source, so an entry that opted in must fire on card text even
      // when the fresh user text says nothing.
      final entry = _entry(
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions(
          <String, dynamic>{
            'targetingPolicy': <String, dynamic>{
              'scanSources': <String>['history', 'character_description'],
            },
          },
        ),
      );
      final result = matcher.findMatchingEntries(
        entries: <WorldInfoEntry>[entry],
        context: const WorldInfoMatchContext(
          history: 'nothing here',
          characterDescription: 'alpha in description',
          scenario: 'alpha in scenario',
        ),
        characterId: 'char_1',
        characterTags: const <String>[],
      );
      expect(result, hasLength(1));
    });
  });

  group('planner budget tier projection', () {
    Character character() => Character(
      id: 'char_1',
      ownerUserId: 'owner',
      name: 'Tester',
      nickname: '',
      description: '',
      personality: '',
      scenario: '',
      firstMessage: '',
      alternateGreetings: const <String>[],
      exampleMessages: '',
      systemPrompt: '',
      postHistoryInstructions: '',
      tags: const <String>[],
      isSystem: false,
      visibilityScope: 'private',
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
    );

    ResolvedExecutionUnit project({String? tier, bool ignoreBudget = false}) {
      final entry = _entry(
        ignoreBudget: ignoreBudget,
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions(
          <String, dynamic>{
            if (tier != null) 'budgetPolicy': <String, dynamic>{'tier': tier},
            if (ignoreBudget) 'ignoreBudget': true,
          },
        ),
      );
      final char = character();
      final plan = const PromptExecutionPlanner().buildDomainPlan(
        DomainPromptPlanningInput(
          character: char,
          worldInfoEntries: <WorldInfoEntry>[entry],
          promptBlocks: const <PromptBlock>[],
          promptContext: const SessionPromptContext(),
        ),
      );
      return <ResolvedExecutionUnit>[
        ...plan.shellSequence,
        ...plan.historySplicePoints.expand((point) => point.units),
        ...plan.outletMap.values.expand((units) => units),
      ].singleWhere(
        (unit) => unit.sourceKind == ExecutionSourceKind.worldInfoEntry,
      );
    }

    test('projects all explicit tiers', () {
      expect(project(tier: 'low').budgetTier, ExecutionBudgetTier.low);
      expect(project(tier: 'normal').budgetTier, ExecutionBudgetTier.normal);
      expect(project(tier: 'high').budgetTier, ExecutionBudgetTier.high);
      expect(
        project(tier: 'mandatory').budgetTier,
        ExecutionBudgetTier.mandatory,
      );
    });

    test('missing and unknown tiers fall back to ignoreBudget', () {
      expect(project().budgetTier, ExecutionBudgetTier.normal);
      expect(project(ignoreBudget: true).budgetTier, ExecutionBudgetTier.high);
      expect(project(tier: 'unknown').budgetTier, ExecutionBudgetTier.normal);
      expect(
        project(tier: 'unknown', ignoreBudget: true).budgetTier,
        ExecutionBudgetTier.high,
      );
    });

    test('explicit low tier coexists independently with ignoreBudget', () {
      final unit = project(tier: 'low', ignoreBudget: true);
      expect(unit.budgetTier, ExecutionBudgetTier.low);
      expect(unit.ignoreBudget, isTrue);
    });
  });
}
