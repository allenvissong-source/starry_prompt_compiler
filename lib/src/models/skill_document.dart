/// Standard SKILL.md parsing shared by authoring, packaging and runtime.
///
/// A document supplies instructions. Its frontmatter never grants tools or
/// permissions, including unknown keys such as `allowed-tools`.
class CodexSkillDocument {
  const CodexSkillDocument({
    required this.name,
    required this.description,
    required this.body,
    this.originalText = '',
  });

  final String name;
  final String description;
  final String body;

  /// Original bytes decoded as UTF-8, including unknown frontmatter fields.
  /// Editors and exports must use this rather than reconstructing frontmatter.
  final String originalText;
}

enum CodexSkillRejection {
  missingFrontmatter,
  missingName,
  missingDescription;

  String get wireLabel => switch (this) {
    missingFrontmatter => 'missing_frontmatter',
    missingName => 'missing_name',
    missingDescription => 'missing_description',
  };
}

({CodexSkillDocument? document, CodexSkillRejection? reason}) codexParseSkill(
  String text,
) {
  final lines = text.split('\n');
  var start = 0;
  while (start < lines.length && lines[start].trim().isEmpty) {
    start++;
  }
  if (start >= lines.length || lines[start].trim() != '---') {
    return (document: null, reason: CodexSkillRejection.missingFrontmatter);
  }
  var end = -1;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end < 0) {
    return (document: null, reason: CodexSkillRejection.missingFrontmatter);
  }
  String? name;
  String? description;
  for (var i = start + 1; i < end; i++) {
    final line = lines[i];
    final colon = line.indexOf(':');
    if (colon <= 0) continue;
    final key = line.substring(0, colon).trim().toLowerCase();
    final value = line.substring(colon + 1).trim();
    if (key == 'name') name = value;
    if (key == 'description') description = value;
  }
  if (name == null || name.isEmpty) {
    return (document: null, reason: CodexSkillRejection.missingName);
  }
  if (description == null || description.isEmpty) {
    return (document: null, reason: CodexSkillRejection.missingDescription);
  }
  return (
    document: CodexSkillDocument(
      name: name,
      description: description,
      body: lines.sublist(end + 1).join('\n').trim(),
      originalText: text,
    ),
    reason: null,
  );
}
