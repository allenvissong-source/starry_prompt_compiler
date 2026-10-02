# starry_prompt_compiler

**English** · [简体中文](README.zh-CN.md)

> Pure-Dart prompt compiler extracted from Starry — deterministically compiles
> character-chat context into a ready-to-send message sequence.

**Status**: `0.1.1-dev` · `publish_to: none` · depends only on `intl` + `meta`.

`starry_prompt_compiler` is the pure-Dart core of Starry's on-device prompt
pipeline. Given an **already-resolved** conversation context, it deterministically
compiles that context into an ordered, ready-to-send message sequence.

It is deliberately **host-agnostic** — no Flutter, no Riverpod, no file I/O, no
database — so it can be unit-tested in isolation, reused, or dropped into any
Dart runtime independent of the app.

## The three-step seam

A single barrel (`package:starry_prompt_compiler/starry_prompt_compiler.dart`)
exposes the whole public surface — callers must not reach into `src/`. At the
core is one assembly pipeline through which a single `PromptExecutionPlan` flows:

```
buildPlan  ->  admitWorldInfoUnits  ->  buildFromExecutionPlan
```

| Step | Call | Does |
|------|------|------|
| ① Plan | `PromptExecutionPlanner.buildPlan(request, resolvedContext)` | Collect units, filter by disable-overlays, apply overrides, sort by priority, locate history anchors. Produces a `PromptExecutionPlan`. |
| ② Admit | `WorldInfoBudgetAdmissionService.admitWorldInfoUnits(plan)` | Crop world-info units against the token budget; returns the same plan, trimmed. |
| ③ Assemble | `CharacterMessageAssemblerPure.buildFromExecutionPlan(...)` | Run each unit's text through macro → variable → regex, splice history at its anchors, emit the final `messages`. |

The host may step in **between** any two stages to perform side effects (data
fetching, attachment reads, budget tuning) — that is the whole reason the seam
is exposed as three calls rather than one.

## Quick start

```dart
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';

// 1. Plan.
const planner = PromptExecutionPlanner();
final plan = planner.buildPlan(
  request: request,               // CharacterAssemblyRequest
  resolvedContext: resolvedContext, // ResolvedPromptContext (host-resolved)
  generationType: 'chat',
);

// 2. Admit world-info against the budget.
const admission = WorldInfoBudgetAdmissionService();
final admittedPlan = admission.admitWorldInfoUnits(plan).plan;

// 3. Assemble into the final message sequence.
const assembler = CharacterMessageAssemblerPure();
final result = assembler.buildFromExecutionPlan(
  request: request,
  character: resolvedContext.character,
  resolvedContext: resolvedContext,
  executionPlan: admittedPlan,
  assembledHistory: assembledHistory,
);

result.messages; // List<TurnMessage> — ready to send
```

### Extending the pipeline

To inject your own content, wrap it as a `PromptBlock` and add it to
`resolvedContext.resolvedPromptBlocks`. `buildPlan` collects prompt blocks
automatically; `priorityPolicy.sortOrder` controls ordering and
`placementPolicy.anchor` controls where it lands relative to history/markers.
No changes to this package are required.

## Determinism contract

All non-deterministic inputs (wall-clock time, RNG, locale, logging) are
injected as constructor-level **Ports**. Production uses system implementations;
tests pin them:

```dart
MacroService(
  clock: FrozenClock(DateTime.utc(2025, 1, 1)),
  random: SeededRandomSource(0),
  locale: const LocaleTag('en_US'),
  logger: const NoopLogger(),
);
```

Together with the `behavior_v1` golden suite, this guarantees the same input
always compiles to **byte-identical** output.

## Layers

| Layer | Content |
|-------|---------|
| Planner | `PromptExecutionPlanner` (const, stateless) |
| World-info gate | `WorldInfoBudgetAdmissionService`, `WorldInfoMatcher` |
| Macros | `MacroService` (Ports: Clock / RandomSource / LocaleTag / Logger) |
| Regex pipeline | `RegexService` (Ports: Logger) |
| Budget | `MessageBudgetPlanner` |
| Assembler (pure) | `CharacterMessageAssemblerPure.buildFromExecutionPlan` |
| Variables | `InMemoryVariableStore`, `VariableEngine` |
| Ports | `Clock`, `RandomSource`, `LocaleTag`, `Logger`, `VariableStore` + deterministic defaults |

## What deliberately does **not** live here

- `PromptContextResolver` / `WorldInfoContextResolver` — depend on repositories; host-only.
- `CharacterMessageAssembler.buildTurnMessages` — reads `File(attachment.path)` and uses `DateTime.now()`; host-only. The pure assembler rejects attachments.
- Anything touching the DB, isolate scheduler, Riverpod, or Flutter widgets.

## Forbidden dependencies

Kept out of the pure core (enforced by `pubspec.yaml` + `analysis_options.yaml`):
`flutter` / any `flutter_*` package, `flutter_riverpod`, `freezed` /
`freezed_annotation`, `dart:io`, `dart:ui`. If you need one of these, the code
belongs in the host, not here.

## Install & test

```bash
dart pub get
dart analyze
dart test
```

Consume it as a git dependency:

```yaml
dependencies:
  starry_prompt_compiler:
    git:
      url: git@github.com:allenvissong-source/starry_prompt_compiler.git
```
