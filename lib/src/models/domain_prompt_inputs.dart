import 'character_entities.dart';
import 'persona.dart';
import 'prompt_block.dart';
import 'prompt_execution_models.dart';
import 'session_prompt_context.dart';
import 'world_info.dart';

/// Flat injection hosts own placement, text expansion and the final context.
enum WorldInfoPlanningMode { contextualMessages, flatInjections }

/// Authorized, already-resolved domain inputs. History is a read-only count
/// here; text projections for matching and macros are supplied by the owner.
class DomainPromptPlanningInput {
  DomainPromptPlanningInput({
    this.character,
    this.identityContent,
    this.persona,
    List<PromptBlock> promptBlocks = const [],
    List<WorldInfoEntry> worldInfoEntries = const [],
    this.promptContext = const SessionPromptContext(),
    this.historyLength = 0,
    this.generationType = 'chat',
    this.sessionDisableOverlay = const PromptDisableOverlay(),
    this.characterDisableOverlay = const PromptDisableOverlay(),
    this.worldInfoBudgetPlan = const WorldInfoBudgetPlan(),
    this.worldInfoPlanningMode = WorldInfoPlanningMode.contextualMessages,
  }) : promptBlocks = List.unmodifiable(promptBlocks),
       worldInfoEntries = List.unmodifiable(worldInfoEntries) {
    if (historyLength < 0) {
      throw ArgumentError.value(historyLength, 'historyLength');
    }
  }

  final Character? character;
  final DomainIdentityContent? identityContent;
  final Persona? persona;
  final List<PromptBlock> promptBlocks;
  final List<WorldInfoEntry> worldInfoEntries;
  final SessionPromptContext promptContext;
  final int historyLength;
  final String generationType;
  final PromptDisableOverlay sessionDisableOverlay;
  final PromptDisableOverlay characterDisableOverlay;
  final WorldInfoBudgetPlan worldInfoBudgetPlan;
  final WorldInfoPlanningMode worldInfoPlanningMode;
}

/// Session-frozen built-in identity supplied by the owning application.
class DomainIdentityContent {
  const DomainIdentityContent({required this.resourceId, required this.text});
  final String resourceId;
  final String text;
}
