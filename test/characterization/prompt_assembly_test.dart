import 'package:test/test.dart';
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart'
    show
        AuthorNotePolicy,
        SessionPromptContext,
        PromptBudgetOverflowException,
        RetainDecision,
        WorldInfoEntry,
        WorldInfoOutputPolicy,
        WorldInfoPosition,
        WorldInfoRuntimePolicy,
        CharacterHistoryMessage,
        ResolvedPromptContext,
        LegacyPromptBlock,
        LegacyPromptBlockActivationPolicy,
        LegacyPromptBlockKind,
        LegacyPromptBlockPlacementPolicy,
        LegacyPromptBlockPriorityPolicy,
        LegacyPromptBlockProtectionPolicy,
        LegacyPromptBlockProvenance,
        PromptManagerConfig,
        PromptSection,
        PromptProfileResource,
        Character,
        CharacterDepthPrompt,
        promptBlocksFromLegacy,
        ExecutionInsertionMode,
        ExecutionSourceKind,
        HistorySplicePoint,
        PromptDisableOverlay,
        PromptExecutionPlan,
        ResolvedExecutionUnit,
        WorldInfoBudgetPlan;

import 'package:starry_prompt_compiler/starry_prompt_compiler.dart'
    show
        Persona,
        PersonaDescriptionSettings,
        PersonaDescriptionPosition,
        PersonaDescriptionRole,
        TurnMessageRole;

import 'package:starry_prompt_compiler/starry_prompt_standalone.dart'
    show StandaloneMessageRole;

import 'prompt_scenario.dart';

