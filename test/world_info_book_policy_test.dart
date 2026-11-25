import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

void _testStoredOutlets() {
  test(
    'saved editor outlet reaches runtime and respects explicit output policy',
    () {
      final stored = <String, dynamic>{
        'st_extra': {'outlet_name': 'scene'},
      };
      expect(
        WorldInfoRuntimePolicy.fromEntryExtensions(stored).output.outlet,
        'scene',
      );
      expect(
        WorldInfoRuntimePolicy.fromEntryExtensions({
          ...stored,
          'outputPolicy': {'outlet': 'explicit'},
        }).output.outlet,
        'explicit',
      );
    },
  );
}

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
  WorldInfoRuntimePolicy? runtimePolicy,
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
  runtimePolicy: runtimePolicy,
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

CompiledPromptPlan admit(
  PromptExecutionPlan plan, {
  Map<String, int> bookBudgets = const {},
  int available = 100,
}) {
  final units = [
    ...plan.shellSequence,
    ...plan.outletMap.values.expand((u) => u),
    ...plan.historySplicePoints.expand((p) => p.units),
  ].where((u) => u.sourceKind != ExecutionSourceKind.marker).toList();
  final candidates = const DomainPromptCompiler().prepareCandidates(
    compilationId: 'book-policy',
    executionPlan: plan,
    sourceSnapshots: [
      for (final id in units.map((u) => u.sourceRef).toSet())
        PromptSourceSnapshot(
          key: id,
          locator: 'fixture:$id',
          resourceId: id,
          revision: '1',
          contentHash: promptDigest(id),
        ),
    ],
    inputSnapshot: const PromptInputSnapshot(
      canonicalInputDigest: 'input',
      scanHistoryDigest: 'history',
      variablesDigest: 'variables',
      environmentDigest: 'environment',
    ),
    speakerRef: const PromptSpeakerRef(kind: PromptSpeakerKind.assistant),
    unitSnapshotKeys: {for (final u in units) u.id: u.sourceRef},
    transformer: PromptContentTransformer(
      macroService: MacroService(
        const MacroContext(),
        clock: FrozenClock(DateTime.utc(2026)),
        random: SeededRandomSource(0),
      ),
      chatId: 'topic',
    ),
    currentInput: '',
    historyTransformDigest: 'transform',
  );
  return const DomainPromptCompiler().admitCandidates(
    candidates,
    PromptAdmissionBudget(
      candidateDigest: candidates.digest,
      budgetSnapshotDigest: 'budget',
      layoutHistoryDigest: 'layout',
      inputLimit: 1000,
      worldbookAvailableTokens: available,
      emissionCosts: {for (final e in candidates.emissions) e.emissionId: 5},
      admittedNonWorldbookUnitIds: const [],
      fixedContextCost: 0,
      protectedHistoryCost: 0,
      nonWorldbookPromptCost: 0,
    ),
    worldInfoPolicy: plan.worldInfoBudgetPlan,
    worldbookTokenBudgets: bookBudgets,
  );
}

void main() {
  _testStoredOutlets();
  test(
    'required terms scope literal and ranked matches to the same sentence',
    () {
      final guarded = entry(
        'engineering',
        key: '千年的工程部',
        content: '千年工程部门承担机械维修。',
        runtimePolicy: WorldInfoRuntimePolicy.fromEntryExtensions({
          'targetingPolicy': {
            'scanSources': ['history'],
            'requiredTermGroups': [
              [' 千年 ', 'Millennium'],
              ['工程部', '机械维修'],
            ],
          },
        }),
      );
      List<WorldInfoActivationReason> reasons(List<String> messages) =>
          const WorldInfoMatcher()
              .findMatchingEntriesWithMetadata(
                context: WorldInfoMatchContext(historyMessages: messages),
                entries: [guarded],
                characterId: 'character',
                characterTags: const [],
              )
              .map((match) => match.activationReason)
              .toList();

      expect(reasons(['千年的工程部负责什么？']), [WorldInfoActivationReason.keyword]);
      expect(reasons(['MILLENNIUM 的学校有工程部吗？']), [
        WorldInfoActivationReason.semantic,
      ]);
      expect(reasons(['圣三一的工程部负责什么？阿拜多斯的科研设施呢？']), isEmpty);
      expect(reasons(['千年。圣三一的工程部负责什么？']), isEmpty);
      expect(reasons(['千年；工程部负责什么？']), isEmpty);
      expect(reasons(['千年学校', '工程部负责什么？']), isEmpty);
      expect(reasons(['千年']), isEmpty);
      expect(reasons(['千年的。工程部']), isEmpty);
      expect(reasons(['千年 問工程部；阿拜多斯的设施呢？']), [
        WorldInfoActivationReason.semantic,
      ]);
    },
  );

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
      shellSequence: [
        unit('first', 'a'),
        unit('other', 'b'),
        const ResolvedExecutionUnit(
          id: 'memory-marker',
          sourceKind: ExecutionSourceKind.marker,
          sourceRef: 'memory',
          enabled: true,
          contentTemplate: '',
          role: 'system',
          markerId: 'memory',
          insertionMode: ExecutionInsertionMode.replaceMarker,
        ),
      ],
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
    final result = admit(plan, bookBudgets: {'a': 5});
    expect(result.selectedUnits.map((u) => u.unitId).toSet(), {
      'first',
      'other',
      'ignored',
    });
    expect(result.emissions.any((e) => e.unitId == 'outlet'), isFalse);
    expect(
      result.admissionTrace
          .where((trace) => trace.reason == 'world_info_budget_exceeded')
          .map((trace) => trace.unitId),
      ['outlet', 'splice'],
    );
  });

  test('global and book budgets are both enforced with existing priority', () {
    final result = admit(
      PromptExecutionPlan(
        shellSequence: [
          unit('a', 'a'),
          unit('b', 'b', order: 1),
          unit('c', 'c', order: 2),
        ],
        outletMap: const {},
        historySplicePoints: const [],
        disabledUnits: const [],
        worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
      ),
      bookBudgets: {'a': 0, 'b': 5},
      available: 40,
    );
    expect(result.selectedUnits.map((u) => u.unitId).toSet(), {'b', 'c'});
  });
}
