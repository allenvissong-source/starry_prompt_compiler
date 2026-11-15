import 'dart:convert';
import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';
import 'package:test/test.dart';

import 'characterization/prompt_scenario.dart';

void main() {
  final now = DateTime.utc(2025, 1, 1, 12);
  final character = Character(
    id: 'char-1',
    ownerUserId: 'owner-1',
    name: 'Aria',
    nickname: 'A',
    description: 'a friendly guide',
    personality: 'warm',
    scenario: 'in a library',
    firstMessage: 'Hello!',
    alternateGreetings: const [],
    exampleMessages: '',
    systemPrompt: '',
    postHistoryInstructions: '',
    tags: const [],
    isSystem: false,
    visibilityScope: 'private',
    createdAt: now,
    updatedAt: now,
  );
  final context = ResolvedPromptContext(
    character: character,
    worldInfoEntries: const [],
    groupedWorldInfoEntries: const {},
    resolvedPromptBlocks: const [],
    promptContext: const SessionPromptContext(),
    resolvedVariables: const {'user_name': 'Traveler'},
  );
  ResolvedExecutionUnit unit(String id, String text) => ResolvedExecutionUnit(
    id: id,
    sourceKind: ExecutionSourceKind.promptBlock,
    sourceRef: id,
    enabled: true,
    contentTemplate: text,
    role: 'system',
    insertionMode: ExecutionInsertionMode.beforeHistory,
  );
  final plan = PromptExecutionPlan(
    shellSequence: [
      unit('sys', 'You are {{char}} talking to {{user}}.'),
      const ResolvedExecutionUnit(
        id: 'history',
        sourceKind: ExecutionSourceKind.marker,
        sourceRef: 'history',
        enabled: true,
        contentTemplate: '',
        role: 'system',
        markerId: 'history',
        insertionMode: ExecutionInsertionMode.replaceMarker,
      ),
      unit('instruction', 'Stay in character.'),
    ],
    historySplicePoints: [],
    disabledUnits: [],
  );
  CharacterHistoryMessage row(
    String text,
    TurnMessageRole role, [
    String? id,
  ]) => CharacterHistoryMessage(
    role: role,
    content: text,
    timestamp: now,
    messageId: id,
  );
  ScenarioAssembly run(
    List<CharacterHistoryMessage> history, {
    bool splice = false,
  }) => assembleScenario(
    request: PromptScenarioInput(
      sessionId: 'session',
      topicId: 'topic',
      characterId: character.id,
      history: history,
      pendingUserInput: const PromptScenarioUserInput(text: 'What is here?'),
    ),
    character: character,
    resolvedContext: context,
    executionPlan: splice
        ? plan.copyWith(
            historySplicePoints: [
              HistorySplicePoint(
                offsetFromEnd: 1,
                units: [unit('note', 'INJECTED_AT_DEPTH_1')],
              ),
            ],
          )
        : plan,
  );
  final history = [
    row('Hi Aria!', TurnMessageRole.user, 'm1'),
    row('Hello, Traveler.', TurnMessageRole.assistant, 'm2'),
  ];

  test('domain candidates assemble shell, history and input exactly once', () {
    final result = run(history);
    expect(result.submittedMessage.content, 'What is here?');
    expect(result.contextMessages.map((m) => m.content), [
      'You are Aria talking to User.',
      'Hi Aria!',
      'Hello, Traveler.',
      'Stay in character.',
    ]);
  });

  test('independent frozen runs produce identical output and diagnostics', () {
    Map<String, Object?> serialize(ScenarioAssembly result) => {
      'messages': result.assembly.messages
          .map((m) => m.toSnapshotJson())
          .toList(),
      'trace': result.trace.map((t) => t.toJson()).toList(),
    };
    expect(serialize(run(history)), serialize(run(history)));
  });

  test('host ledger identities survive interleaved domain emissions', () {
    final result = run([
      row('first', TurnMessageRole.user, 'h1'),
      row('second', TurnMessageRole.assistant),
      row('third', TurnMessageRole.user, 'h3'),
    ], splice: true);
    expect(
      result.contextMessages
          .where((m) => m.slotId != null)
          .map((m) => '${m.sourceId}=${m.content}'),
      ['h1=first', 'null=second', 'h3=third'],
    );
    final injection = result.contextMessages.singleWhere(
      (m) => m.content == 'INJECTED_AT_DEPTH_1',
    );
    expect(injection.slotId, isNull);
    expect(injection.sourceId, isNotNull);
    expect(injection.sourceId, isNot(anyOf('h1', 'h3')));
  });

  test('absent host message identity remains null', () {
    final result = run([
      row('first', TurnMessageRole.user),
      row('second', TurnMessageRole.assistant),
    ]);
    expect(
      result.contextMessages
          .where((m) => m.slotId != null)
          .every((m) => m.sourceId == null),
      isTrue,
    );
    expect(result.submittedMessage.sourceId, isNull);
  });

  test('model JSON excludes host and domain provenance identifiers', () {
    final result = run(history, splice: true);
    expect(result.contextMessages.any((m) => m.sourceId != null), isTrue);
    for (final message in result.assembly.messages) {
      expect(message.toModelJson().keys, unorderedEquals(['role', 'content']));
      expect(message.toSnapshotJson()['source_id'], message.sourceId);
    }
  });

  test('domain schema refuses host attachments and local file paths', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/compiled_prompt_v1.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final candidates = PreparedPromptCandidates.fromJson(fixture['candidates']);
    final raw = candidates.toJson();
    raw['attachments'] = [
      {'path': '/tmp/image.png', 'mime_type': 'image/png'},
    ];
    expect(() => PreparedPromptCandidates.fromJson(raw), throwsFormatException);
  });
}