void main() {
  group('Domain compiler and standalone assembly', () {
    test(
      'consumes prompt blocks directly and filters non-chat triggers',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_1',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: <LegacyPromptBlock>[
            _customBlock(
              id: 'pre',
              promptProfileId: 'profile_1',
              content: 'PRE',
              sortOrder: 1,
            ),
            const LegacyPromptBlock(
              id: 'skip',
              promptProfileId: 'profile_1',
              kind: LegacyPromptBlockKind.custom,
              name: 'Skip',
              content: 'SKIP',
              role: 'system',
              activationPolicy: LegacyPromptBlockActivationPolicy(
                generationTriggers: <String>['quiet'],
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            const LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_1',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
            const LegacyPromptBlock(
              id: 'post',
              promptProfileId: 'profile_1',
              kind: LegacyPromptBlockKind.custom,
              name: 'Post',
              content: 'POST',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 4),
            ),
            const LegacyPromptBlock(
              id: 'depth',
              promptProfileId: 'profile_1',
              kind: LegacyPromptBlockKind.custom,
              name: 'Depth',
              content: 'DEPTH',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 0,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 5,
                injectionOrder: 0,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 21),
          updatedAt: DateTime.utc(2026, 3, 21),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(result.submittedMessage.content, 'hello');
        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>['PRE', 'older reply', 'DEPTH', 'POST'],
        );
      },
    );

    test('injects author note before history with configured role', () async {
      const promptContext = SessionPromptContext(
        authorNotePolicy: AuthorNotePolicy(
          enabled: true,
          text: 'NOTE',
          role: 'assistant',
          placement: 'before_history',
        ),
      );
      final request = _buildRequest(promptContext: promptContext);
      final character = _buildCharacter();
      final promptProfile = PromptProfileResource(
        id: 'profile_2',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_2',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 21),
        updatedAt: DateTime.utc(2026, 3, 21),
      );

      final result = await _buildFromResolvedContext(
        request: request,
        character: character,
        resolvedContext: _buildResolvedContext(
          character: character,
          promptContext: promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(result.contextMessages, hasLength(2));
      expect(
        result.contextMessages.first.role,
        StandaloneMessageRole.assistant,
      );
      expect(result.contextMessages.first.content, "[Author's Note]\nNOTE");
      expect(result.contextMessages.last.content, 'older reply');
    });

    test(
      'keeps locked system block content instead of persona override',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter(systemPrompt: 'BASE');
        final persona = Persona(
          id: 'persona_1',
          name: 'User',
          description: 'desc',
          systemPromptOverride: 'OVERRIDE',
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_3',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_3',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'BASE',
              role: 'system',
              protectionPolicy: LegacyPromptBlockProtectionPolicy(locked: true),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_3',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 21),
          updatedAt: DateTime.utc(2026, 3, 21),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: persona,
          ),
        );

        expect(result.contextMessages.first.content, 'BASE');
      },
    );

    test(
      'applies persona post-history override unless blocked by protection',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter();
        final persona = Persona(
          id: 'persona_1',
          name: 'User',
          description: 'desc',
          postHistoryInstructions: 'POST_OVERRIDE',
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_post',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_post',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'post',
              promptProfileId: 'profile_post',
              kind: LegacyPromptBlockKind.postHistoryInstructions,
              name: 'Post',
              content: 'POST_BASE',
              role: 'assistant',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: persona,
          ),
        );

        expect(result.contextMessages.last.content, 'POST_OVERRIDE');
        expect(
          result.contextMessages.last.role,
          StandaloneMessageRole.assistant,
        );
      },
    );

    test(
      'blocks persona post-history override when forbidOverride is enabled',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter();
        final persona = Persona(
          id: 'persona_1',
          name: 'User',
          description: 'desc',
          postHistoryInstructions: 'POST_OVERRIDE',
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_post_locked',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_post_locked',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'post',
              promptProfileId: 'profile_post_locked',
              kind: LegacyPromptBlockKind.postHistoryInstructions,
              name: 'Post',
              content: 'POST_BASE',
              role: 'assistant',
              protectionPolicy: LegacyPromptBlockProtectionPolicy(
                forbidOverride: true,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: persona,
          ),
        );

        expect(result.contextMessages.last.content, 'POST_BASE');
        expect(
          result.contextMessages.last.role,
          StandaloneMessageRole.assistant,
        );
      },
    );

    test(
      'keeps inSystemPrompt persona separate and injects its content once',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter(systemPrompt: 'BASE');
        final persona = Persona(
          id: 'persona_1',
          name: 'User',
          description: 'persona desc',
          descriptionSettings: const PersonaDescriptionSettings(
            position: PersonaDescriptionPosition.inSystemPrompt,
          ),
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_system_persona',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_system_persona',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'BASE',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_system_persona',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: persona,
          ),
        );

        expect(result.contextMessages, hasLength(3));
        expect(result.contextMessages.first.content, 'BASE');
        expect(result.contextMessages[1].role, StandaloneMessageRole.system);
        expect(
          result.contextMessages[1].content,
          'User persona:\npersona desc',
        );
        expect(
          result.contextMessages.where(
            (message) => message.content.toString().contains('persona desc'),
          ),
          hasLength(1),
        );
        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          isNot(contains('The user is User.\nUser description: persona desc')),
        );
      },
    );

    test('injects character depth prompt at configured depth', () async {
      final request = _buildRequest();
      final character = _buildCharacter(
        depthPrompt: const CharacterDepthPrompt(
          text: 'DEPTH PROMPT',
          depth: 0,
          role: 'assistant',
        ),
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_4',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_4',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 21),
        updatedAt: DateTime.utc(2026, 3, 21),
      );

      final result = await _buildFromResolvedContext(
        request: request,
        character: character,
        resolvedContext: _buildResolvedContext(
          character: character,
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(result.contextMessages, hasLength(2));
      expect(
        result.contextMessages.first.role,
        StandaloneMessageRole.assistant,
      );
      expect(result.contextMessages.first.content, 'older reply');
      expect(result.contextMessages.last.content, 'DEPTH PROMPT');
    });

    test(
      'resolves marker-relative-ordering around explicit marker anchors',
      () async {
        final request = _buildRequest();
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_marker',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: <LegacyPromptBlock>[
            _customBlock(
              id: 'pre',
              promptProfileId: 'profile_marker',
              content: 'PRE',
              sortOrder: 1,
            ),
            const LegacyPromptBlock(
              id: 'before_marker',
              promptProfileId: 'profile_marker',
              kind: LegacyPromptBlockKind.custom,
              name: 'Before Marker',
              content: 'BEFORE_MARKER',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'scene_marker',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            const LegacyPromptBlock(
              id: 'marker',
              promptProfileId: 'profile_marker',
              kind: LegacyPromptBlockKind.marker,
              name: 'Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'scene_marker',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
            const LegacyPromptBlock(
              id: 'after_marker',
              promptProfileId: 'profile_marker',
              kind: LegacyPromptBlockKind.custom,
              name: 'After Marker',
              content: 'AFTER_MARKER',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'scene_marker',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 4),
            ),
            _customBlock(
              id: 'mid',
              promptProfileId: 'profile_marker',
              content: 'MID',
              sortOrder: 5,
            ),
            const LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_marker',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 6),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'PRE',
            'BEFORE_MARKER',
            'AFTER_MARKER',
            'MID',
            'older reply',
          ],
        );
      },
    );

    test(
      'executes mixed-role history splice from unified multi-source plan',
      () async {
        const promptContext = SessionPromptContext(
          authorNotePolicy: AuthorNotePolicy(
            enabled: true,
            text: 'NOTE',
            role: 'user',
            depth: 1,
          ),
        );
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'older reply',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'older user',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          promptContext: promptContext,
        );
        final character = _buildCharacter(
          depthPrompt: const CharacterDepthPrompt(
            text: 'CHAR_DEPTH',
            depth: 1,
            role: 'assistant',
          ),
        );
        final persona = Persona(
          id: 'persona_1',
          name: 'User',
          description: 'persona desc',
          descriptionSettings: const PersonaDescriptionSettings(
            position: PersonaDescriptionPosition.atDepth,
            depth: 1,
            role: PersonaDescriptionRole.assistant,
          ),
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_splice',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_splice',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'absolute_block',
              promptProfileId: 'profile_splice',
              kind: LegacyPromptBlockKind.custom,
              name: 'Absolute Block',
              content: 'ABSOLUTE_BLOCK',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 1,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 2,
                injectionOrder: 3,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final worldInfoEntries = <WorldInfoEntry>[
          WorldInfoEntry(
            id: 'entry_1',
            worldbookId: 'wb_1',
            keys: const <String>['k'],
            secondaryKeys: const <String>[],
            content: 'WORLD_INFO',
            comment: 'Lore',
            enabled: true,
            constant: false,
            selective: false,
            insertionOrder: 1,
            caseSensitive: false,
            matchWholeWords: false,
            useGroupScoring: false,
            probability: 100,
            useProbability: false,
            position: WorldInfoPosition.atDepth,
            depth: 1,
            group: null,
            groupWeight: 100,
            preventRecursion: false,
            delayUntilRecursion: false,
            scanDepth: 0,
            role: 0,
            sticky: 0,
            cooldown: 0,
            delay: 0,
            characterFilter: const <String, dynamic>{},
          ),
        ];

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: promptContext,
            promptProfile: promptProfile,
            persona: persona,
            worldInfoEntries: worldInfoEntries,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.role)
              .toList(growable: false),
          <StandaloneMessageRole>[
            StandaloneMessageRole.assistant,
            StandaloneMessageRole.system,
            StandaloneMessageRole.assistant,
            StandaloneMessageRole.system,
            StandaloneMessageRole.user,
            StandaloneMessageRole.assistant,
            StandaloneMessageRole.user,
          ],
        );
        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'older reply',
            'ABSOLUTE_BLOCK',
            'CHAR_DEPTH',
            '[Lore]\nWORLD_INFO',
            "[Author's Note]\nNOTE",
            'The user is User.\nUser description: persona desc',
            'older user',
          ],
        );
      },
    );

    test(
      'keeps ANTop author note before note and ANBottom after note',
      () async {
        const promptContext = SessionPromptContext(
          authorNotePolicy: AuthorNotePolicy(
            enabled: true,
            text: 'NOTE',
            placement: 'before_history',
          ),
        );
        final request = _buildRequest(promptContext: promptContext);
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_author_note_slots',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system_marker',
              promptProfileId: 'profile_author_note_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'System Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'systemPrompt',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'author_marker',
              promptProfileId: 'profile_author_note_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'Author Marker',
              provenance: LegacyPromptBlockProvenance(identifier: 'authorNote'),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_author_note_slots',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final worldInfoEntries = <WorldInfoEntry>[
          _worldInfoEntry(
            id: 'wi_top',
            content: 'AN_TOP',
            insertionOrder: 1,
            position: WorldInfoPosition.anTop,
          ),
          _worldInfoEntry(
            id: 'wi_bottom',
            content: 'AN_BOTTOM',
            insertionOrder: 2,
            position: WorldInfoPosition.anBottom,
          ),
        ];

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: worldInfoEntries,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            '[World Info]\nAN_TOP',
            "[Author's Note]\nNOTE",
            '[World Info]\nAN_BOTTOM',
            'older reply',
          ],
        );
      },
    );

    test('places persona topAN before note and bottomAN after note', () async {
      const promptContext = SessionPromptContext(
        authorNotePolicy: AuthorNotePolicy(
          enabled: true,
          text: 'NOTE',
          placement: 'before_history',
        ),
      );
      final request = _buildRequest(promptContext: promptContext);
      final promptProfile = PromptProfileResource(
        id: 'profile_persona_author_note_slots',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'author_marker',
            promptProfileId: 'profile_persona_author_note_slots',
            kind: LegacyPromptBlockKind.marker,
            name: 'Author Marker',
            provenance: LegacyPromptBlockProvenance(identifier: 'authorNote'),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_persona_author_note_slots',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final topResult = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: promptContext,
          promptProfile: promptProfile,
          persona: Persona(
            id: 'persona_top',
            name: 'Top Persona',
            description: 'top desc',
            descriptionSettings: const PersonaDescriptionSettings(
              position: PersonaDescriptionPosition.topAN,
            ),
          ),
        ),
      );
      final bottomResult = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: promptContext,
          promptProfile: promptProfile,
          persona: Persona(
            id: 'persona_bottom',
            name: 'Bottom Persona',
            description: 'bottom desc',
            descriptionSettings: const PersonaDescriptionSettings(
              position: PersonaDescriptionPosition.bottomAN,
            ),
          ),
        ),
      );

      expect(
        topResult.contextMessages
            .map((message) => message.content)
            .toList(growable: false),
        <dynamic>[
          'The user is Top Persona.\nUser description: top desc',
          "[Author's Note]\nNOTE",
          'older reply',
        ],
      );
      expect(
        bottomResult.contextMessages
            .map((message) => message.content)
            .toList(growable: false),
        <dynamic>[
          "[Author's Note]\nNOTE",
          'The user is Bottom Persona.\nUser description: bottom desc',
          'older reply',
        ],
      );
    });

    test(
      'keeps persona topAN before history without an explicit author note marker',
      () async {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_persona_top_no_author_marker',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_persona_top_no_author_marker',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'PRE_SHELL',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_persona_top_no_author_marker',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: Persona(
              id: 'persona_top',
              name: 'Top Persona',
              description: 'top desc',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.topAN,
              ),
            ),
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'PRE_SHELL',
            'The user is Top Persona.\nUser description: top desc',
            'older reply',
          ],
        );
      },
    );

    test(
      'places persona topAN and bottomAN around note without an explicit author note marker',
      () async {
        const promptContext = SessionPromptContext(
          authorNotePolicy: AuthorNotePolicy(
            enabled: true,
            text: 'NOTE',
            placement: 'before_history',
          ),
        );
        final request = _buildRequest(promptContext: promptContext);
        final promptProfile = PromptProfileResource(
          id: 'profile_persona_an_without_marker',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_persona_an_without_marker',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'PRE_SHELL',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_persona_an_without_marker',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final topResult = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: promptContext,
            promptProfile: promptProfile,
            persona: Persona(
              id: 'persona_top',
              name: 'Top Persona',
              description: 'top desc',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.topAN,
              ),
            ),
          ),
        );
        final bottomResult = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: promptContext,
            promptProfile: promptProfile,
            persona: Persona(
              id: 'persona_bottom',
              name: 'Bottom Persona',
              description: 'bottom desc',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.bottomAN,
              ),
            ),
          ),
        );

        expect(
          topResult.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'PRE_SHELL',
            'The user is Top Persona.\nUser description: top desc',
            "[Author's Note]\nNOTE",
            'older reply',
          ],
        );
        expect(
          bottomResult.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'PRE_SHELL',
            "[Author's Note]\nNOTE",
            'The user is Bottom Persona.\nUser description: bottom desc',
            'older reply',
          ],
        );
      },
    );

    test('routes world info only into the matching named outlet', () async {
      final request = _buildRequest();
      final promptProfile = PromptProfileResource(
        id: 'profile_outlet_targeting',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'primary_outlet',
            promptProfileId: 'profile_outlet_targeting',
            kind: LegacyPromptBlockKind.marker,
            name: 'Primary Outlet',
            provenance: LegacyPromptBlockProvenance(
              identifier: 'primaryOutlet',
            ),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'secondary_outlet',
            promptProfileId: 'profile_outlet_targeting',
            kind: LegacyPromptBlockKind.marker,
            name: 'Secondary Outlet',
            provenance: LegacyPromptBlockProvenance(
              identifier: 'secondaryOutlet',
            ),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_outlet_targeting',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );
      final worldInfoEntries = <WorldInfoEntry>[
        _worldInfoEntry(
          id: 'primary',
          content: 'PRIMARY_OUTLET',
          insertionOrder: 1,
          position: WorldInfoPosition.outlet,
          outletName: 'primaryOutlet',
        ),
        _worldInfoEntry(
          id: 'secondary',
          content: 'SECONDARY_OUTLET',
          insertionOrder: 1,
          position: WorldInfoPosition.outlet,
          outletName: 'secondaryOutlet',
        ),
      ];

      final result = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
          worldInfoEntries: worldInfoEntries,
        ),
      );

      expect(
        result.contextMessages
            .map((message) => message.content)
            .toList(growable: false),
        <dynamic>[
          '[World Info]\nPRIMARY_OUTLET',
          '[World Info]\nSECONDARY_OUTLET',
          'older reply',
        ],
      );
    });

    test(
      'orders multiple units in the same outlet by explicit insertionOrder',
      () async {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_same_outlet_order',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'custom_outlet',
              promptProfileId: 'profile_same_outlet_order',
              kind: LegacyPromptBlockKind.marker,
              name: 'Custom Outlet',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'customOutlet',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_same_outlet_order',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final worldInfoEntries = <WorldInfoEntry>[
          _worldInfoEntry(
            id: 'late',
            content: 'LATE_OUTLET',
            insertionOrder: 5,
            position: WorldInfoPosition.outlet,
            outletName: 'customOutlet',
          ),
          _worldInfoEntry(
            id: 'early',
            content: 'EARLY_OUTLET',
            insertionOrder: 1,
            position: WorldInfoPosition.outlet,
            outletName: 'customOutlet',
          ),
        ];

        final result = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: worldInfoEntries,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            '[World Info]\nEARLY_OUTLET',
            '[World Info]\nLATE_OUTLET',
            'older reply',
          ],
        );
      },
    );

    test(
      'drops outlet units with missing anchors and records filtering trace',
      () async {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_missing_outlet_anchor',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_missing_outlet_anchor',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: <WorldInfoEntry>[
              _worldInfoEntry(
                id: 'missing_outlet',
                content: 'MISSING_OUTLET',
                insertionOrder: 1,
                position: WorldInfoPosition.outlet,
                outletName: 'missingOutlet',
              ),
            ],
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          isNot(contains('[World Info]\nMISSING_OUTLET')),
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.unitId == 'wi:wb_1:missing_outlet' &&
                trace.stage == 'filtering' &&
                trace.reason == 'missing_outlet_anchor',
          ),
          isTrue,
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.unitId == 'wi:wb_1:missing_outlet' &&
                trace.reason == 'outlet_routed',
          ),
          isFalse,
        );
      },
    );

    test(
      'routes history-anchored outlet units after retained history',
      () async {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_history_outlet',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_history_outlet',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'post',
              promptProfileId: 'profile_history_outlet',
              kind: LegacyPromptBlockKind.postHistoryInstructions,
              name: 'Post',
              content: 'POST_AFTER_OUTLET',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: <WorldInfoEntry>[
              _worldInfoEntry(
                id: 'history_outlet',
                content: 'HISTORY_OUTLET',
                insertionOrder: 1,
                position: WorldInfoPosition.outlet,
                runtimePolicy: const WorldInfoRuntimePolicy(
                  output: WorldInfoOutputPolicy(outlet: 'history'),
                ),
              ),
            ],
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'older reply',
            '[World Info]\nHISTORY_OUTLET',
            'POST_AFTER_OUTLET',
          ],
        );
      },
    );

    test(
      'applies independent WI budget admission before final messages',
      () async {
        final request = _buildRequest(
          inputLimit: 40,
          worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
        );
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_wi_budget',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_wi_budget',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final worldInfoEntries = <WorldInfoEntry>[
          _worldInfoEntry(id: 'wi_small', content: 'SMALL', insertionOrder: 1),
          _worldInfoEntry(
            id: 'wi_large',
            content:
                'THIS WORLD INFO ENTRY IS LARGE ENOUGH TO FAIL THE SUB-BUDGET',
            insertionOrder: 2,
          ),
          _worldInfoEntry(
            id: 'wi_ignore',
            content: 'IGNORE_BUDGET_ENTRY',
            insertionOrder: 3,
            ignoreBudget: true,
          ),
        ];

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: worldInfoEntries,
          ),
        );

        final contents = result.contextMessages
            .map((message) => message.content)
            .toList(growable: false);
        expect(contents, contains('[World Info]\nSMALL'));
        expect(contents, contains('[World Info]\nIGNORE_BUDGET_ENTRY'));
        expect(
          contents,
          isNot(
            contains(
              '[World Info]\nTHIS WORLD INFO ENTRY IS LARGE ENOUGH TO FAIL THE SUB-BUDGET',
            ),
          ),
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.stage == 'budget' &&
                trace.reason == 'world_info_budget_exceeded' &&
                trace.unitId.contains('wi_large'),
          ),
          isTrue,
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.stage == 'budget' &&
                trace.reason == 'world_info_budget_exceeded' &&
                trace.unitId.contains('wi_large'),
          ),
          isTrue,
        );
      },
    );

    test('session disable overlay blocks prompt in final messages', () async {
      final request = _buildRequest(
        sessionDisableOverlay: const PromptDisableOverlay(
          disabledUnitIds: <String>['system'],
        ),
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_session_disable',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'system',
            promptProfileId: 'profile_session_disable',
            kind: LegacyPromptBlockKind.systemPrompt,
            name: 'System',
            content: 'SYSTEM_DISABLED',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_session_disable',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final result = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(
        result.contextMessages
            .map((message) => message.content)
            .toList(growable: false),
        isNot(contains('SYSTEM_DISABLED')),
      );
      expect(
        result.trace.any(
          (trace) =>
              trace.stage == 'filtering' &&
              trace.reason == 'session_disable_overlay' &&
              trace.unitId == 'system',
        ),
        isTrue,
      );
    });

    test('character disable overlay blocks prompt in final messages', () async {
      final request = _buildRequest(
        characterDisableOverlay: const PromptDisableOverlay(
          disabledUnitIds: <String>['post'],
        ),
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_character_disable',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_character_disable',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'post',
            promptProfileId: 'profile_character_disable',
            kind: LegacyPromptBlockKind.postHistoryInstructions,
            name: 'Post',
            content: 'POST_DISABLED',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final result = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(
        result.contextMessages
            .map((message) => message.content)
            .toList(growable: false),
        isNot(contains('POST_DISABLED')),
      );
      expect(
        result.trace.any(
          (trace) =>
              trace.stage == 'filtering' &&
              trace.reason == 'character_disable_overlay' &&
              trace.unitId == 'post',
        ),
        isTrue,
      );
    });

    test('budget and outlet trace remain observable in final result', () async {
      final request = _buildRequest(
        inputLimit: 40,
        worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_trace_visibility',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'trace_outlet',
            promptProfileId: 'profile_trace_visibility',
            kind: LegacyPromptBlockKind.marker,
            name: 'Trace Outlet',
            provenance: LegacyPromptBlockProvenance(identifier: 'traceOutlet'),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_trace_visibility',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );
      final worldInfoEntries = <WorldInfoEntry>[
        _worldInfoEntry(
          id: 'trace_small',
          content: 'TRACE_SMALL',
          insertionOrder: 1,
          position: WorldInfoPosition.outlet,
          outletName: 'traceOutlet',
        ),
        _worldInfoEntry(
          id: 'trace_large',
          content:
              'THIS WORLD INFO ENTRY IS LARGE ENOUGH TO FAIL THE SUB-BUDGET',
          insertionOrder: 2,
          position: WorldInfoPosition.outlet,
          outletName: 'traceOutlet',
        ),
      ];

      final result = await _buildFromResolvedContext(
        request: request,
        character: _buildCharacter(),
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
          worldInfoEntries: worldInfoEntries,
        ),
      );

      expect(
        result.trace.any(
          (trace) =>
              trace.stage == 'routing' &&
              trace.reason == 'outlet_routed' &&
              trace.outletName == 'traceOutlet' &&
              trace.unitId.contains('trace_small'),
        ),
        isTrue,
      );
      expect(
        result.trace.any(
          (trace) =>
              trace.stage == 'budget' &&
              trace.reason == 'world_info_budget_exceeded' &&
              trace.unitId.contains('trace_large'),
        ),
        isTrue,
      );
    });

    test('keeps mandatory shell when total budget is tight', () async {
      final request = _buildRequest(inputLimit: 24);
      final character = _buildCharacter(systemPrompt: 'BASE_SYSTEM_PROMPT');
      final promptProfile = PromptProfileResource(
        id: 'profile_budget_mandatory',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'system',
            promptProfileId: 'profile_budget_mandatory',
            kind: LegacyPromptBlockKind.systemPrompt,
            name: 'System',
            content: 'BASE_SYSTEM_PROMPT',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'optional',
            promptProfileId: 'profile_budget_mandatory',
            kind: LegacyPromptBlockKind.custom,
            name: 'Optional',
            content: 'OPTIONAL_SHELL_SHOULD_DROP',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_budget_mandatory',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final result = await _buildFromResolvedContext(
        request: request,
        character: character,
        resolvedContext: _buildResolvedContext(
          character: character,
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      final contents = result.contextMessages
          .map((message) => message.content)
          .toList(growable: false);
      expect(contents, contains('BASE_SYSTEM_PROMPT'));
      expect(contents, isNot(contains('OPTIONAL_SHELL_SHOULD_DROP')));
    });

    test(
      'drops old history as a contiguous suffix under budget pressure',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'OLD_MESSAGE_1_WITH_LENGTH',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'RECENT_MESSAGE_2_WITH_LENGTH',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'LATEST_MESSAGE_3_WITH_LENGTH',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 28,
        );
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_history_budget',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_history_budget',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>[
            'RECENT_MESSAGE_2_WITH_LENGTH',
            'LATEST_MESSAGE_3_WITH_LENGTH',
          ],
        );
      },
    );

    test(
      'rejects an overflowing recent-history floor instead of skipping it',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'OLD',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'RECENT_BUT_TOO_LONG_FOR_BUDGET_WINDOW',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'LATEST',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 20,
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_suffix_cutoff',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_suffix_cutoff',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        await expectLater(
          () => _buildFromResolvedContext(
            request: request,
            character: _buildCharacter(),
            resolvedContext: _buildResolvedContext(
              character: _buildCharacter(),
              promptContext: request.promptContext,
              promptProfile: promptProfile,
            ),
          ),
          throwsA(
            isA<PromptBudgetOverflowException>()
                .having((e) => e.code, 'code', 'context_limit')
                .having(
                  (e) => e.trace.single.reason,
                  'reason',
                  'protected_context_exceeds_input_limit',
                ),
          ),
        );
      },
    );

    test(
      'collapses deep splice units to history start when anchor is cropped',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'OLD_A' * 16,
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'RECENT_B',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'NEWEST_C',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 25,
        );
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_cropped_anchor',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_cropped_anchor',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'deep',
              promptProfileId: 'profile_cropped_anchor',
              kind: LegacyPromptBlockKind.custom,
              name: 'Deep',
              content: 'DEEP_SPLICE',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 3,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 2,
                injectionOrder: 0,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>['DEEP_SPLICE', 'RECENT_B', 'NEWEST_C'],
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.reason == 'anchor_relocated_after_compaction' &&
                trace.unitId.contains('deep'),
          ),
          isTrue,
        );
      },
    );

    test(
      'keeps history-start fallback after pre-history shell content',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'OLDER_A',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'RECENT_B',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'LATEST_C',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 32,
        );
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_cropped_anchor_with_shell',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'pre',
              promptProfileId: 'profile_cropped_anchor_with_shell',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'PRE_SHELL',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_cropped_anchor_with_shell',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'deep',
              promptProfileId: 'profile_cropped_anchor_with_shell',
              kind: LegacyPromptBlockKind.custom,
              name: 'Deep',
              content: 'DEEP_SPLICE',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 3,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 3,
                injectionOrder: 0,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>['PRE_SHELL', 'DEEP_SPLICE', 'RECENT_B', 'LATEST_C'],
        );
      },
    );

    test(
      'retains admitted splice content when compaction removes its anchor',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'OLDER_A',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: 'RECENT_B',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'LATEST_C',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 28,
        );
        final executionPlan = PromptExecutionPlan(
          shellSequence: const <ResolvedExecutionUnit>[],
          disabledUnits: const <ResolvedExecutionUnit>[],
          historySplicePoints: <HistorySplicePoint>[
            HistorySplicePoint(
              offsetFromEnd: 3,
              units: const <ResolvedExecutionUnit>[
                ResolvedExecutionUnit(
                  id: 'synthetic_drop_splice',
                  sourceKind: ExecutionSourceKind.promptBlock,
                  sourceRef: 'test',
                  enabled: true,
                  contentTemplate: 'RELOCATED',
                  role: 'system',
                  insertionMode: ExecutionInsertionMode.historySplice,
                  depth: 3,
                ),
              ],
            ),
          ],
        );

        final result = assembleScenario(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
          ),
          executionPlan: executionPlan,
          assembledHistory: <CharacterHistoryMessage>[
            ...request.history,
            CharacterHistoryMessage(
              role: TurnMessageRole.user,
              content: request.pendingUserInput.text,
              timestamp: DateTime.now(),
            ),
          ],
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          contains('RELOCATED'),
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.unitId.contains('synthetic_drop_splice') &&
                trace.reason == 'anchor_relocated_after_compaction',
          ),
          isTrue,
        );
      },
    );

    test(
      'places the zero-depth splice at the tail when history is empty',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: const <CharacterHistoryMessage>[],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 20,
        );
        final character = _buildCharacter();
        final promptProfile = PromptProfileResource(
          id: 'profile_tail_splice_anchor_loss',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'pre',
              promptProfileId: 'profile_tail_splice_anchor_loss',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'PRE_SHELL',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_tail_splice_anchor_loss',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'tail',
              promptProfileId: 'profile_tail_splice_anchor_loss',
              kind: LegacyPromptBlockKind.custom,
              name: 'Tail',
              content: 'TAIL_SPLICE',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 0,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 3,
                injectionOrder: 0,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          result.contextMessages
              .map((message) => message.content)
              .toList(growable: false),
          <dynamic>['PRE_SHELL', 'TAIL_SPLICE'],
        );
        expect(
          result.trace.any(
            (trace) =>
                trace.reason == 'anchor_relocated_after_compaction' &&
                trace.unitId.contains('tail'),
          ),
          isFalse,
        );
        expect(
          result.assembly.messages.where(
            (message) => message.content == 'hello',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'admits world info by explicit budget priority instead of plan traversal order',
      () async {
        final request = PromptScenarioInput(
          sessionId: 'session_1',
          topicId: 'topic_1',
          characterId: 'character_1',
          history: <CharacterHistoryMessage>[
            CharacterHistoryMessage(
              role: TurnMessageRole.assistant,
              content: 'RECENT_HISTORY',
              timestamp: DateTime.utc(2026, 3, 21),
            ),
          ],
          pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
          inputLimit: 40,
          worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
        );
        final executionPlan = PromptExecutionPlan(
          shellSequence: const <ResolvedExecutionUnit>[
            ResolvedExecutionUnit(
              id: 'shell_wi_late',
              sourceKind: ExecutionSourceKind.worldInfoEntry,
              sourceRef: 'wb_1',
              enabled: true,
              contentTemplate: 'SHELL_WI',
              role: 'system',
              insertionMode: ExecutionInsertionMode.relativeBefore,
              anchorId: 'systemPrompt',
              sourceOrder: 100,
              injectionOrder: 10,
            ),
          ],
          disabledUnits: const <ResolvedExecutionUnit>[],
          historySplicePoints: <HistorySplicePoint>[
            HistorySplicePoint(
              offsetFromEnd: 1,
              units: const <ResolvedExecutionUnit>[
                ResolvedExecutionUnit(
                  id: 'splice_wi_early',
                  sourceKind: ExecutionSourceKind.worldInfoEntry,
                  sourceRef: 'wb_1',
                  enabled: true,
                  contentTemplate: 'SPLICE_WI',
                  role: 'system',
                  insertionMode: ExecutionInsertionMode.historySplice,
                  depth: 1,
                  sourceOrder: 200,
                  injectionOrder: 1,
                ),
              ],
            ),
          ],
          worldInfoBudgetPlan: const WorldInfoBudgetPlan(enabled: true),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: _buildCharacter(),
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
          ),
          executionPlan: executionPlan,
        );

        final contents = result.contextMessages
            .map((message) => message.content)
            .toList(growable: false);
        expect(contents, contains('SPLICE_WI'));
        expect(contents, isNot(contains('SHELL_WI')));
      },
    );

    test('throws structured mandatory overflow with trace', () async {
      final request = _buildRequest(inputLimit: 10);
      final character = _buildCharacter(
        systemPrompt: 'MANDATORY_SYSTEM_PROMPT_THAT_OVERFLOWS',
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_mandatory_overflow',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'system',
            promptProfileId: 'profile_mandatory_overflow',
            kind: LegacyPromptBlockKind.systemPrompt,
            name: 'System',
            content: 'MANDATORY_SYSTEM_PROMPT_THAT_OVERFLOWS',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_mandatory_overflow',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      await expectLater(
        () => _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        ),
        throwsA(
          isA<PromptBudgetOverflowException>()
              .having((error) => error.code, 'code', 'context_limit')
              .having(
                (error) => error.trace.any(
                  (trace) =>
                      trace.decision == RetainDecision.dropMandatoryOverflow,
                ),
                'trace contains mandatory overflow',
                isTrue,
              ),
        ),
      );
    });

    test(
      'drops optional content under total budget while keeping submitted and shell',
      () async {
        final request = _buildRequest(inputLimit: 22);
        final character = _buildCharacter(systemPrompt: 'MANDATORY');
        final promptProfile = PromptProfileResource(
          id: 'profile_total_budget',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_total_budget',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'MANDATORY',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'optional',
              promptProfileId: 'profile_total_budget',
              kind: LegacyPromptBlockKind.custom,
              name: 'Optional',
              content: 'OPTIONAL_PROMPT',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_total_budget',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final result = await _buildFromResolvedContext(
          request: request,
          character: character,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        final contents = result.contextMessages
            .map((message) => message.content)
            .toList(growable: false);
        expect(contents, contains('MANDATORY'));
        expect(contents, contains('older reply'));
        expect(contents, isNot(contains('OPTIONAL_PROMPT')));
        expect(result.submittedMessage.content, 'hello');
      },
    );
  });
}

