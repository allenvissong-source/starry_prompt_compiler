// SPDX-License-Identifier: BSD-3-Clause
//
// Ports-ified subset of `lib/features/prompt_lab/domain/services/regex_service.dart`.
//
// Behavioral parity for the copied methods is enforced by the characterization
// test `test/features/prompt_compiler/regex_service_characterization_test.dart`
// scheduled to run under both `SUT=starry` and `SUT=package`.
//
// Deliberate deltas versus the source of truth:
//
//   * `import 'package:flutter/foundation.dart';` → dropped in favor of a
//     [Logger] port. The two `debugPrint(...)` call sites become
//     `_logger.warn(...)`.
//   * Singleton (`RegexService._()` + `static final instance = ...`) is
//     removed. The pure package exposes a normal constructor so callers can
//     inject a [Logger] and so tests do not have to share state through a
//     global. The Starry-side singleton stays (the host wires it to a
//     process-scoped instance).
//   * Explicitly **not copied** (Host / UI concerns, and the only remaining
//     `DateTime.now()` call sites in the source):
//       - `testRegex(...)` / `RegexTestResult` / `RegexMatch` — used only by
//         `regex_test_widget.dart` (a Flutter preview widget).
//       - `RegexPresets` (and its five factory methods) — used only by
//         `regex_script_state.dart` (a Riverpod state class in the prompt-lab
//         UI). The presets embed `DateTime.now()` seed timestamps, which is
//         non-deterministic and irrelevant to the compiler pipeline.
//
// Everything else — cache eviction policy, /pattern/flags parsing, group /
// named-group substitution, `{{match}}` handling, placement filtering,
// markdown/prompt/edit gating, depth constraints, and the `_escapeRegex`
// character table — is byte-identical to the Starry-side source.

import '../models/regex_script.dart';
import '../ports/logger.dart';

/// Service for managing and executing regex scripts.
/// Based on SillyTavern's regex extension engine.
class RegexService {
  RegexService({Logger logger = const NoopLogger()}) : _logger = logger;

  final Logger _logger;

  /// LRU cache for compiled regex patterns
  final Map<String, RegExp> _regexCache = {};
  static const int _maxCacheSize = 1000;

  /// Get or compile a regex from string.
  /// Returns null if the regex is invalid.
  RegExp? getRegex(String regexString) {
    // Check cache first
    if (_regexCache.containsKey(regexString)) {
      // LRU: Move to end by re-inserting
      final regex = _regexCache.remove(regexString)!;
      _regexCache[regexString] = regex;
      return regex;
    }

    // Try to compile the regex
    try {
      final regex = _parseRegexString(regexString);
      if (regex == null) return null;

      // Evict oldest if at capacity
      if (_regexCache.length >= _maxCacheSize) {
        _regexCache.remove(_regexCache.keys.first);
      }

      _regexCache[regexString] = regex;
      return regex;
    } on Object catch (e) {
      _logger.warn('RegexService: Failed to compile regex "$regexString": $e');
      return null;
    }
  }

  /// Parse a regex string in /pattern/flags format
  RegExp? _parseRegexString(String regexString) {
    // Handle /pattern/flags format
    if (regexString.startsWith('/')) {
      final lastSlash = regexString.lastIndexOf('/');
      if (lastSlash > 0) {
        final pattern = regexString.substring(1, lastSlash);
        final flags = regexString.substring(lastSlash + 1);

        final bool caseSensitive = !flags.contains('i');
        final bool multiLine = flags.contains('m');
        final bool dotAll = flags.contains('s');
        final bool unicode = flags.contains('u');

        return RegExp(
          pattern,
          caseSensitive: caseSensitive,
          multiLine: multiLine,
          dotAll: dotAll,
          unicode: unicode,
        );
      }
    }

    // Plain pattern without delimiters
    return RegExp(regexString);
  }

  /// Drops all compiled-pattern entries from the internal LRU cache.
  ///
  /// Retained as a public cache-invalidation seam even though no caller in the
  /// seven current workspaces invokes it (verified across `starry_prompt_
  /// compiler`, `starry_domain_entities`, `starry_character_card_codec`,
  /// `starry_injection_service`, and the host `starry`): the host wires this
  /// service as a process-scoped singleton (`regexServiceProvider`), the cache
  /// is private and self-evicting at 1000 entries, and cache keys are the full
  /// source string so editing a script cannot leave a stale entry behind.
  /// There is therefore no *correctness* bug this fixes today. It is kept
  /// because it is the only public way to invalidate that internal cache, and
  /// deleting it would narrow an injectable service's contract for no behavior
  /// gain. Re-evaluate if a host ever needs post-edit cache busting.
  void clearCache() {
    _regexCache.clear();
  }

