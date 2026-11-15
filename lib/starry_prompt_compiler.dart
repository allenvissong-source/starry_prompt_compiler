/// Pure Dart domain prompt compilation.
///
/// This library is the single public entry point. Callers must not reach into
/// `src/`; only the symbols re-exported here are considered stable.
///
/// Host budgeting consumes frozen candidates. Complete Dart assembly is
/// exported separately by starry_prompt_standalone.dart.
library;

// Ports.
export 'src/ports/clock.dart';
export 'src/ports/locale_tag.dart';
export 'src/ports/logger.dart';
export 'src/ports/random_source.dart';
export 'src/ports/variable_store.dart';

// Models. Order kept alphabetical for readability.
export 'src/models/resolved_prompt_context.dart';
export 'src/models/character_entities.dart';
export 'src/models/compiled_prompt_plan.dart';
export 'src/models/domain_prompt_inputs.dart';
export 'src/models/prompt_admission_budget.dart';
export 'src/codec/prompt_plan_wire.dart' show promptDigest, canonicalPromptJson;
export 'src/models/conversation_turns_models.dart';
export 'src/models/prompt_budget_diagnostics.dart';
export 'src/models/persona.dart';
export 'src/models/prompt_execution_models.dart';
export 'src/codec/prompt_block_legacy_wire.dart';
export 'src/codec/prompt_block_from_legacy.dart';
export 'src/models/prompt_block.dart';
export 'src/models/prompt_manager.dart';
export 'src/models/prompt_profile.dart';
export 'src/models/regex_profile.dart';
export 'src/models/regex_script.dart';
export 'src/models/session_prompt_context.dart';
export 'src/models/skill_document.dart';
export 'src/models/variable_set.dart';
export 'src/models/world_info.dart';
export 'src/models/worldbook_entities.dart';

// Services.
export 'src/compiler/domain_prompt_compiler.dart';
export 'src/compiler/prompt_content_transformer.dart';
export 'src/macros/macro_service.dart';
export 'src/planner/prompt_execution_planner.dart';
export 'src/regex/regex_service.dart';
export 'src/worldinfo/text_recall.dart';
export 'src/worldinfo/world_info_budget_admission.dart';
export 'src/worldinfo/world_info_matcher.dart';

// Variables.
export 'src/variables/in_memory_variable_store.dart';
export 'src/variables/variable_engine.dart';
