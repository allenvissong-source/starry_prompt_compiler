import 'dart:convert';

/// Canonical UTF-8 JSON/FNV-1a contract shared with the execution host.
/// Digests detect stale snapshots; they are not authorization signatures.
String promptDigest(Object? value) {
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  for (final byte in utf8.encode(canonicalPromptJson(value))) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String canonicalPromptJson(Object? value) {
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw FormatException('prompt_plan.invalid_json_key');
    }
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalPromptJson(value[key])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(canonicalPromptJson).join(',')}]';
  }
  if (value == null ||
      value is String ||
      value is bool ||
      (value is num && value.isFinite)) {
    return jsonEncode(value);
  }
  throw FormatException('prompt_plan.invalid_json_value');
}

Map<String, dynamic> promptObject(Object? value, Set<String> fields) {
  if (value is! Map<String, dynamic> ||
      value.keys.any((key) => !fields.contains(key))) {
    throw FormatException('prompt_plan.invalid_fields');
  }
  return value;
}

String promptString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > 1024) {
    throw FormatException('prompt_plan.invalid_$key');
  }
  return value;
}

String promptText(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || utf8.encode(value).length > 4 * 1024 * 1024) {
    throw FormatException('prompt_plan.invalid_$key');
  }
  return value;
}

int promptInt(Map<String, dynamic> json, String key, {int min = 0}) {
  final value = json[key];
  if (value is! int || value < min || value > 9007199254740991) {
    throw FormatException('prompt_plan.invalid_$key');
  }
  return value;
}

bool promptBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('prompt_plan.invalid_$key');
  return value;
}

List<T> promptList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Object?) decode,
) {
  final value = json[key];
  if (value is! List || value.length > 16384) {
    throw FormatException('prompt_plan.invalid_$key');
  }
  return List<T>.unmodifiable(value.map(decode));
}

String promptEnumName(Enum value) => value.name.replaceAllMapped(
  RegExp('[A-Z]'),
  (m) => '_${m[0]!.toLowerCase()}',
);

T promptEnum<T extends Enum>(Object? value, List<T> values) {
  for (final candidate in values) {
    if (value == promptEnumName(candidate)) return candidate;
  }
  throw FormatException('prompt_plan.invalid_enum');
}

void promptUnique(Iterable<String> values) {
  final ids = <String>{};
  for (final id in values) {
    if (!ids.add(id)) throw FormatException('prompt_plan.duplicate_id');
  }
}
