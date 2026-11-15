import 'dart:convert';

import '../macros/macro_service.dart';
import '../models/regex_profile.dart';
import '../models/regex_script.dart';
import '../regex/regex_service.dart';
import '../variables/in_memory_variable_store.dart';
import '../variables/variable_engine.dart';

/// One compilation owns one scratch store. Callers never pass a durable store.
class PromptContentTransformer {
  PromptContentTransformer({
    required this.macroService,
    required this.chatId,
    Map<String, dynamic> globalVariables = const {},
    Map<String, dynamic> localOverrides = const {},
    this.regexProfile,
    RegexService? regexService,
  }) : regexService = regexService ?? RegexService() {
    final scratch = InMemoryVariableStore();
    // Each scope gets its own mutable copy: array macros must not mutate the
    // frozen source, the other scope, or a caller-owned container.
    dynamic clone(dynamic value) => jsonDecode(jsonEncode(value));
    for (final entry in globalVariables.entries) {
      scratch.setGlobal(entry.key, clone(entry.value));
      scratch.setLocal(chatId, entry.key, clone(entry.value));
    }
    for (final entry in localOverrides.entries) {
      scratch.setLocal(chatId, entry.key, clone(entry.value));
    }
    _variables = VariableEngine(store: scratch);
  }

  final MacroService macroService;
  final String chatId;
  final RegexProfileBundle? regexProfile;
  final RegexService regexService;
  late final VariableEngine _variables;

  String expand(String template, {RegexPlacement? placement, int? depth}) =>
      applyRegex(
        _variables.processVariableMacros(
          macroService.process(template),
          chatId: chatId,
        ),
        placement: placement,
        depth: depth,
      );

  /// User input is only regex transformed; macro execution is for domain text.
  String applyRegex(String text, {RegexPlacement? placement, int? depth}) {
    return applyPromptRegex(
      text,
      regexProfile,
      placement: placement,
      regexService: regexService,
      characterName: macroService.context.characterName,
      userName: macroService.context.userName,
      isPrompt: true,
      depth: depth,
    );
  }
}

String applyPromptRegex(
  String text,
  RegexProfileBundle? profile, {
  required RegexPlacement? placement,
  required RegexService regexService,
  required String? characterName,
  required String? userName,
  required bool isPrompt,
  int? depth,
}) {
  if (text.isEmpty ||
      placement == null ||
      profile == null ||
      !profile.profile.settings.enabled) {
    return text;
  }
  final settings = profile.profile.settings;
  final enabled = switch (placement) {
    RegexPlacement.userInput => settings.applyToUserInput,
    RegexPlacement.aiOutput => settings.applyToAiOutput,
    RegexPlacement.slashCommand => settings.applyToSlashCommands,
    RegexPlacement.worldInfo => settings.applyToWorldInfo,
    RegexPlacement.reasoning => settings.applyToReasoning,
  };
  if (!enabled) return text;
  return regexService.getRegexedString(
    text,
    placement,
    profile.scripts,
    characterName: characterName,
    userName: userName,
    isPrompt: isPrompt,
    depth: depth,
  );
}
