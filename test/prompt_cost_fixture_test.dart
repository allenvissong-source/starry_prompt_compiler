import 'dart:convert';
import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';
import 'package:test/test.dart';

void main() {
  test('shared Rust/Dart cost, output reserve and digest fixtures', () {
    final fixture =
        jsonDecode(File('test/fixtures/prompt_cost_v1.json').readAsStringSync())
            as Map<String, dynamic>;
    const estimator = HeuristicPromptCostEstimator();
    expect(estimator.id, fixture['estimator_id']);
    for (final row in fixture['cases'] as List) {
      expect(estimator.text(row['text'] as String), row['text_tokens']);
      expect(estimator.message(row['text'] as String), row['message_tokens']);
    }
    for (final row in fixture['budget_cases'] as List) {
      final policy = StandalonePromptBudgetPolicy(
        contextTokens: row['context_tokens'] as int,
        outputReserveTokens: row['output_reserve_tokens'] as int,
      );
      expect(policy.protocolReserveTokens, row['protocol_reserve_tokens']);
      expect(policy.inputLimit, row['input_limit']);
      expect(policy.autoTrigger, row['auto_trigger']);
      expect(policy.softTarget, row['soft_target']);
    }
    for (final row in fixture['digest_cases'] as List) {
      expect(promptDigest(row['value']), row['digest']);
    }
  });
}
