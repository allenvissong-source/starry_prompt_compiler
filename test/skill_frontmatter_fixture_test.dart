import 'dart:convert';
import 'dart:io';

import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/skill_frontmatter_v1.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final row in fixture['cases'] as List) {
    test('shared Skill frontmatter ${row['id']}', () {
      final text = row['text'] as String;
      final result = codexParseSkill(text);
      expect(result.reason?.wireLabel, row['rejection']);
      if (row['rejection'] != null) {
        expect(result.document, isNull);
      } else {
        expect(result.document!.name, row['name']);
        expect(result.document!.description, row['description']);
        expect(result.document!.body, row['body']);
        expect(result.document!.originalText, text);
      }
    });
  }
}
