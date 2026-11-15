import 'package:test/test.dart';
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart'
    show TurnMessageRole, DomainPromptPlanningInput, PromptExecutionPlan;
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart'
    show
        AuthorNotePolicy,
        SessionPromptContext,
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
        ExecutionDisableSource,
        ExecutionInsertionMode,
        ExecutionSourceKind,
        ExecutionTraceStage,
        PromptDisableOverlay,
        PromptExecutionPlanner,
        ResolvedExecutionUnit;

import 'package:starry_prompt_compiler/starry_prompt_compiler.dart'
    show
        Persona,
        PersonaDescriptionSettings,
        PersonaDescriptionPosition,
        PersonaDescriptionRole;
import 'prompt_scenario.dart';

void main() {
  group('PromptExecutionPlanner', () {
    test(
      'builds shell sequence and history splice points from prompt blocks',
      () {
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
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final plan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
          ),
        );

        expect(
          plan.shellSequence.map((unit) => unit.id).toList(growable: false),
          <String>['pre', 'history', 'post'],
        );
        expect(
          plan.shellSequence.first.insertionMode,
          ExecutionInsertionMode.relativeBefore,
        );
        expect(plan.shellSequence[1].sourceKind, ExecutionSourceKind.marker);
        expect(
          plan.shellSequence.last.insertionMode,
          ExecutionInsertionMode.afterHistory,
        );
        expect(plan.disabledUnits.map((unit) => unit.id), <String>['skip']);
        expect(plan.historySplicePoints, hasLength(1));
        expect(plan.historySplicePoints.single.offsetFromEnd, 0);
        expect(
          plan.historySplicePoints.single.units.map((unit) => unit.id),
          <String>['depth'],
        );
      },
    );

    test(
      'orders same-depth splice units by descending injectionOrder then role precedence',
      () {
        final request = _buildRequest(
          promptContext: const SessionPromptContext(
            authorNotePolicy: AuthorNotePolicy(
              enabled: true,
              text: 'NOTE',
              role: 'user',
              depth: 1,
            ),
          ),
        );
        final promptProfile = PromptProfileResource(
          id: 'profile_splice_order',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_splice_order',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'absolute_high_user',
              promptProfileId: 'profile_splice_order',
              kind: LegacyPromptBlockKind.custom,
              name: 'Absolute High User',
              content: 'ABS_HIGH_USER',
              role: 'user',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 1,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 10,
                injectionOrder: 10,
              ),
            ),
            LegacyPromptBlock(
              id: 'absolute_high_system',
              promptProfileId: 'profile_splice_order',
              kind: LegacyPromptBlockKind.custom,
              name: 'Absolute High System',
              content: 'ABS_HIGH_SYSTEM',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 1,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 11,
                injectionOrder: 10,
              ),
            ),
            LegacyPromptBlock(
              id: 'absolute_low_system',
              promptProfileId: 'profile_splice_order',
              kind: LegacyPromptBlockKind.custom,
              name: 'Absolute Low System',
              content: 'ABS_LOW_SYSTEM',
              role: 'system',
              placementPolicy: LegacyPromptBlockPlacementPolicy(
                anchor: 'absolute',
                injectionPosition: 1,
                depth: 1,
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(
                sortOrder: 12,
                injectionOrder: 2,
              ),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final persona = Persona(
          id: 'persona_depth',
          name: 'Depth Persona',
          description: 'PERSONA_DEPTH',
          descriptionSettings: const PersonaDescriptionSettings(
            position: PersonaDescriptionPosition.atDepth,
            depth: 1,
            role: PersonaDescriptionRole.assistant,
          ),
        );
        final character = _buildCharacter().copyWith(
          depthPrompt: const CharacterDepthPrompt(text: 'CHAR_DEPTH', depth: 1),
        );

        final plan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: character,
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: persona,
            worldInfoEntries: <WorldInfoEntry>[
              _worldInfoEntry(
                id: 'wi_depth',
                content: 'WI_DEPTH',
                insertionOrder: 10,
                position: WorldInfoPosition.atDepth,
                depth: 1,
                role: 1,
              ),
            ],
          ),
        );

        final point = plan.historySplicePoints.firstWhere(
          (item) => item.offsetFromEnd == 1,
        );

        expect(
          point.units.map((unit) => unit.id).toList(growable: false),
          <String>[
            'absolute_high_system',
            'absolute_high_user',
            'wi:wb_1:wi_depth',
            'absolute_low_system',
            'character_depth_prompt:character_1',
            'author_note',
            'persona:persona_depth',
          ],
        );
      },
    );

    test('includes author note as shell unit when cadence allows it', () {
      const promptContext = SessionPromptContext(
        authorNotePolicy: AuthorNotePolicy(
          enabled: true,
          text: 'NOTE',
          role: 'assistant',
          placement: 'before_history',
        ),
      );
      final request = _buildRequest(promptContext: promptContext);
      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: promptContext,
        ),
      );

      final authorNoteUnit = plan.shellSequence.firstWhere(
        (unit) => unit.sourceKind == ExecutionSourceKind.authorNote,
      );
      expect(authorNoteUnit.role, 'assistant');
      expect(
        authorNoteUnit.insertionMode,
        ExecutionInsertionMode.beforeHistory,
      );
    });

    test(
      'projects persona topAN and bottomAN into author note adjacency units',
      () {
        final request = _buildRequest();

        final topPlan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            persona: Persona(
              id: 'persona_top',
              name: 'Top Persona',
              description: 'top',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.topAN,
              ),
            ),
          ),
        );
        final bottomPlan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            persona: Persona(
              id: 'persona_bottom',
              name: 'Bottom Persona',
              description: 'bottom',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.bottomAN,
              ),
            ),
          ),
        );

        final topUnit = topPlan.shellSequence.firstWhere(
          (unit) => unit.sourceKind == ExecutionSourceKind.persona,
        );
        final bottomUnit = bottomPlan.shellSequence.firstWhere(
          (unit) => unit.sourceKind == ExecutionSourceKind.persona,
        );
        expect(topUnit.insertionMode, ExecutionInsertionMode.authorNoteTop);
        expect(topUnit.anchorId, 'authorNote');
        expect(
          bottomUnit.insertionMode,
          ExecutionInsertionMode.authorNoteBottom,
        );
        expect(bottomUnit.anchorId, 'authorNote');
      },
    );

    test(
      'adds a synthetic author note anchor when AN-adjacent persona needs it',
      () {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_without_author_note_slot',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system',
              promptProfileId: 'profile_without_author_note_slot',
              kind: LegacyPromptBlockKind.systemPrompt,
              name: 'System',
              content: 'SYS',
              role: 'system',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_without_author_note_slot',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final plan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            persona: Persona(
              id: 'persona_top',
              name: 'Top Persona',
              description: 'top',
              descriptionSettings: const PersonaDescriptionSettings(
                position: PersonaDescriptionPosition.topAN,
              ),
            ),
          ),
        );

        expect(
          plan.shellSequence.any(
            (unit) =>
                unit.id == 'synthetic_author_note_marker' &&
                unit.markerId == 'authorNote',
          ),
          isTrue,
        );
        expect(
          plan.shellSequence.any(
            (unit) =>
                unit.sourceKind == ExecutionSourceKind.persona &&
                unit.anchorId == 'authorNote' &&
                unit.insertionMode == ExecutionInsertionMode.authorNoteTop,
          ),
          isTrue,
        );
      },
    );

    test('records applied and blocked persona overrides in execution plan', () {
      final request = _buildRequest();
      final character = _buildCharacter().copyWith(
        systemPrompt: 'BASE',
        postHistoryInstructions: 'POST_BASE',
      );
      final promptProfile = PromptProfileResource(
        id: 'profile_override',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'system',
            promptProfileId: 'profile_override',
            kind: LegacyPromptBlockKind.systemPrompt,
            name: 'System',
            content: 'BASE',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'post',
            promptProfileId: 'profile_override',
            kind: LegacyPromptBlockKind.postHistoryInstructions,
            name: 'Post',
            content: 'POST_BASE',
            role: 'system',
            protectionPolicy: LegacyPromptBlockProtectionPolicy(
              forbidOverride: true,
            ),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_override',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );
      final persona = Persona(
        id: 'persona_1',
        name: 'User',
        description: 'desc',
        systemPromptOverride: 'OVERRIDE',
        postHistoryInstructions: 'POST_OVERRIDE',
      );

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: character,
          promptContext: request.promptContext,
          promptProfile: promptProfile,
          persona: persona,
        ),
      );

      final systemUnit = plan.shellSequence.firstWhere(
        (unit) => unit.id == 'system',
      );
      final postUnit = plan.shellSequence.firstWhere(
        (unit) => unit.id == 'post',
      );
      expect(systemUnit.contentTemplate, 'OVERRIDE');
      expect(postUnit.contentTemplate, 'POST_BASE');
      final overrideTrace = plan.trace
          .where((entry) => entry.stage == ExecutionTraceStage.override)
          .toList(growable: false);
      expect(
        overrideTrace
            .where((entry) => entry.reason == 'persona_system_prompt_override')
            .map((entry) => entry.unitId)
            .toList(growable: false),
        <String>['persona:persona_1:systemPromptOverride'],
      );
      expect(
        overrideTrace
            .where((entry) => entry.reason == 'locked_or_forbid_override')
            .map((entry) => entry.unitId)
            .toList(growable: false),
        <String>['persona:persona_1:postHistoryInstructions'],
      );
      expect(
        overrideTrace.map((entry) => entry.reason).toList(growable: false),
        containsAll(<String>[
          'persona_system_prompt_override',
          'locked_or_forbid_override',
        ]),
      );
    });

    test('applies session disable overlay to prompt units', () {
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
            content: 'BASE',
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

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(
        plan.shellSequence.map((unit) => unit.id),
        isNot(contains('system')),
      );
      final disabled = plan.disabledUnits.firstWhere(
        (unit) => unit.id == 'system',
      );
      expect(disabled.disableSource, ExecutionDisableSource.sessionOverlay);
      expect(disabled.disableReason, 'session_disable_overlay');
    });

    test('applies character disable overlay to prompt units', () {
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
            content: 'POST',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
        ),
      );

      expect(
        plan.shellSequence.map((unit) => unit.id),
        isNot(contains('post')),
      );
      final disabled = plan.disabledUnits.firstWhere(
        (unit) => unit.id == 'post',
      );
      expect(disabled.disableSource, ExecutionDisableSource.characterOverlay);
      expect(disabled.disableReason, 'character_disable_overlay');
    });

    test('keeps basic shell plan parity for default prompt blocks', () {
      final request = _buildRequest();
      final character = _buildCharacter().copyWith(
        systemPrompt: 'SYS',
        description: 'DESC',
        personality: 'PERS',
        scenario: 'SCENE',
        postHistoryInstructions: 'POST',
      );

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: character,
          promptContext: request.promptContext,
        ),
      );

      expect(
        plan.shellSequence
            .where((unit) => unit.sourceKind != ExecutionSourceKind.marker)
            .map((unit) => unit.markerId ?? unit.id)
            .toList(growable: false),
        <String>[
          'systemPrompt',
          'persona',
          'characterDescription',
          'characterPersonality',
          'characterScenario',
          'exampleMessages',
          'worldInfo',
          'authorNote',
          'worldInfoAfter',
          'postHistoryInstructions',
        ],
      );
    });

    test(
      'maps world info positions to distinct anchors instead of collapsing them',
      () {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_wi_slots',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'system_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'System Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'systemPrompt',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'example_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'Example Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'exampleMessages',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'world_info_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'World Info Marker',
              provenance: LegacyPromptBlockProvenance(identifier: 'worldInfo'),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
            LegacyPromptBlock(
              id: 'custom_world_info_outlet_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'Custom World Info Outlet Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'customWorldInfoOutlet',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 4),
            ),
            LegacyPromptBlock(
              id: 'world_info_after_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'World Info After Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'worldInfoAfter',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 5),
            ),
            LegacyPromptBlock(
              id: 'author_marker',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.marker,
              name: 'Author Marker',
              provenance: LegacyPromptBlockProvenance(identifier: 'authorNote'),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 6),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_wi_slots',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 7),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );
        final resolvedContext = ResolvedPromptContext(
          character: _buildCharacter(),
          worldInfoEntries: <WorldInfoEntry>[
            _worldInfoEntry(
              id: 'before',
              content: 'BEFORE',
              insertionOrder: 1,
              position: WorldInfoPosition.before,
            ),
            _worldInfoEntry(
              id: 'after',
              content: 'AFTER',
              insertionOrder: 2,
              position: WorldInfoPosition.after,
            ),
            _worldInfoEntry(
              id: 'em_top',
              content: 'EM_TOP',
              insertionOrder: 3,
              position: WorldInfoPosition.emTop,
            ),
            _worldInfoEntry(
              id: 'em_bottom',
              content: 'EM_BOTTOM',
              insertionOrder: 4,
              position: WorldInfoPosition.emBottom,
            ),
            _worldInfoEntry(
              id: 'outlet',
              content: 'OUTLET',
              insertionOrder: 5,
              position: WorldInfoPosition.outlet,
              outletName: 'customWorldInfoOutlet',
            ),
          ],
          groupedWorldInfoEntries:
              const <WorldInfoPosition, List<WorldInfoEntry>>{},
          resolvedPromptBlocks: promptBlocksFromLegacy(
            promptProfile.resolvedBlocks,
          ),
          promptContext: request.promptContext,
          resolvedVariables: const <String, dynamic>{},
        );

        final plan = _plan(request: request, resolvedContext: resolvedContext);

        ResolvedExecutionUnit wi(String id) =>
            plan.shellSequence.firstWhere((unit) => unit.id == 'wi:wb_1:$id');

        expect(wi('before').anchorId, 'systemPrompt');
        expect(
          wi('before').insertionMode,
          ExecutionInsertionMode.relativeBefore,
        );
        expect(wi('after').anchorId, 'worldInfoAfter');
        expect(wi('after').insertionMode, ExecutionInsertionMode.relativeAfter);
        expect(wi('em_top').anchorId, 'exampleMessages');
        expect(
          wi('em_top').insertionMode,
          ExecutionInsertionMode.relativeBefore,
        );
        expect(wi('em_bottom').anchorId, 'exampleMessages');
        expect(
          wi('em_bottom').insertionMode,
          ExecutionInsertionMode.relativeAfter,
        );
        expect(
          plan.outletMap['customWorldInfoOutlet']?.single.id,
          'wi:wb_1:outlet',
        );
      },
    );

    test('orders same-anchor world info shell units by insertionOrder', () {
      final request = _buildRequest();
      final promptProfile = PromptProfileResource(
        id: 'profile_wi_order',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'system_marker',
            promptProfileId: 'profile_wi_order',
            kind: LegacyPromptBlockKind.marker,
            name: 'System Marker',
            provenance: LegacyPromptBlockProvenance(identifier: 'systemPrompt'),
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_wi_order',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final plan = _plan(
        request: request,
        resolvedContext: ResolvedPromptContext(
          character: _buildCharacter(),
          worldInfoEntries: <WorldInfoEntry>[
            _worldInfoEntry(
              id: 'late',
              content: 'LATE',
              insertionOrder: 2,
              position: WorldInfoPosition.before,
            ),
            _worldInfoEntry(
              id: 'early',
              content: 'EARLY',
              insertionOrder: 1,
              position: WorldInfoPosition.before,
            ),
          ],
          groupedWorldInfoEntries:
              const <WorldInfoPosition, List<WorldInfoEntry>>{},
          resolvedPromptBlocks: promptBlocksFromLegacy(
            promptProfile.resolvedBlocks,
          ),
          promptContext: request.promptContext,
          resolvedVariables: const <String, dynamic>{},
        ),
      );

      final beforeSystem = plan.shellSequence
          .where(
            (unit) =>
                unit.sourceKind == ExecutionSourceKind.worldInfoEntry &&
                unit.anchorId == 'systemPrompt',
          )
          .map((unit) => unit.id)
          .toList(growable: false);
      expect(beforeSystem, <String>['wi:wb_1:early', 'wi:wb_1:late']);
    });

    test(
      'prefers runtime outlet over entry outletName for world info outlet anchor',
      () {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_wi_runtime_outlet',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'runtime_outlet_marker',
              promptProfileId: 'profile_wi_runtime_outlet',
              kind: LegacyPromptBlockKind.marker,
              name: 'Runtime Outlet Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'runtimeOutlet',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'world_info_marker',
              promptProfileId: 'profile_wi_runtime_outlet',
              kind: LegacyPromptBlockKind.marker,
              name: 'World Info Marker',
              provenance: LegacyPromptBlockProvenance(identifier: 'worldInfo'),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_wi_runtime_outlet',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 3),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final plan = _plan(
          request: request,
          resolvedContext: ResolvedPromptContext(
            character: _buildCharacter(),
            worldInfoEntries: <WorldInfoEntry>[
              _worldInfoEntry(
                id: 'outlet',
                content: 'OUTLET',
                insertionOrder: 1,
                position: WorldInfoPosition.outlet,
                outletName: 'entryOutlet',
                runtimePolicy: const WorldInfoRuntimePolicy(
                  output: WorldInfoOutputPolicy(outlet: 'runtimeOutlet'),
                ),
              ),
            ],
            groupedWorldInfoEntries:
                const <WorldInfoPosition, List<WorldInfoEntry>>{},
            resolvedPromptBlocks: promptBlocksFromLegacy(
              promptProfile.resolvedBlocks,
            ),
            promptContext: request.promptContext,
            resolvedVariables: const <String, dynamic>{},
          ),
        );

        final outletUnit = plan.outletMap['runtimeOutlet']!.single;
        expect(outletUnit.anchorId, 'runtimeOutlet');
        expect(outletUnit.insertionMode, ExecutionInsertionMode.outlet);
      },
    );

    test(
      'groups outlet units by named outlet and orders them by injectionOrder',
      () {
        final request = _buildRequest();
        final promptProfile = PromptProfileResource(
          id: 'profile_outlet_order',
          name: 'Profile',
          config: const PromptManagerConfig(sections: <PromptSection>[]),
          blocks: const <LegacyPromptBlock>[
            LegacyPromptBlock(
              id: 'custom_outlet_marker',
              promptProfileId: 'profile_outlet_order',
              kind: LegacyPromptBlockKind.marker,
              name: 'Custom Outlet Marker',
              provenance: LegacyPromptBlockProvenance(
                identifier: 'customOutlet',
              ),
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
            ),
            LegacyPromptBlock(
              id: 'history',
              promptProfileId: 'profile_outlet_order',
              kind: LegacyPromptBlockKind.chatHistory,
              name: 'History',
              priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
            ),
          ],
          createdAt: DateTime.utc(2026, 3, 23),
          updatedAt: DateTime.utc(2026, 3, 23),
        );

        final plan = _plan(
          request: request,
          resolvedContext: _buildResolvedContext(
            character: _buildCharacter(),
            promptContext: request.promptContext,
            promptProfile: promptProfile,
            worldInfoEntries: <WorldInfoEntry>[
              _worldInfoEntry(
                id: 'late',
                content: 'LATE',
                insertionOrder: 5,
                position: WorldInfoPosition.outlet,
                outletName: 'customOutlet',
              ),
              _worldInfoEntry(
                id: 'early',
                content: 'EARLY',
                insertionOrder: 1,
                position: WorldInfoPosition.outlet,
                outletName: 'customOutlet',
              ),
            ],
          ),
        );

        expect(
          plan.outletMap['customOutlet']
              ?.map((unit) => unit.id)
              .toList(growable: false),
          <String>['wi:wb_1:early', 'wi:wb_1:late'],
        );
      },
    );

    test('disables outlet units when the outlet anchor is missing', () {
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

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
          worldInfoEntries: <WorldInfoEntry>[
            _worldInfoEntry(
              id: 'missing_outlet',
              content: 'MISSING',
              insertionOrder: 1,
              position: WorldInfoPosition.outlet,
              outletName: 'doesNotExist',
            ),
          ],
        ),
      );

      expect(plan.outletMap.containsKey('doesNotExist'), isFalse);
      expect(
        plan.disabledUnits.any(
          (unit) =>
              unit.id == 'wi:wb_1:missing_outlet' &&
              unit.disableSource == ExecutionDisableSource.missingAnchor &&
              unit.disableReason == 'missing_outlet_anchor',
        ),
        isTrue,
      );
      expect(
        plan.trace.any(
          (trace) =>
              trace.unitId == 'wi:wb_1:missing_outlet' &&
              trace.stage == ExecutionTraceStage.filtering &&
              trace.reason == 'missing_outlet_anchor',
        ),
        isTrue,
      );
      expect(
        plan.trace.any(
          (trace) =>
              trace.unitId == 'wi:wb_1:missing_outlet' &&
              trace.reason == 'outlet_routed',
        ),
        isFalse,
      );
    });

    test('accepts outlet anchors provided by scaffold shell units', () {
      final request = _buildRequest();
      final promptProfile = PromptProfileResource(
        id: 'profile_scaffold_outlet_anchor',
        name: 'Profile',
        config: const PromptManagerConfig(sections: <PromptSection>[]),
        blocks: const <LegacyPromptBlock>[
          LegacyPromptBlock(
            id: 'world_info_slot',
            promptProfileId: 'profile_scaffold_outlet_anchor',
            kind: LegacyPromptBlockKind.worldInfo,
            name: 'World Info Slot',
            role: 'system',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 1),
          ),
          LegacyPromptBlock(
            id: 'history',
            promptProfileId: 'profile_scaffold_outlet_anchor',
            kind: LegacyPromptBlockKind.chatHistory,
            name: 'History',
            priorityPolicy: LegacyPromptBlockPriorityPolicy(sortOrder: 2),
          ),
        ],
        createdAt: DateTime.utc(2026, 3, 23),
        updatedAt: DateTime.utc(2026, 3, 23),
      );

      final plan = _plan(
        request: request,
        resolvedContext: _buildResolvedContext(
          character: _buildCharacter(),
          promptContext: request.promptContext,
          promptProfile: promptProfile,
          worldInfoEntries: <WorldInfoEntry>[
            _worldInfoEntry(
              id: 'scaffold_outlet',
              content: 'OUTLET',
              insertionOrder: 1,
              position: WorldInfoPosition.outlet,
              outletName: 'worldInfo',
            ),
          ],
        ),
      );

      expect(
        plan.outletMap['worldInfo']
            ?.map((unit) => unit.id)
            .toList(growable: false),
        <String>['wi:wb_1:scaffold_outlet'],
      );
      expect(
        plan.disabledUnits.any((unit) => unit.id == 'wi:wb_1:scaffold_outlet'),
        isFalse,
      );
    });
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

