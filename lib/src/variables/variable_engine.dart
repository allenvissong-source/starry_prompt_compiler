import 'dart:convert';

import '../ports/logger.dart';
import '../ports/variable_store.dart';

/// Pure runtime engine for variable operations and macro expansion.
///
/// Ported verbatim from the host `VariablesService` — persistence, singleton
/// state and `SharedPreferences` have been extracted into [VariableStore] so
/// this class can live inside the pure-Dart package.
///
/// Behavior parity: kept identical to host implementation. Every kind of
/// coercion / indexed access / error swallow reflects the original
/// characterization tests (SUT=starry baseline).
class VariableEngine {
  VariableEngine({
    required VariableStore store,
    Logger logger = const NoopLogger(),
  }) : _store = store,
       _logger = logger;

  final VariableStore _store;
  // Diagnostic exit for degraded paths (array-add that falls back to
  // number/concat when the stored value is not a JSON list). Defaults to
  // [NoopLogger]; hosts inject whatever sink they want, and
  // `test/degradation_diagnostics_test.dart` pins the behavior with a
  // capturing `CallbackLogger`.
  final Logger _logger;

  // ==================== Resolution ====================

  /// Resolve a variable name to its value. Prefers local (per-chat) over
  /// global. Returns the name itself when not found, mirroring host behavior.
  dynamic resolveVariable(String name, {String? chatId}) {
    if (chatId != null && _store.existsLocal(chatId, name)) {
      return _store.getLocal(chatId, name);
    }
    if (_store.existsGlobal(name)) {
      return _store.getGlobal(name);
    }
    return name;
  }

  // ==================== Add (arithmetic + concat) ====================

  /// Add-or-concat semantics for global variables. Returns the resulting
  /// value. Mirrors `VariablesService.addGlobalVariable`.
  dynamic addGlobal(String name, dynamic value) {
    final currentValue = _store.getGlobal(name);

    // Try to handle as array
    try {
      final parsed = currentValue is String
          ? jsonDecode(currentValue)
          : currentValue;
      if (parsed is List) {
        parsed.add(value);
        _store.setGlobal(name, jsonEncode(parsed));
        return parsed;
      }
    } on Object catch (e) {
      // Not an array: the stored value is not JSON-decodable as a list, so the
      // add falls through to the number/concat path below. Surface the decode
      // failure through the injected logger instead of swallowing it silently;
      // the fallback result below is unchanged.
      _logger.warn(
        'VariableEngine: global "$name" is not a JSON list; '
        'add falls back to number/concat: $e',
      );
    }

    // Try to handle as number
    final increment = value is num ? value : double.tryParse(value.toString());
    final current = currentValue is num
        ? currentValue
        : double.tryParse(currentValue.toString());

    if (increment != null && current != null) {
      final newValue = current + increment;
      _store.setGlobal(name, newValue);
      return newValue;
    }

    final stringValue = '${currentValue ?? ''}$value';
    _store.setGlobal(name, stringValue);
    return stringValue;
  }

  dynamic incrementGlobal(String name) => addGlobal(name, 1);
  dynamic decrementGlobal(String name) => addGlobal(name, -1);

  /// Add-or-concat semantics for local (per-chat) variables.
  dynamic addLocal(String chatId, String name, dynamic value) {
    final currentValue = _store.getLocal(chatId, name);

    try {
      final parsed = currentValue is String
          ? jsonDecode(currentValue)
          : currentValue;
      if (parsed is List) {
        parsed.add(value);
        _store.setLocal(chatId, name, jsonEncode(parsed));
        return parsed;
      }
    } on Object catch (e) {
      // Not an array: see the global path. The fallback result below is
      // unchanged; this only opens an observable, injectable diagnostic exit.
      _logger.warn(
        'VariableEngine: local "$name" is not a JSON list; '
        'add falls back to number/concat: $e',
      );
    }

    final increment = value is num ? value : double.tryParse(value.toString());
    final current = currentValue is num
        ? currentValue
        : double.tryParse(currentValue.toString());

    if (increment != null && current != null) {
      final newValue = current + increment;
      _store.setLocal(chatId, name, newValue);
      return newValue;
    }

    final stringValue = '${currentValue ?? ''}$value';
    _store.setLocal(chatId, name, stringValue);
    return stringValue;
  }

  dynamic incrementLocal(String chatId, String name) =>
      addLocal(chatId, name, 1);
  dynamic decrementLocal(String chatId, String name) =>
      addLocal(chatId, name, -1);

  // ==================== Macro processing ====================

  /// Process variable macros in a string. Supported forms:
  ///
  /// - `{{setvar::name::value}}`
  /// - `{{addvar::name::value}}`
  /// - `{{incvar::name}}`
  /// - `{{decvar::name}}`
  /// - `{{getvar::name}}`
  /// - `{{setglobalvar::name::value}}`
  /// - `{{addglobalvar::name::value}}`
  /// - `{{incglobalvar::name}}`
  /// - `{{decglobalvar::name}}`
  /// - `{{getglobalvar::name}}`
  ///
  /// Local macros require `chatId`; when absent, local macros expand to `''`
  /// (matches host behavior).
  String processVariableMacros(String input, {String? chatId}) {
    String result = input;

    // {{setvar::name::value}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{setvar::([^:]+)::([^}]*)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        final value = match.group(2)!;
        if (chatId != null) {
          _store.setLocal(chatId, name, value);
        }
        return '';
      },
    );

    // {{addvar::name::value}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{addvar::([^:]+)::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        final value = match.group(2)!;
        if (chatId != null) {
          addLocal(chatId, name, value);
        }
        return '';
      },
    );

    // {{incvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{incvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        if (chatId != null) {
          return incrementLocal(chatId, name).toString();
        }
        return '';
      },
    );

    // {{decvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{decvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        if (chatId != null) {
          return decrementLocal(chatId, name).toString();
        }
        return '';
      },
    );

    // {{getvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{getvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        if (chatId != null) {
          return _store.getLocal(chatId, name).toString();
        }
        return '';
      },
    );

    // {{setglobalvar::name::value}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{setglobalvar::([^:]+)::([^}]*)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        final value = match.group(2)!;
        _store.setGlobal(name, value);
        return '';
      },
    );

    // {{addglobalvar::name::value}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{addglobalvar::([^:]+)::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        final value = match.group(2)!;
        addGlobal(name, value);
        return '';
      },
    );

    // {{incglobalvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{incglobalvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        return incrementGlobal(name).toString();
      },
    );

    // {{decglobalvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{decglobalvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        return decrementGlobal(name).toString();
      },
    );

    // {{getglobalvar::name}}
    result = result.replaceAllMapped(
      RegExp(r'\{\{getglobalvar::([^}]+)\}\}', caseSensitive: false),
      (match) {
        final name = match.group(1)!.trim();
        return _store.getGlobal(name).toString();
      },
    );

    return result;
  }
}
