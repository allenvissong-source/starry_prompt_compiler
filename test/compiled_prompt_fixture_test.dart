import 'dart:convert';
import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/compiled_prompt_v1.json').readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('Rust admission has the same schema, candidates and costs as Dart', () {
    final candidates = PreparedPromptCandidates.fromJson(fixture['candidates']);
    expect(candidates.digest, fixture['candidate_digest']);
    expect(candidates.toJson(), fixture['candidates']);
    final admission = PromptAdmissionBudget.fromJson(fixture['admission']);
    admission.validateFor(candidates);
    expect(admission.toJson(), fixture['admission']);
    expect(
      promptDigest(fixture['budget_snapshot']),
      admission.budgetSnapshotDigest,
    );
    final plan = const DomainPromptCompiler().admitCandidates(
      candidates,
      admission,
    );
    expect(plan.selectedUnits.length, 3);
    expect(plan.emissions.length, 4);
    expect(plan.selectedUnits.map((u) => u.role.wireValue), [
      'system',
      'user',
      'assistant',
    ]);
    expect(CompiledPromptPlan.fromJson(plan.toJson()).digest, plan.digest);
  });
}
