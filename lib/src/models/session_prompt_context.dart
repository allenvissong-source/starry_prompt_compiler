// Only cross-file dep is prompt_execution_models (PromptDisableOverlay);
// rewritten to a package-relative import.

import 'prompt_execution_models.dart';

class AuthorNotePolicy {
  const AuthorNotePolicy({
    this.enabled = false,
    this.text = '',
    this.role = 'system',
    this.placement = 'at_depth',
    this.depth = 4,
    this.interval = 1,
    this.allowWorldbookScan = false,
  });

  factory AuthorNotePolicy.fromJson(Map<String, dynamic> json) {
    return AuthorNotePolicy(
      enabled: json['enabled'] == true,
      text: (json['text'] ?? '').toString(),
      role: _normalizedString(json['role'], fallback: 'system'),
      placement: _normalizedString(json['placement'], fallback: 'at_depth'),
      depth: _asInt(json['depth'], fallback: 4),
      interval: _asInt(json['interval'], fallback: 1),
      allowWorldbookScan: json['allow_worldbook_scan'] == true,
    );
  }

  final bool enabled;
  final String text;
  final String role;
  final String placement;
  final int depth;
  final int interval;
  final bool allowWorldbookScan;

  bool get hasContent => enabled && text.trim().isNotEmpty;

  AuthorNotePolicy copyWith({
    bool? enabled,
    String? text,
    String? role,
    String? placement,
    int? depth,
    int? interval,
    bool? allowWorldbookScan,
  }) {
    return AuthorNotePolicy(
      enabled: enabled ?? this.enabled,
      text: text ?? this.text,
      role: role ?? this.role,
      placement: placement ?? this.placement,
      depth: depth ?? this.depth,
      interval: interval ?? this.interval,
      allowWorldbookScan: allowWorldbookScan ?? this.allowWorldbookScan,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'text': text,
    'role': role,
    'placement': placement,
    'depth': depth,
    'interval': interval,
    'allow_worldbook_scan': allowWorldbookScan,
  };

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }

  static String _normalizedString(Object? value, {required String fallback}) {
    final normalized = (value ?? '').toString().trim();
    return normalized.isEmpty ? fallback : normalized;
  }
}

class SessionPromptContext {
  const SessionPromptContext({
    this.personaId,
    this.contextProfileId,
    this.regexProfileId,
    this.variableSetId,
    this.authorNotePolicy = const AuthorNotePolicy(),
    this.activeWorldbookIds = const <String>[],
    this.updatedAt,
    this.sessionVariables = const <String, dynamic>{},
    this.sessionDisableOverlay = const PromptDisableOverlay(),
    this.characterDisableOverlay = const PromptDisableOverlay(),
  });