  /// Apply a single regex script to a string
  String runRegexScript(
    RegexScript script,
    String input, {
    String? characterName,
    String? userName,
  }) {
    if (script.disabled || script.findRegex.isEmpty || input.isEmpty) {
      return input;
    }

    // Get the find regex, optionally with macro substitution
    String regexString = script.findRegex;
    if (script.substituteRegex == SubstituteRegex.raw) {
      regexString = _substituteMacros(regexString, characterName, userName);
    } else if (script.substituteRegex == SubstituteRegex.escaped) {
      regexString = _substituteMacrosEscaped(
        regexString,
        characterName,
        userName,
      );
    }

    final regex = getRegex(regexString);
    if (regex == null) {
      return input;
    }

    // Perform the replacement
    try {
      return input.replaceAllMapped(regex, (match) {
        String replacement = script.replaceString;

        // Replace {{match}} with $0
        replacement = replacement.replaceAll(
          RegExp(r'\{\{match\}\}', caseSensitive: false),
          match.group(0) ?? '',
        );

        // Replace numbered capture groups ($1, $2, etc.)
        for (int i = 0; i <= match.groupCount; i++) {
          final group = match.group(i) ?? '';
          final filteredGroup = _filterString(group, script.trimStrings);
          replacement = replacement.replaceAll('\$$i', filteredGroup);
        }

        // Replace named capture groups ($<name>)
        // Note: Named groups require RegExpMatch, which is available when using RegExp
        final namedGroupPattern = RegExp(r'\$<([^>]+)>');
        replacement = replacement.replaceAllMapped(namedGroupPattern, (m) {
          final groupName = m.group(1);
          if (groupName != null && match is RegExpMatch) {
            try {
              final groupValue = match.namedGroup(groupName) ?? '';
              return _filterString(groupValue, script.trimStrings);
            } on Object {
              return '';
            }
          }
          return '';
        });

        // Substitute macros in the replacement
        replacement = _substituteMacros(replacement, characterName, userName);

        return replacement;
      });
    } on Object catch (e) {
      _logger.warn(
        'RegexService: Error running script "${script.scriptName}": $e',
      );
      return input;
    }
  }

  /// Apply all applicable regex scripts to a string
  String getRegexedString(
    String input,
    RegexPlacement placement,
    List<RegexScript> scripts, {
    String? characterName,
    String? userName,
    bool isMarkdown = false,
    bool isPrompt = false,
    bool isEdit = false,
    int? depth,
  }) {
    if (input.isEmpty) return input;

    String result = input;

    // Sort scripts by order
    final sortedScripts = List<RegexScript>.from(scripts)
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final script in sortedScripts) {
      // Skip disabled scripts
      if (script.disabled) continue;

      // Check placement
      if (!script.placement.contains(placement)) continue;

      // Check markdown/prompt only flags
      if (script.markdownOnly && !isMarkdown) continue;
      if (script.promptOnly && !isPrompt) continue;
      if (!script.markdownOnly &&
          !script.promptOnly &&
          (isMarkdown || isPrompt)) {
        continue;
      }

      // Check edit flag
      if (isEdit && !script.runOnEdit) continue;

      // Check depth constraints
      if (depth != null) {
        if (script.minDepth != null &&
            script.minDepth! >= -1 &&
            depth < script.minDepth!) {
          continue;
        }
        if (script.maxDepth != null &&
            script.maxDepth! >= 0 &&
            depth > script.maxDepth!) {
          continue;
        }
      }

      // Run the script
      result = runRegexScript(
        script,
        result,
        characterName: characterName,
        userName: userName,
      );
    }

    return result;
  }

  /// Filter a string by removing trim strings
  String _filterString(String input, List<String> trimStrings) {
    if (trimStrings.isEmpty) return input;

    String result = input;
    for (final trim in trimStrings) {
      result = result.replaceAll(trim, '');
    }
    return result;
  }

  /// Substitute macros in a string (raw)
  String _substituteMacros(
    String input,
    String? characterName,
    String? userName,
  ) {
    String result = input;

    if (characterName != null) {
      result = result.replaceAll(
        RegExp(r'\{\{char\}\}', caseSensitive: false),
        characterName,
      );
    }
    if (userName != null) {
      result = result.replaceAll(
        RegExp(r'\{\{user\}\}', caseSensitive: false),
        userName,
      );
    }

    return result;
  }

  /// Substitute macros in a string with regex escaping
  String _substituteMacrosEscaped(
    String input,
    String? characterName,
    String? userName,
  ) {
    String result = input;

    if (characterName != null) {
      result = result.replaceAll(
        RegExp(r'\{\{char\}\}', caseSensitive: false),
        _escapeRegex(characterName),
      );
    }
    if (userName != null) {
      result = result.replaceAll(
        RegExp(r'\{\{user\}\}', caseSensitive: false),
        _escapeRegex(userName),
      );
    }

    return result;
  }

  /// Escape special regex characters in a string
  String _escapeRegex(String input) {
    return input.replaceAllMapped(RegExp(r'[\n\r\t\v\f\0.^$*+?{}\[\]\\/|()]'), (
      match,
    ) {
      final char = match.group(0)!;
      switch (char) {
        case '\n':
          return r'\n';
        case '\r':
          return r'\r';
        case '\t':
          return r'\t';
        case '\v':
          return r'\v';
        case '\f':
          return r'\f';
        case '\x00':
          return r'\0';
        default:
          return '\\$char';
      }
    });
  }
}