LegacyPromptBlock _customBlock({
  required String id,
  required String promptProfileId,
  required String content,
  required int sortOrder,
}) {
  return LegacyPromptBlock(
    id: id,
    promptProfileId: promptProfileId,
    kind: LegacyPromptBlockKind.custom,
    name: id,
    content: content,
    role: 'system',
    priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: sortOrder),
  );
}

PromptScenarioInput _buildRequest({
  SessionPromptContext? promptContext,
  int inputLimit = 100000,
  WorldInfoBudgetPlan worldInfoBudgetPlan = const WorldInfoBudgetPlan(),
  PromptDisableOverlay sessionDisableOverlay = const PromptDisableOverlay(),
  PromptDisableOverlay characterDisableOverlay = const PromptDisableOverlay(),
}) {
  return PromptScenarioInput(
    sessionId: 'session_1',
    topicId: 'topic_1',
    characterId: 'character_1',
    history: <CharacterHistoryMessage>[
      CharacterHistoryMessage(
        role: TurnMessageRole.assistant,
        content: 'older reply',
        timestamp: DateTime.utc(2026, 3, 21),
      ),
    ],
    pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
    inputLimit: inputLimit,
    worldInfoBudgetPlan: worldInfoBudgetPlan,
    promptContext: promptContext ?? const SessionPromptContext(),
    sessionDisableOverlay: sessionDisableOverlay,
    characterDisableOverlay: characterDisableOverlay,
  );
}