PromptExecutionPlan _plan({
  required PromptScenarioInput request,
  required ResolvedPromptContext resolvedContext,
  String generationType = 'chat',
}) => const PromptExecutionPlanner().buildDomainPlan(
  DomainPromptPlanningInput(
    character: resolvedContext.character,
    persona: resolvedContext.persona,
    promptBlocks: resolvedContext.resolvedPromptBlocks,
    worldInfoEntries: resolvedContext.worldInfoEntries,
    promptContext: request.promptContext,
    historyLength: request.history.length,
    generationType: generationType,
    sessionDisableOverlay: request.sessionDisableOverlay,
    characterDisableOverlay: request.characterDisableOverlay,
  ),
);

PromptScenarioInput _buildRequest({
  SessionPromptContext? promptContext,
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
        timestamp: DateTime.utc(2026, 3, 23),
      ),
    ],
    pendingUserInput: const PromptScenarioUserInput(text: 'hello'),
    promptContext: promptContext ?? const SessionPromptContext(),
    sessionDisableOverlay: sessionDisableOverlay,
    characterDisableOverlay: characterDisableOverlay,
  );
}

Character _buildCharacter() {
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
    systemPrompt: '',
    postHistoryInstructions: '',
    tags: const <String>[],
    isSystem: false,
    visibilityScope: 'private',
    createdAt: DateTime.utc(2026, 3, 23),
    updatedAt: DateTime.utc(2026, 3, 23),
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

WorldInfoEntry _worldInfoEntry({
  required String id,
  required String content,
  required int insertionOrder,
  required WorldInfoPosition position,
  int depth = 0,
  int role = 0,
  String? outletName,
  WorldInfoRuntimePolicy? runtimePolicy,
}) {
  return WorldInfoEntry(
    id: id,
    worldbookId: 'wb_1',
    keys: const <String>['key'],
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
    depth: depth,
    group: null,
    groupWeight: 100,
    preventRecursion: false,
    delayUntilRecursion: false,
    scanDepth: 0,
    role: role,
    sticky: 0,
    cooldown: 0,
    delay: 0,
    characterFilter: const <String, dynamic>{},
    outletName: outletName,
    runtimePolicy: runtimePolicy,
  );
}
