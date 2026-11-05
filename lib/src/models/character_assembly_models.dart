// Package-internal model: character-turn assembly request / result / history.
//
// Provenance: verbatim copy of
//   lib/features/chat_character/domain/models/character_assembly_models.dart
// All 11 external imports rewritten to relative in-package paths (see the
// authoritative mapping table in the copy script). Class / enum / field
// names are byte-identical to the Starry source.
import 'conversation_turns_models.dart';
import 'session_prompt_context.dart';
import 'message_budget_models.dart';
import 'world_info.dart';
import 'prompt_execution_models.dart';
import 'persona.dart';
import 'prompt_block.dart';
import 'prompt_profile.dart';
import 'regex_profile.dart';
import 'variable_set.dart';
import 'character_entities.dart';

class CharacterAssemblyRequest {
  const CharacterAssemblyRequest({
    required this.sessionId,
    required this.topicId,
    required this.characterId,
    required this.history,
    required this.pendingUserInput,
    this.generationType = 'chat',
    this.budgetPlan = const MessageBudgetPlan(),
    this.worldInfoBudgetPlan = const WorldInfoBudgetPlan(),
    this.promptContext = const SessionPromptContext(),
    this.sessionDisableOverlay = const PromptDisableOverlay(),
    this.characterDisableOverlay = const PromptDisableOverlay(),
  });

  final String sessionId;
  final String topicId;
  final String characterId;
  final List<CharacterHistoryMessage> history;
  final CharacterPendingUserInput pendingUserInput;
  final String generationType;
  final MessageBudgetPlan budgetPlan;
  final WorldInfoBudgetPlan worldInfoBudgetPlan;
  final SessionPromptContext promptContext;
  final PromptDisableOverlay sessionDisableOverlay;
  final PromptDisableOverlay characterDisableOverlay;
}

class CharacterTurnAssemblyResult {
  const CharacterTurnAssemblyResult({
    required this.messages,
    required this.submittedMessage,
    this.croppingTrace = const <CroppingTrace>[],
    this.executionTrace = const <ExecutionTraceEntry>[],
  });

  final List<TurnMessage> messages;
  final TurnMessage submittedMessage;
  final List<CroppingTrace> croppingTrace;
  final List<ExecutionTraceEntry> executionTrace;
}

class CharacterHistoryMessage {
  const CharacterHistoryMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.messageId,
  });

  final TurnMessageRole role;
  final dynamic content;
  final DateTime timestamp;
  final String? messageId;

  String get textContent => extractTextFromTurnContent(content);
}

class CharacterPendingUserInput {
  const CharacterPendingUserInput({
    required this.text,
    this.attachments = const <CharacterLocalImageAttachment>[],
  });

  final String text;
  final List<CharacterLocalImageAttachment> attachments;
}

class CharacterLocalImageAttachment {
  const CharacterLocalImageAttachment({
    required this.path,
    required this.mimeType,
    this.sizeBytes,
  });

  final String path;
  final String mimeType;
  final int? sizeBytes;
}

class ResolvedPromptContext {
  ResolvedPromptContext({
    required this.character,
    required List<WorldInfoEntry> worldInfoEntries,
    required Map<WorldInfoPosition, List<WorldInfoEntry>>
    groupedWorldInfoEntries,
    required List<PromptBlock> resolvedPromptBlocks,
    required this.promptContext,
    required Map<String, dynamic> resolvedVariables,
    List<String> worldInfoCandidateIds = const <String>[],
    this.worldInfoContextText = '',
    Map<String, int> worldbookTokenBudgets = const <String, int>{},
    this.persona,
    this.promptProfile,
    this.regexProfile,
    this.variableSet,
  }) : worldInfoEntries = List<WorldInfoEntry>.unmodifiable(worldInfoEntries),
       groupedWorldInfoEntries =
           Map<WorldInfoPosition, List<WorldInfoEntry>>.unmodifiable(
             groupedWorldInfoEntries.map(
               (key, value) =>
                   MapEntry(key, List<WorldInfoEntry>.unmodifiable(value)),
             ),
           ),
       resolvedPromptBlocks = List<PromptBlock>.unmodifiable(
         resolvedPromptBlocks,
       ),
       worldInfoCandidateIds = List<String>.unmodifiable(worldInfoCandidateIds),
       worldbookTokenBudgets = Map<String, int>.unmodifiable(
         worldbookTokenBudgets,
       ),
       resolvedVariables = _deepFreezeMap(resolvedVariables);

  final Character character;
  final List<WorldInfoEntry> worldInfoEntries;
  final Map<WorldInfoPosition, List<WorldInfoEntry>> groupedWorldInfoEntries;

  /// Prompt blocks in the V2 shape.
  ///
  /// V2 is the only shape this type accepts. A caller still holding V1 blocks
  /// converts at its own edge with promptBlocksFromLegacy, which keeps the
  /// conversion visible at the point where legacy data actually enters rather
  /// than hiding it inside a constructor every caller goes through. Everything
  /// downstream - the planner in particular - sees only V2, so no version
  /// branch exists inside the compiler.
  final List<PromptBlock> resolvedPromptBlocks;
  final SessionPromptContext promptContext;
  final List<String> worldInfoCandidateIds;
  final String worldInfoContextText;
  final Map<String, int> worldbookTokenBudgets;
  final Persona? persona;
  final PromptProfileResource? promptProfile;
  final RegexProfileBundle? regexProfile;
  final VariableSetResource? variableSet;
  final Map<String, dynamic> resolvedVariables;

  bool get hasAuthorNote => promptContext.hasAuthorNote;
}

Map<String, dynamic> _deepFreezeMap(Map<String, dynamic> source) {
  return Map<String, dynamic>.unmodifiable(
    source.map((key, value) => MapEntry(key, _deepFreezeValue(value))),
  );
}

// Runtime variables are expected to be acyclic, JSON-like container trees.
// This freezer only normalizes nested Map/List/Set structures and is not a
// general-purpose object freezer for arbitrary mutable object graphs.
dynamic _deepFreezeValue(dynamic value) {
  if (value is Map) {
    return Map<dynamic, dynamic>.unmodifiable(
      value.map(
        (key, nestedValue) => MapEntry(key, _deepFreezeValue(nestedValue)),
      ),
    );
  }
  if (value is List) {
    return List<dynamic>.unmodifiable(value.map(_deepFreezeValue));
  }
  if (value is Set) {
    return Set<dynamic>.unmodifiable(value.map(_deepFreezeValue));
  }
  return value;
}

String extractTextFromTurnContent(dynamic content) {
  if (content is String) {
    return content;
  }
  if (content is List) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      final type = (part['type'] ?? '').toString().trim().toLowerCase();
      if (type != 'text') continue;
      final text = (part['text'] ?? '').toString();
      if (text.trim().isEmpty) continue;
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(text);
    }
    return buffer.toString();
  }
  if (content is Map) {
    final text = (content['text'] ?? '').toString();
    return text;
  }
  return '';
}
