import '../codec/prompt_plan_wire.dart';
import 'heuristic_cost_estimator.dart';

/// Explicit budget configuration for a host that chooses Dart assembly.
/// Starry production resolves these values exclusively in its Rust host.
class StandalonePromptBudgetPolicy {
  StandalonePromptBudgetPolicy({
    required this.contextTokens,
    required this.outputReserveTokens,
    this.autoCompactTokens,
    this.estimator = const HeuristicPromptCostEstimator(),
  }) {
    if (contextTokens <= 0 ||
        outputReserveTokens <= 0 ||
        inputLimit <= 0 ||
        (autoCompactTokens ?? 1) <= 0 ||
        autoTrigger <= 0) {
      throw ArgumentError('prompt_plan.invalid_budget');
    }
  }

  final int contextTokens;
  final int outputReserveTokens;
  final int? autoCompactTokens;
  final PromptCostEstimator estimator;

  int get protocolReserveTokens => (contextTokens + 19) ~/ 20;
  int get inputLimit =>
      contextTokens - outputReserveTokens - protocolReserveTokens;
  int get autoTrigger {
    final trigger = autoCompactTokens ?? (inputLimit * 9 ~/ 10);
    return trigger < inputLimit ? trigger : inputLimit;
  }

  int get softTarget => autoTrigger * 8 ~/ 10;
  String get digest => promptDigest({
    'context_tokens': contextTokens,
    'output_reserve_tokens': outputReserveTokens,
    'protocol_reserve_tokens': protocolReserveTokens,
    'input_limit': inputLimit,
    'auto_trigger': autoTrigger,
    'soft_target': softTarget,
    'estimator_id': estimator.id,
  });
}