Future<ScenarioAssembly> _buildFromResolvedContext({
  required PromptScenarioInput request,
  required Character character,
  required ResolvedPromptContext resolvedContext,
  PromptExecutionPlan? executionPlan,
  List<CharacterHistoryMessage>? assembledHistory,
}) async => assembleScenario(
  request: request,
  character: character,
  resolvedContext: resolvedContext,
  executionPlan: executionPlan,
  assembledHistory: assembledHistory,
);

Character _buildCharacter({
  String systemPrompt = '',
  CharacterDepthPrompt? depthPrompt,
}) {
  return Character(
    id: 'character_1',
    ownerUserId: 'user_1',
    name: 'Char',
    nickname: 'Char',
    description: '',
    personality: '',
    scenario: '',
    firstMessage: '',
    alternateGreetings: const <String>[],
    exampleMessages: '',
    systemPrompt: systemPrompt,
    postHistoryInstructions: '',
    depthPrompt: depthPrompt,
    tags: const <String>[],
    isSystem: false,
    visibilityScope: 'private',
    createdAt: DateTime.utc(2026, 3, 21),
    updatedAt: DateTime.utc(2026, 3, 21),
  );
}

WorldInfoEntry _worldInfoEntry({
  required String id,
  required String content,
  required int insertionOrder,
  bool ignoreBudget = false,
  WorldInfoPosition position = WorldInfoPosition.before,
  String? outletName,
  WorldInfoRuntimePolicy? runtimePolicy,
}) {
  return WorldInfoEntry(
    id: id,
    worldbookId: 'wb_1',
    keys: const <String>['k'],
    secondaryKeys: const <String>[],
    content: content,
    comment: '',
    enabled: true,
    constant: false,
    selective: false,
    insertionOrder: insertionOrder,
    caseSensitive: false,
    matchWholeWords: false,
    useGroupScoring: false,
    probability: 100,
    useProbability: false,
    position: position,
    depth: 0,
    group: null,
    groupWeight: 100,
    preventRecursion: false,
    delayUntilRecursion: false,
    scanDepth: 0,
    role: 0,
    sticky: 0,
    cooldown: 0,
    delay: 0,
    characterFilter: const <String, dynamic>{},
    ignoreBudget: ignoreBudget,
    outletName: outletName,
    runtimePolicy: runtimePolicy,
  );
}

ResolvedPromptContext _buildResolvedContext({
  required Character character,
  required SessionPromptContext promptContext,
  PromptProfileResource? promptProfile,
  Persona? persona,
  List<WorldInfoEntry> worldInfoEntries = const <WorldInfoEntry>[],
}) {
  return ResolvedPromptContext(
    character: character,
    worldInfoEntries: worldInfoEntries,
    groupedWorldInfoEntries: <WorldInfoPosition, List<WorldInfoEntry>>{
      for (final position in WorldInfoPosition.values)
        position: worldInfoEntries
            .where((entry) => entry.position == position)
            .toList(growable: false),
    },
    resolvedPromptBlocks: promptBlocksFromLegacy(
      promptProfile?.resolvedBlocks ??
          PromptManagerConfig.defaultConfig().toPromptBlocks(),
    ),
    promptContext: promptContext,
    persona: persona,
    promptProfile: promptProfile,
    resolvedVariables: const <String, dynamic>{},
  );
}
