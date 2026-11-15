import 'dart:convert';

import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

void main() {
  const compiler = DomainPromptCompiler();
  const source = PromptSourceSnapshot(
    key: 'book-snapshot',
    locator: 'library:test',
    resourceId: 'book',
    revision: '7',
    contentHash: 'hash',
  );
  ResolvedExecutionUnit unit(
    String id,
    String text, {
    ExecutionSourceKind kind = ExecutionSourceKind.worldInfoEntry,
    bool required = false,
    bool ignoreBudget = false,
    ExecutionBudgetTier tier = ExecutionBudgetTier.normal,
  }) => ResolvedExecutionUnit(
    id: id,
    sourceKind: kind,
    sourceRef: 'book',
    enabled: true,
    contentTemplate: text,
    role: 'system',
    insertionMode: ExecutionInsertionMode.beforeHistory,
    mandatory: required,
    ignoreBudget: ignoreBudget,
    budgetTier: tier,
  );
  PreparedPromptCandidates prepare(
    List<ResolvedExecutionUnit> units, {
    Map<String, dynamic> global = const {},
    Map<String, dynamic> local = const {},
    bool duplicateOutlet = false,
  }) {
    final plan = PromptExecutionPlan(
      shellSequence: duplicateOutlet
          ? [
              for (var i = 0; i < 2; i++)
                ResolvedExecutionUnit(
                  id: 'marker-$i',
                  sourceKind: ExecutionSourceKind.marker,
                  sourceRef: 'marker',
                  enabled: true,
                  contentTemplate: '',
                  role: 'system',
                  markerId: 'outlet',
                  insertionMode: ExecutionInsertionMode.replaceMarker,
                ),
            ]
          : units,
      outletMap: duplicateOutlet ? {'outlet': units} : {},
      historySplicePoints: [],
      disabledUnits: [],
    );
    return compiler.prepareCandidates(
      compilationId: 'operation',
      executionPlan: plan,
      sourceSnapshots: [source],
      inputSnapshot: const PromptInputSnapshot(
        canonicalInputDigest: 'input',
        scanHistoryDigest: 'history',
        variablesDigest: 'variables',
        environmentDigest: 'environment',
      ),
      speakerRef: const PromptSpeakerRef(kind: PromptSpeakerKind.assistant),
      unitSnapshotKeys: {for (final u in units) u.id: source.key},
      transformer: PromptContentTransformer(
        macroService: MacroService(
          const MacroContext(),
          clock: FrozenClock(DateTime.utc(2026)),
          random: SeededRandomSource(3),
        ),
        chatId: 'topic',
        globalVariables: global,
        localOverrides: local,
      ),
      currentInput: '{{incvar::count}}',
      historyTransformDigest: 'regex',
    );
  }

  PromptAdmissionBudget budget(
    PreparedPromptCandidates candidates, {
    int available = 100,
    int emissionCost = 10,
    List<String> nonWorldbook = const [],
  }) => PromptAdmissionBudget(
    candidateDigest: candidates.digest,
    budgetSnapshotDigest: 'budget',
    layoutHistoryDigest: 'layout',
    inputLimit: 1000,
    worldbookAvailableTokens: available,
    emissionCosts: {
      for (final e in candidates.emissions) e.emissionId: emissionCost,
    },
    admittedNonWorldbookUnitIds: nonWorldbook,
    fixedContextCost: 4,
    protectedHistoryCost: 0,
    nonWorldbookPromptCost:
        candidates.emissions
            .where((e) => nonWorldbook.contains(e.unitId))
            .length *
        emissionCost,
  );

  test(
    'scratch macros isolate global/local and never modify frozen inputs',
    () {
      final global = {
        'count': 1,
        'items': ['initial'],
      };
      final local = {'count': 8};
      final candidates = prepare(
        [
          unit(
            'a',
            '{{incvar::count}}/{{getvar::count}}/{{getglobalvar::count}}',
          ),
          unit('b', '{{addglobalvar::items::next}}{{getglobalvar::items}}'),
          unit('c', '{{getvar::items}}'),
          unit('d', '{{setvar::name::Aria}}{{getvar::name}}'),
        ],
        global: global,
        local: local,
      );
      expect(candidates.units[0].expandedText, '9/9/1');
      expect(candidates.units[1].expandedText, '["initial","next"]');
      expect(candidates.units[2].expandedText, '[initial]');
      expect(candidates.units[3].expandedText, 'Aria');
      expect(candidates.transformedInput, '{{incvar::count}}');
      expect(global, {
        'count': 1,
        'items': ['initial'],
      });
      expect(local, {'count': 8});
      expect(
        candidates.trace
            .where((t) => t.reason == 'scratch_variable_operation')
            .length,
        3,
      );
    },
  );

  test('one expansion per unit, multiple occurrences charged separately', () {
    final candidates = prepare(
      [unit('counter', '{{incvar::n}}')],
      global: {'n': 0},
      duplicateOutlet: true,
    );
    expect(candidates.units.single.expandedText, '1');
    expect(candidates.emissions.length, 2);
    final admitted = compiler.admitCandidates(
      candidates,
      budget(candidates, available: 15),
    );
    expect(admitted.selectedUnits, isEmpty);
    expect(admitted.emissions, isEmpty);
    final retained = compiler.admitCandidates(
      candidates,
      budget(candidates, available: 20),
    );
    expect(retained.selectedUnits.single.expandedText, '1');
    expect(retained.emissions.length, 2);
    expect(candidates.units.single.expandedText, '1');
  });

  test('zero-text scratch unit still executes only once', () {
    final candidates = prepare(
      [unit('add', '{{addvar::n::1}}'), unit('read', '{{getvar::n}}')],
      global: {'n': 0},
      duplicateOutlet: true,
    );
    expect(candidates.units.single.expandedText, '1.0');
    expect(candidates.emissions.length, 2);
  });

  test('ignoreBudget costs global capacity but skips book quota', () {
    final candidates = prepare([
      unit('ignore', 'lore', ignoreBudget: true),
      unit('other', 'other'),
    ]);
    final plan = compiler.admitCandidates(
      candidates,
      budget(candidates, available: 15),
      worldbookTokenBudgets: {'book': 0},
    );
    expect(plan.selectedUnits.map((u) => u.unitId), ['ignore']);
    expect(
      () => compiler.admitCandidates(
        candidates,
        budget(candidates, available: 9),
      ),
      throwsA(
        isA<PromptBudgetOverflowException>().having(
          (e) => e.code,
          'code',
          'context_limit',
        ),
      ),
    );
  });

  test('required lore overflow fails instead of becoming optional', () {
    final candidates = prepare([
      unit('required', 'must retain', required: true),
    ]);
    expect(
      () => compiler.admitCandidates(
        candidates,
        budget(candidates, available: 5),
      ),
      throwsA(isA<PromptBudgetOverflowException>()),
    );
  });

  test('expanded cost vector and host selection are required and exact', () {
    final candidates = prepare([
      unit(
        'sys',
        'hello',
        kind: ExecutionSourceKind.promptBlock,
        required: true,
      ),
    ]);
    expect(
      () => compiler.admitCandidates(candidates, budget(candidates)),
      throwsFormatException,
    );
    final plan = compiler.admitCandidates(
      candidates,
      budget(candidates, nonWorldbook: ['sys']),
    );
    expect(plan.selectedUnits.single.unitId, 'sys');
    final raw = budget(candidates, nonWorldbook: ['sys']).toJson();
    raw['emission_costs'] = <String, int>{};
    expect(() => PromptAdmissionBudget.fromJson(raw), throwsFormatException);
  });

  test(
    'strict candidate and plan roundtrip rejects tampering and authority fields',
    () {
      final candidates = prepare([unit('lore', '中文 😀')]);
      expect(
        PreparedPromptCandidates.fromJson(
          jsonDecode(jsonEncode(candidates.toJson())),
        ).digest,
        candidates.digest,
      );
      final plan = compiler.admitCandidates(candidates, budget(candidates));
      expect(CompiledPromptPlan.fromJson(plan.toJson()).digest, plan.digest);
      for (final change in <void Function(Map<String, dynamic>)>[
        (json) => json['tools'] = ['secret'],
        (json) => json['schema_digest'] = 'wrong',
        (json) => (json['units'] as List).first['role'] = 'developer',
        (json) => (json['units'] as List).first['retention'] = 'host_policy',
        (json) => (json['emissions'] as List).first['depth'] = -1,
        (json) => (json['emissions'] as List).first['unit_id'] = 'absent',
        (json) => (json['units'] as List).add((json['units'] as List).first),
        (json) => (json['source_snapshots'] as List).first['resource_id'] =
            'different',
      ]) {
        final raw =
            jsonDecode(jsonEncode(candidates.toJson())) as Map<String, dynamic>;
        change(raw);
        expect(
          () => PreparedPromptCandidates.fromJson(raw),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'generic planning has no artificial character and keeps authored profile text',
    () {
      final plan = const PromptExecutionPlanner().buildDomainPlan(
        DomainPromptPlanningInput(
          promptBlocks: const [
            PromptBlock(
              id: 'description',
              kind: 'core:characterDescription',
              name: 'description',
            ),
            PromptBlock(
              id: 'custom',
              kind: 'app:instructions',
              name: 'profile',
              content: 'Answer concisely',
            ),
          ],
        ),
      );
      expect(
        plan.shellSequence
            .where((u) => u.contentTemplate.isNotEmpty)
            .map((u) => u.id),
        ['custom'],
      );
      expect(
        plan.shellSequence.any(
          (u) => u.sourceKind == ExecutionSourceKind.characterCore,
        ),
        isFalse,
      );
    },
  );

  test('canonical digest is stable across object order and UTF-8', () {
    expect(
      promptDigest({
        'b': ['中文', 1],
        'a': true,
      }),
      promptDigest({
        'a': true,
        'b': ['中文', 1],
      }),
    );
    expect(canonicalPromptJson({'z': 1, 'a': '中文'}), '{"a":"中文","z":1}');
    expect(canonicalPromptJson({'number': 2.5}), '{"number":2.5}');
    expect(() => promptDigest(double.nan), throwsFormatException);
    expect(promptDigest('hello'), 'dcdd4ba1ec7623eb');
  });
}
