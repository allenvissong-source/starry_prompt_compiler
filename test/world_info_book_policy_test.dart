import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

Worldbook book(
  String id, {
  int scanDepth = 1,
  bool recursiveScanning = true,
  int maxRecursionDepth = 3,
  bool allowEntryCascade = true,
}) => Worldbook(
  id: id,
  ownerUserId: 'owner',
  name: id,
  description: '',
  scanDepth: scanDepth,
  tokenBudget: null,
  recursiveScanning: recursiveScanning,
  maxRecursionDepth: maxRecursionDepth,
  allowEntryCascade: allowEntryCascade,
  tags: const [],
  creatorNotes: '',
  extensions: const {},
  isSystem: false,
  visibilityScope: 'private',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

WorldInfoEntry entry(
  String id, {
  String worldbookId = 'book',
  String key = 'alpha',
  String content = 'beta',
  int? scanDepth,
  List<String> scanSources = const [],
  bool preventRecursion = false,
  bool excludeRecursion = false,
  bool delayUntilRecursion = false,
}) => WorldInfoEntry(
  id: id,
  worldbookId: worldbookId,
  keys: [key],
  secondaryKeys: const [],
  content: content,
  comment: '',
  enabled: true,
  constant: false,
  selective: false,
  insertionOrder: 0,
  caseSensitive: false,
  matchWholeWords: false,
  useGroupScoring: false,
  probability: 100,
  useProbability: false,
  position: WorldInfoPosition.before,
  depth: 0,
  group: null,
  groupWeight: 100,
  preventRecursion: preventRecursion,
  excludeRecursion: excludeRecursion,
  delayUntilRecursion: delayUntilRecursion,
  scanDepth: scanDepth,
  role: 0,
  sticky: 0,
  cooldown: 0,
  delay: 0,
  characterFilter: const {},
  scanSources: scanSources,
);

Set<String> match(
  List<WorldInfoEntry> entries, {
  WorldInfoMatchContext context = const WorldInfoMatchContext(
    historyMessages: ['alpha'],
  ),
  Map<String, Worldbook>? worldbooks,
}) => const WorldInfoMatcher()
    .findMatchingEntriesWithMetadata(
      context: context,
      entries: entries,
      characterId: 'character',
      characterTags: const [],
      worldbooks: worldbooks ?? {'book': book('book')},
    )
    .map((match) => match.entry.id)
    .toSet();

ResolvedExecutionUnit unit(
  String id,
  String bookId, {
  int order = 0,
  bool ignoreBudget = false,
  ExecutionInsertionMode mode = ExecutionInsertionMode.relativeBefore,
}) => ResolvedExecutionUnit(
  id: id,
  sourceKind: ExecutionSourceKind.worldInfoEntry,
  sourceRef: bookId,
  enabled: true,
  contentTemplate: 'x',
  role: 'system',
  insertionMode: mode,
  sourceOrder: order,
  injectionOrder: order,
  ignoreBudget: ignoreBudget,
);

Set<String> retained(PromptExecutionPlan plan) => {
  ...plan.shellSequence.map((unit) => unit.id),
  ...plan.outletMap.values.expand((units) => units.map((unit) => unit.id)),
  ...plan.historySplicePoints.expand(
    (point) => point.units.map((unit) => unit.id),
  ),
};

void main() {
  test('book depth and entry overrides limit both keywords and recall', () {
    final found = match(
      [
        entry('inherit'),
        entry('override', scanDepth: 2),
        entry('zero', scanDepth: 0),
        entry('recent', key: 'gamma'),
      ],
      context: const WorldInfoMatchContext(historyMessages: ['alpha', 'gamma']),
    );
    expect(found, {'override', 'recent'});
  });

  test('book zero depth leaves opted-in persona scanning available', () {
    expect(
      match(
        [
          entry('history'),
          entry('persona', scanSources: ['persona_description']),
        ],
        context: const WorldInfoMatchContext(
          historyMessages: ['alpha'],
          personaDescription: 'alpha',
        ),
        worldbooks: {'book': book('book', scanDepth: 0)},
      ),
      {'history', 'persona'},
    );
    expect(
      match(
        [entry('history')],
        worldbooks: {'book': book('book', scanDepth: 0)},
      ),
      isEmpty,
    );
  });

  test('recall cannot escape entry source or depth restrictions', () {
    final found = const WorldInfoMatcher().findMatchingEntriesWithMetadata(
      context: const WorldInfoMatchContext(
        historyMessages: ['你父亲怎么了', '你好'],
        personaDescription: '与此无关',
      ),
      entries: [
        entry('old', key: '米雪儿的父亲', content: '米雪儿的父亲失踪了'),
        entry(
          'persona',
          key: '米雪儿的父亲',
          content: '米雪儿的父亲失踪了',
          scanSources: ['persona_description'],
        ),
        entry('wide', key: '米雪儿的父亲', content: '米雪儿的父亲失踪了', scanDepth: 2),
      ],
      characterId: 'character',
      characterTags: const [],
      worldbooks: {'book': book('book')},
      // Duplicate synthetic documents lower IDF. This checks scope isolation,
      // independently of the calibrated production score threshold.
      recall: const WorldInfoRecallOptions(minScore: 0.01),
    );
    expect(found.map((match) => match.entry.id), ['wide']);
    expect(found.single.activationReason, WorldInfoActivationReason.semantic);
  });

  test('each book controls entry into a cross-book cascade', () {
    final entries = [
      entry('seed'),
      entry('open', worldbookId: 'open', key: 'beta'),
      entry('closed', worldbookId: 'closed', key: 'beta'),
      entry('zero', worldbookId: 'zero', key: 'beta'),
    ];
    expect(
      match(
        entries,
        worldbooks: {
          'book': book('book'),
          'open': book('open'),
          'closed': book('closed', recursiveScanning: false),
          'zero': book('zero', maxRecursionDepth: 0),
        },
      ),
      {'seed', 'open'},
    );
  });

  test('book cascade flag blocks emitted text but keeps its own match', () {
    expect(
      match(
        [entry('seed'), entry('next', worldbookId: 'next', key: 'beta')],
        worldbooks: {
          'book': book('book', allowEntryCascade: false),
          'next': book('next'),
        },
      ),
      {'seed'},
    );
  });

  test('book recursion depth does not inherit a minimum of three', () {
    final entries = [
      entry('first'),
      entry('second', key: 'beta', content: 'gamma'),
      entry('third', key: 'gamma'),
    ];
    expect(
      match(entries, worldbooks: {'book': book('book', maxRecursionDepth: 1)}),
      {'first', 'second'},
    );
  });

  test('entry recursion gates survive book policy matching', () {
    expect(
      match([
        entry('seed', preventRecursion: true),
        entry('delayed', key: 'beta', delayUntilRecursion: true),
        entry('direct', key: 'alpha', excludeRecursion: true),
      ]),
      {'seed', 'direct', 'delayed'},
    );
    expect(
      match([
        entry('seed', preventRecursion: true),
        entry('delayed', key: 'beta', delayUntilRecursion: true),
      ]),
      {'seed'},
    );
  });

  test('book budgets apply across shell, outlets and history splice', () {
    final plan = PromptExecutionPlan(
      shellSequence: [unit('first', 'a'), unit('other', 'b')],
      outletMap: {
        'memory': [
          unit('outlet', 'a', order: 1, mode: ExecutionInsertionMode.outlet),
        ],
      },
      historySplicePoints: [
        HistorySplicePoint(
          offsetFromEnd: 0,
          units: [
            unit('splice', 'a', order: 2),
            unit('ignored', 'a', order: 3, ignoreBudget: true),
          ],
        ),
      ],
      disabledUnits: const [],
    );
    final result = const WorldInfoBudgetAdmissionService().admitWorldInfoUnits(
      plan,
      worldbookTokenBudgets: {'a': 5},
    );
    expect(retained(result.plan), {'first', 'other', 'ignored'});
    expect(result.plan.outletMap, isEmpty);
    expect(
      result.trace
          .where((trace) => trace.decision == RetainDecision.dropOverSubBudget)
          .map((trace) => trace.unitId),
      ['outlet', 'splice'],
    );
  });

  test('global and book budgets are both enforced with existing priority', () {
    final result = const WorldInfoBudgetAdmissionService().admitWorldInfoUnits(
      PromptExecutionPlan(
        shellSequence: [
          unit('a', 'a'),
          unit('b', 'b', order: 1),
          unit('c', 'c', order: 2),
        ],
        outletMap: const {},
        historySplicePoints: const [],
        disabledUnits: const [],
        budgetPlan: const MessageBudgetPlan(availableInputTokens: 40),
        worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
      ),
      worldbookTokenBudgets: {'a': 0, 'b': 5},
    );
    expect(retained(result.plan), {'b', 'c'});
  });
}
