import 'dart:convert';
import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';
import 'package:test/test.dart';

void main() {
  final promptText = File(
    'test/fixtures/compiled_prompt_v1.json',
  ).readAsStringSync();
  final layout =
      jsonDecode(File('test/fixtures/prompt_layout_v1.json').readAsStringSync())
          as Map<String, dynamic>;
  const assembler = StandalonePromptAssembler();
  const compiler = DomainPromptCompiler();
  for (final value in layout['cases'] as List<dynamic>) {
    final scenario = value as Map<String, dynamic>;
    test('shared Rust/Dart layout: ${scenario['name']}', () {
      final prompt = jsonDecode(promptText) as Map<String, dynamic>;
      final candidateJson = prompt['candidates'] as Map<String, dynamic>;
      (candidateJson['emissions'] as List<dynamic>)[1]['depth'] =
          scenario['depth'];
      candidateJson['transformed_input'] = 'current';
      final candidates = PreparedPromptCandidates.fromJson(candidateJson);
      final messages = (layout['history'] as List<dynamic>).map((value) {
        final turn = value as Map<String, dynamic>;
        return StandalonePromptMessage(
          role: StandaloneMessageRole.values.byName(turn['role'] as String),
          content: turn['content'] as String? ?? jsonEncode(turn['output']),
          slotId: turn['slot_id'] as String,
          toolCallId: turn['call_id'] as String?,
          toolCalls: [
            for (final call in turn['calls'] as List<dynamic>? ?? [])
              StandaloneToolCall(
                id: call['call_id'] as String,
                name: call['name'] as String,
                arguments: jsonEncode(call['arguments']),
              ),
          ],
        );
      }).toList();
      final history = [
        StandaloneHistoryGroup(id: 'old', messages: messages.sublist(0, 4)),
        StandaloneHistoryGroup(id: 'recent', messages: messages.sublist(4)),
      ];
      final compact = scenario['retained_start'] != 0;
      final policy = StandalonePromptBudgetPolicy(
        contextTokens: compact ? 60 : 1000,
        outputReserveTokens: compact ? 1 : 100,
      );
      final admission = assembler.prepareAdmission(
        candidates: candidates,
        policy: policy,
        history: history,
      );
      final plan = compiler.admitCandidates(candidates, admission);
      final result = assembler.assemble(
        candidates: candidates,
        plan: plan,
        policy: policy,
        history: history,
      );
      expect(
        result.messages.map(
          (message) =>
              message.sourceId ?? message.toolCallId ?? message.content,
        ),
        (scenario['order'] as List<dynamic>).where((id) => id != 'checkpoint'),
      );
      expect(
        result.trace
            .where((entry) => entry.stage == 'layout')
            .map((entry) => entry.reason),
        scenario['trace'],
      );
      expect(
        result.retainedHistoryGroupIds,
        compact ? ['recent'] : ['old', 'recent'],
      );
    });
  }
}
