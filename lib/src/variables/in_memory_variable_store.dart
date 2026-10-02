import 'dart:convert';

import '../ports/logger.dart';
import '../ports/variable_store.dart';

/// In-memory [VariableStore] implementation used by:
/// - package tests
/// - hosts that do not need durable persistence
///
/// Behavior parity: get/set/index/asType semantics ported verbatim from the
/// host `VariablesService`. Persistence side-effects (SharedPreferences) are
/// intentionally absent — hosts that need them wrap this class or provide a
/// separate adapter.
class InMemoryVariableStore extends VariableStore {
  InMemoryVariableStore({Logger logger = const NoopLogger()})
    : _logger = logger;

  final Logger _logger;

  final Map<String, dynamic> _globalVariables = {};
  final Map<String, Map<String, dynamic>> _localVariables = {};

  // ---------------- Local ----------------

  @override
  dynamic getLocal(String chatId, String name, {String? index}) {
    final chatVars = _localVariables[chatId];
    if (chatVars == null || !chatVars.containsKey(name)) return '';
    return _readIndexedNumericCoerced(chatVars[name], index);
  }

  @override
  void setLocal(
    String chatId,
    String name,
    dynamic value, {
    String? index,
    String? asType,
  }) {
    if (name.isEmpty) {
      throw ArgumentError('Variable name cannot be empty');
    }
    _localVariables[chatId] ??= {};
    final chatVars = _localVariables[chatId]!;

    if (index != null) {
      try {
        chatVars[name] = _writeIndexedValue(
          chatVars[name],
          value,
          index,
          asType,
        );
      } on Object catch (e) {
        _logger.warn(
          'Failed to set indexed local variable "$name[$index]": $e',
        );
      }
    } else {
      chatVars[name] = value;
    }
  }

  @override
  bool existsLocal(String chatId, String name) =>
      _localVariables[chatId]?.containsKey(name) ?? false;

  @override
  void deleteLocal(String chatId, String name) {
    _localVariables[chatId]?.remove(name);
  }

  @override
  Map<String, dynamic> getAllLocal(String chatId) =>
      Map.unmodifiable(_localVariables[chatId] ?? const {});

  @override
  void clearLocal(String chatId) {
    _localVariables.remove(chatId);
  }

  @override
  void importLocalFromMetadata(String chatId, Map<String, dynamic>? metadata) {
    if (metadata != null && metadata.containsKey('variables')) {
      final vars = metadata['variables'];
      if (vars is Map<String, dynamic>) {
        _localVariables[chatId] = Map<String, dynamic>.from(vars);
      }
    }
  }

  @override
  Map<String, dynamic>? exportLocalToMetadata(String chatId) {
    final vars = _localVariables[chatId];
    if (vars == null || vars.isEmpty) return null;
    return {'variables': Map<String, dynamic>.from(vars)};
  }

  // ---------------- Global ----------------

  @override
  dynamic getGlobal(String name, {String? index}) {
    if (!_globalVariables.containsKey(name)) return '';
    return _readIndexedNumericCoerced(_globalVariables[name], index);
  }

  @override
  void setGlobal(String name, dynamic value, {String? index, String? asType}) {
    if (name.isEmpty) {
      throw ArgumentError('Variable name cannot be empty');
    }
    if (index != null) {
      try {
        _globalVariables[name] = _writeIndexedValue(
          _globalVariables[name],
          value,
          index,
          asType,
        );
      } on Object catch (e) {
        _logger.warn(
          'Failed to set indexed global variable "$name[$index]": $e',
        );
      }
    } else {
      _globalVariables[name] = value;
    }
  }

  @override
  bool existsGlobal(String name) => _globalVariables.containsKey(name);

  @override
  void deleteGlobal(String name) {
    _globalVariables.remove(name);
  }

  @override
  Map<String, dynamic> getAllGlobal() => Map.unmodifiable(_globalVariables);

  @override
  void clearGlobal() {
    _globalVariables.clear();
  }

  // ---------------- Internal helpers (mirror host VariablesService) ----------------

  dynamic _readIndexedNumericCoerced(dynamic value, String? index) {
    if (index != null) {
      try {
        var v = value;
        if (v is String) v = jsonDecode(v);

        final numIndex = int.tryParse(index);
        if (numIndex != null && v is List) {
          v = v[numIndex];
        } else if (v is Map) {
          v = v[index];
        }

        if (v is Map || v is List) {
          return jsonEncode(v);
        }
        value = v;
      } on Object catch (e) {
        // The indexed value is not JSON-decodable / indexable; return it
        // as-is rather than failing the whole read. This only opens an
        // observable, injectable diagnostic exit -- the pass-through result
        // below is unchanged.
        _logger.warn(
          'InMemoryVariableStore: indexed read coercion failed for '
          'index "$index"; returning value as-is: $e',
        );
      }
    }

    if (value is String && value.trim().isNotEmpty) {
      final n = double.tryParse(value);
      if (n != null) {
        return n % 1 == 0 ? n.toInt() : n;
      }
    }

    return value ?? '';
  }

  dynamic _writeIndexedValue(
    dynamic current,
    dynamic value,
    String index,
    String? asType,
  ) {
    var c = current;
    if (c is String) c = jsonDecode(c);
    c ??= <String, dynamic>{};

    final convertedValue = _convertValueType(value, asType);
    final numIndex = int.tryParse(index);

    if (numIndex != null) {
      if (c is! List) {
        c = <dynamic>[];
      }
      while (c.length <= numIndex) {
        c.add(null);
      }
      c[numIndex] = convertedValue;
    } else {
      if (c is! Map) {
        c = <String, dynamic>{};
      }
      c[index] = convertedValue;
    }

    return jsonEncode(c);
  }

  dynamic _convertValueType(dynamic value, String? asType) {
    if (asType == null) return value;
    switch (asType.toLowerCase()) {
      case 'number':
      case 'num':
        return double.tryParse(value.toString()) ?? 0;
      case 'int':
      case 'integer':
        return int.tryParse(value.toString()) ?? 0;
      case 'bool':
      case 'boolean':
        return value.toString().toLowerCase() == 'true' || value == 1;
      case 'string':
      case 'str':
        return value.toString();
      default:
        return value;
    }
  }
}
