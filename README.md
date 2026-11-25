# starry_prompt_compiler

**English** · [简体中文](README.zh-CN.md)

Pure Dart domain prompt compilation, with a separate assembly library for
independent Dart hosts. No Flutter, Riverpod, database or file I/O in `lib/`.

## Public libraries

| Library | Responsibility |
|---|---|
| `starry_prompt_compiler.dart` | Domain planning, frozen expansion, source and placement models, worldbook admission |
| `starry_prompt_standalone.dart` | The same compiler plus standalone message assembly, cost estimation and history budgeting |

Callers use these public libraries rather than importing `src/`. Starry uses
the domain library; its Rust Host owns final messages, total budgeting and
history compaction. Each host chooses one final assembler.

## Domain pipeline

```text
authorized resource snapshots
→ PromptExecutionPlanner.buildDomainPlan
→ DomainPromptCompiler.prepareCandidates
→ host costs and budget
→ DomainPromptCompiler.admitCandidates
→ CompiledPromptPlan
→ the host's final assembler
```

The planner handles characters, generic assistants, built-in identity, Persona,
Profile/Block overrides, worldbooks, markers, outlets and depth constraints.
Preparation expands each unit once through macros, scratch variables and regex.
Repeated emissions reuse the expanded text and are charged separately.
Admission selects whole frozen units; required overflow fails explicitly.

The host supplies immutable sources, input/history digests, clock, random source,
locale, variable scopes and regex configuration. Local and global variables use
separate scratch stores; compilation does not persist variable writes.

The `/v1/injections:resolve` external host uses the explicit `flatInjections`,
`literalInjectionText` and `injectionAllowance` policies. It preserves raw text
and its external allocation contract; the caller owns placement and final model
budgeting. These policies are not used by Starry chat.

An entry can set `extensions.targetingPolicy.requiredTermGroups` (a list of
lists of literal strings). A keyed match, whether literal or ranked, then
requires at least one term from every group in a single sentence of the
entry's scan scope. Sentence-ending punctuation, semicolons and line breaks
separate sentences; commas do not. Entry case and whole-word settings also
apply to these terms. The rule is additive to the existing key logic and does
not affect always-on entries. For example, `[["Millennium"], ["engineering"]]`
keeps a topic mention in a different sentence from borrowing the school name.

## Executable examples

[Standalone assistant](example/standalone.dart) and
[character context](example/character.dart) run without Flutter, Rust or a
database:

```bash
dart run example/standalone.dart
dart run example/character.dart
```

They demonstrate the full independent chain:

```dart
import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';

// candidates: frozen PreparedPromptCandidates from the domain pipeline.
final policy = StandalonePromptBudgetPolicy(
  contextTokens: 4096,
  outputReserveTokens: 512,
);
const assembler = StandalonePromptAssembler();
final budget = assembler.prepareAdmission(
  candidates: candidates,
  policy: policy,
);
final plan = const DomainPromptCompiler().admitCandidates(candidates, budget);
final result = assembler.assemble(
  candidates: candidates,
  plan: plan,
  policy: policy,
);
```

Standalone assembly drops complete old history groups deterministically. It
does not call a model for summaries. The host may provide an existing summary
and retained history. Production Starry does not call this assembler.

## Contract and verification

The shared schema, costs, layout and production boundary are documented in
[domain-prompt-runtime-v1.md](../starry/docs/contracts/domain-prompt-runtime-v1.md).
Shared fixtures verify Dart/Rust wire, costs, placement and Skill frontmatter.
Skill document parsing does not grant tool access.

```bash
dart analyze
dart test
dart format --output=none --set-exit-if-changed .
```

Consume this unpublished package through a sibling path dependency or its Git
repository. See `pubspec.yaml` for the current version and dependencies.

## License

This package is licensed under [Apache-2.0](LICENSE).
