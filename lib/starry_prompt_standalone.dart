/// Independent Dart-host assembly. Starry uses the domain compiler library
/// and delegates final model messages/history/budget decisions to Rust.
library;

export 'starry_prompt_compiler.dart';
export 'src/standalone/heuristic_cost_estimator.dart';
export 'src/standalone/prompt_assembler.dart';
export 'src/standalone/prompt_budget_policy.dart';
