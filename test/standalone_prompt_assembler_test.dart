import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';
import 'package:test/test.dart';

void main() {
  const assembler = StandalonePromptAssembler();
  const compiler = DomainPromptCompiler();
  final policy = StandalonePromptBudgetPolicy(
    contextTokens: 1000,
    outputReserveTokens: 100,
  );
  PreparedPromptCandidates candidates({
    int depth = 1,
    String identity = 'identity',
  }) {
    const source = PromptSourceSnapshot(
      key: 'source',
      locator: 'library:test',
      resourceId: 'profile',
      revision: '1',
      contentHash: 'hash',
    );
    ResolvedExecutionUnit unit(String id, String text, String role) =>
        ResolvedExecutionUnit(
          id: id,
          sourceKind: ExecutionSourceKind.promptBlock,
          sourceRef: 'profile',
          contentTemplate: text,
          role: role,
          enabled: true,
          insertionMode: ExecutionInsertionMode.beforeHistory,
          mandatory: true,
        );
    return compiler.prepareCandidates(
      compilationId: 'operation',
      executionPlan: PromptExecutionPlan(
        shellSequence: [
          unit('pre', identity, 'system'),
          const ResolvedExecutionUnit(
            id: 'history',
            sourceKind: ExecutionSourceKind.marker,
            sourceRef: 'marker',
            enabled: true,
            contentTemplate: '',
            role: 'system',
            insertionMode: ExecutionInsertionMode.replaceMarker,
            markerId: 'history',
          ),
          unit('post', 'after', 'assistant'),
        ],
        historySplicePoints: [
          HistorySplicePoint(
            offsetFromEnd: depth,
            units: [unit('depth', 'at-depth', 'user')],
          ),
        ],
        disabledUnits: [],
      ),
      sourceSnapshots: [source],
      inputSnapshot: const PromptInputSnapshot(
        canonicalInputDigest: 'input',
        scanHistoryDigest: 'scan',
        variablesDigest: 'variables',
        environmentDigest: 'environment',
      ),
      speakerRef: const PromptSpeakerRef(kind: PromptSpeakerKind.assistant),
      unitSnapshotKeys: {
        'pre': source.key,
        'post': source.key,
        'depth': source.key,
      },
      transformer: PromptContentTransformer(
        macroService: MacroService(
          const MacroContext(),
          clock: FrozenClock(DateTime.utc(2026)),
        ),
        chatId: 'topic',
      ),
      currentInput: 'current',
      historyTransformDigest: 'regex',
    );
  }

  StandaloneHistoryGroup group(String id, String user, String assistant) =>
      StandaloneHistoryGroup(
        id: id,
        messages: [
          StandalonePromptMessage(
            role: StandaloneMessageRole.user,
            content: user,
            slotId: '$id-user',
          ),
          StandalonePromptMessage(
            role: StandaloneMessageRole.assistant,
            content: assistant,
            slotId: '$id-assistant',
          ),
        ],
      );
  StandalonePromptAssembly assemble(
    PreparedPromptCandidates c,
    List<StandaloneHistoryGroup> history, {
    StandalonePromptBudgetPolicy? override,
  }) {
    final p = override ?? policy;
    final budget = assembler.prepareAdmission(
      candidates: c,
      policy: p,
      history: history,
    );
    final plan = compiler.admitCandidates(c, budget);
    return assembler.assemble(
      candidates: c,
      plan: plan,
      policy: p,
      history: history,
    );
  }

  test(
    'keeps roles and original history, depth 1 precedes last dialogue slot',
    () {
      final result = assemble(candidates(), [
        group('h', 'old user', 'old assistant'),
      ]);
      expect(result.messages.map((m) => m.content), [
        'identity',
        'old user',
        'at-depth',
        'old assistant',
        'after',
        'current',
      ]);
      expect(result.messages.map((m) => m.role), [
        StandaloneMessageRole.system,
        StandaloneMessageRole.user,
        StandaloneMessageRole.user,
        StandaloneMessageRole.assistant,
        StandaloneMessageRole.assistant,
        StandaloneMessageRole.user,
      ]);
      expect(result.messages.where((m) => m.content == 'current').length, 1);
      expect(
        result.messages
            .map((m) => m.toModelJson())
            .any((j) => j.containsKey('source_id')),
        isFalse,
      );
    },
  );

  test('depth 0 and overflow use current/earliest retained slots', () {
    final history = [group('h', 'old user', 'old assistant')];
    expect(
      assemble(candidates(depth: 0), history).messages.map((m) => m.content),
      ['identity', 'old user', 'old assistant', 'at-depth', 'after', 'current'],
    );
    expect(
      assemble(candidates(depth: 99), history).messages.map((m) => m.content),
      ['identity', 'at-depth', 'old user', 'old assistant', 'after', 'current'],
    );
    expect(assemble(candidates(depth: 99), []).messages.map((m) => m.content), [
      'identity',
      'at-depth',
      'after',
      'current',
    ]);
  });

  test('tool results do not advance depth and remain paired', () {
    final history = [
      StandaloneHistoryGroup(
        id: 'tool-group',
        messages: [
          StandalonePromptMessage(
            role: StandaloneMessageRole.user,
            content: 'old user',
            slotId: 'u',
          ),
          StandalonePromptMessage(
            role: StandaloneMessageRole.assistant,
            content: '',
            slotId: 'a',
            toolCalls: const [
              StandaloneToolCall(id: 'call', name: 'read', arguments: '{}'),
            ],
          ),
          StandalonePromptMessage(
            role: StandaloneMessageRole.tool,
            content: '{"answer":1}',
            slotId: 'a',
            toolCallId: 'call',
          ),
          StandalonePromptMessage(
            role: StandaloneMessageRole.assistant,
            content: 'old assistant',
            slotId: 'a',
          ),
        ],
      ),
    ];
    final result = assemble(candidates(), history);
    expect(result.messages.map((m) => m.content), [
      'identity',
      'old user',
      'at-depth',
      '',
      '{"answer":1}',
      'old assistant',
      'after',
      'current',
    ]);
    final call = result.messages.indexWhere((m) => m.toolCalls.isNotEmpty);
    expect(result.messages[call + 1].toolCallId, 'call');
    expect(result.messages[call + 1].toModelJson()['role'], 'tool');
    expect(
      () => StandaloneHistoryGroup(
        id: 'broken',
        messages: [history.single.messages[2]],
      ),
      throwsArgumentError,
    );
  });

  test(
    'whole old group is evicted and depth anchor relocates after compaction',
    () {
      final p = StandalonePromptBudgetPolicy(
        contextTokens: 150,
        outputReserveTokens: 30,
      );
      final result = assemble(candidates(depth: 4), [
        group('old', 'x' * 400, 'y' * 400),
        group('recent', 'recent user', 'recent assistant'),
      ], override: p);
      expect(result.retainedHistoryGroupIds, ['recent']);
      expect(result.messages.map((m) => m.content), [
        'identity',
        'at-depth',
        'recent user',
        'recent assistant',
        'after',
        'current',
      ]);
      expect(
        result.trace.any(
          (t) => t.reason == 'anchor_relocated_after_compaction',
        ),
        isTrue,
      );
      expect(result.estimatedTokens, lessThanOrEqualTo(p.inputLimit));
    },
  );

  test(
    'protected prompt overflow refuses assembly instead of trimming identity',
    () {
      expect(
        () => assemble(
          candidates(identity: '身' * 300),
          [],
          override: StandalonePromptBudgetPolicy(
            contextTokens: 150,
            outputReserveTokens: 30,
          ),
        ),
        throwsA(isA<PromptBudgetOverflowException>()),
      );
    },
  );

  test(
    'output reserve and Unicode heuristic have explicit deterministic costs',
    () {
      final p = StandalonePromptBudgetPolicy(
        contextTokens: 101,
        outputReserveTokens: 11,
      );
      expect(p.protocolReserveTokens, 6);
      expect(p.inputLimit, 84);
      expect(p.autoTrigger, 75);
      expect(p.softTarget, 60);
      const estimator = HeuristicPromptCostEstimator();
      expect(estimator.text('abcde'), 2);
      expect(estimator.text('你好😀'), 3);
      expect(estimator.message('ab中😀'), 7);
      expect(
        () => StandalonePromptBudgetPolicy(
          contextTokens: 100,
          outputReserveTokens: 96,
        ),
        throwsArgumentError,
      );
    },
  );
}
