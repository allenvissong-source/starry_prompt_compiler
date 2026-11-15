// Domain history and resolved, immutable authoring resources.
import 'conversation_turns_models.dart';
import 'session_prompt_context.dart';
import 'world_info.dart';
import 'persona.dart';
import 'prompt_block.dart';
import 'prompt_profile.dart';
import 'regex_profile.dart';
import 'variable_set.dart';
import 'character_entities.dart';
import 'worldbook_entities.dart';
import 'compiled_prompt_plan.dart';

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
    List<Worldbook> sourceWorldbooks = const [],
    List<PromptCompilationTrace> matchingTrace = const [],
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
       resolvedVariables = _deepFreezeMap(resolvedVariables),
       sourceWorldbooks = List<Worldbook>.unmodifiable(sourceWorldbooks),
       matchingTrace = List<PromptCompilationTrace>.unmodifiable(matchingTrace);

  final Character? character;
  final List<WorldInfoEntry> worldInfoEntries;
  final Map<WorldInfoPosition, List<WorldInfoEntry>> groupedWorldInfoEntries;

  /// Canonical authored blocks; wire conversion happens at the import edge.
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
  final List<Worldbook> sourceWorldbooks;
  final List<PromptCompilationTrace> matchingTrace;

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