  factory SessionPromptContext.fromJson(Map<String, dynamic> json) {
    final rawIds = json['active_worldbook_ids'];
    final ids = rawIds is List
        ? rawIds
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final rawSessionVariables = json['session_variables'];
    final sessionVariables = rawSessionVariables is Map
        ? Map<String, dynamic>.from(rawSessionVariables)
        : const <String, dynamic>{};
    final updatedAtValue = json['updated_at'];
    final updatedAtSeconds = updatedAtValue is int
        ? updatedAtValue
        : int.tryParse((updatedAtValue ?? '').toString());
    return SessionPromptContext(
      personaId: _normalizedId(json['persona_id']),
      contextProfileId: _normalizedId(json['context_profile_id']),
      regexProfileId: _normalizedId(json['regex_profile_id']),
      variableSetId: _normalizedId(json['variable_set_id']),
      authorNotePolicy: json['author_note_policy'] is Map
          ? AuthorNotePolicy.fromJson(
              Map<String, dynamic>.from(json['author_note_policy'] as Map),
            )
          : const AuthorNotePolicy(),
      activeWorldbookIds: ids,
      // `updated_at` is epoch seconds: an absolute instant. Materialize it as a
      // UTC DateTime so callers comparing/ordering it never see a local-zone
      // representation, and so toJson projects the same instant.
      updatedAt: updatedAtSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              updatedAtSeconds * 1000,
              isUtc: true,
            ),
      sessionVariables: sessionVariables,
      sessionDisableOverlay: _overlayFromJson(json['session_disable_overlay']),
      characterDisableOverlay: _overlayFromJson(
        json['character_disable_overlay'],
      ),
    );
  }
  static const Object _unset = Object();

  final String? personaId;
  final String? contextProfileId;
  final String? regexProfileId;
  final String? variableSetId;
  final AuthorNotePolicy authorNotePolicy;
  final List<String> activeWorldbookIds;
  final DateTime? updatedAt;
  final Map<String, dynamic> sessionVariables;
  final PromptDisableOverlay sessionDisableOverlay;
  final PromptDisableOverlay characterDisableOverlay;

  bool get hasAuthorNote => authorNotePolicy.hasContent;
  String get authorNote => authorNotePolicy.text;
  int get authorNoteDepth => authorNotePolicy.depth;
  bool get authorNoteEnabled => authorNotePolicy.enabled;

  SessionPromptContext copyWith({
    Object? personaId = _unset,
    Object? contextProfileId = _unset,
    Object? regexProfileId = _unset,
    Object? variableSetId = _unset,
    Object? authorNotePolicy = _unset,
    String? authorNote,
    int? authorNoteDepth,
    bool? authorNoteEnabled,
    String? authorNoteRole,
    String? authorNotePlacement,
    int? authorNoteInterval,
    bool? allowWorldbookScan,
    List<String>? activeWorldbookIds,
    DateTime? updatedAt,
    Map<String, dynamic>? sessionVariables,
    PromptDisableOverlay? sessionDisableOverlay,
    PromptDisableOverlay? characterDisableOverlay,
  }) {
    final nextAuthorNotePolicy = identical(authorNotePolicy, _unset)
        ? this.authorNotePolicy.copyWith(
            text: authorNote,
            depth: authorNoteDepth,
            enabled: authorNoteEnabled,
            role: authorNoteRole,
            placement: authorNotePlacement,
            interval: authorNoteInterval,
            allowWorldbookScan: allowWorldbookScan,
          )
        : authorNotePolicy as AuthorNotePolicy;
    return SessionPromptContext(
      personaId: identical(personaId, _unset)
          ? this.personaId
          : personaId as String?,
      contextProfileId: identical(contextProfileId, _unset)
          ? this.contextProfileId
          : contextProfileId as String?,
      regexProfileId: identical(regexProfileId, _unset)
          ? this.regexProfileId
          : regexProfileId as String?,
      variableSetId: identical(variableSetId, _unset)
          ? this.variableSetId
          : variableSetId as String?,
      authorNotePolicy: nextAuthorNotePolicy,
      activeWorldbookIds: activeWorldbookIds ?? this.activeWorldbookIds,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionVariables: sessionVariables ?? this.sessionVariables,
      sessionDisableOverlay:
          sessionDisableOverlay ?? this.sessionDisableOverlay,
      characterDisableOverlay:
          characterDisableOverlay ?? this.characterDisableOverlay,
    );
  }

  Map<String, dynamic> toJson() => {
    if (personaId != null) 'persona_id': personaId,
    if (contextProfileId != null) 'context_profile_id': contextProfileId,
    if (regexProfileId != null) 'regex_profile_id': regexProfileId,
    if (variableSetId != null) 'variable_set_id': variableSetId,
    'active_worldbook_ids': activeWorldbookIds,
    'author_note_policy': authorNotePolicy.toJson(),
    'session_disable_overlay': _overlayToJson(sessionDisableOverlay),
    'character_disable_overlay': _overlayToJson(characterDisableOverlay),
    if (sessionVariables.isNotEmpty) 'session_variables': sessionVariables,
    if (updatedAt != null)
      'updated_at': updatedAt!.toUtc().millisecondsSinceEpoch ~/ 1000,
  };

  static Map<String, dynamic> _map(dynamic raw) {
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  static String? _normalizedId(Object? value) {
    final normalized = (value ?? '').toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static Map<String, dynamic> _overlayToJson(PromptDisableOverlay overlay) => {
    'disabled_unit_ids': overlay.disabledUnitIds,
    'disabled_source_refs': overlay.disabledSourceRefs,
  };

  static PromptDisableOverlay _overlayFromJson(dynamic raw) {
    final map = _map(raw);
    final unitIds = map['disabled_unit_ids'] is List
        ? (map['disabled_unit_ids'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final sourceRefs = map['disabled_source_refs'] is List
        ? (map['disabled_source_refs'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return PromptDisableOverlay(
      disabledUnitIds: unitIds,
      disabledSourceRefs: sourceRefs,
    );
  }
}
