# starry_prompt_compiler

[English](README.md) · **简体中文**

> 从 Starry 抽取的纯 Dart 提示词编译器——把角色对话的上下文，确定性地编译成可直接发送的消息序列。

**状态**：`0.1.1-dev` · `publish_to: none` · 仅依赖 `intl` + `meta`。

`starry_prompt_compiler` 是 Starry 端上提示词流水线的纯 Dart 内核。给定一份**已解析好的**对话上下文，它把这份上下文确定性地编译成一份有序、可直接发送给模型的消息序列。

它刻意保持**宿主无关**——不依赖 Flutter、Riverpod、文件 I/O、数据库——因此可以脱离 App 独立单测、复用，或迁移到任何 Dart 运行环境。

## 三步装配 seam

对外只暴露一个入口（barrel：`package:starry_prompt_compiler/starry_prompt_compiler.dart`）——调用方不允许伸进 `src/`。核心是一条装配管线，一份 `PromptExecutionPlan` 顺着它流动：

```
buildPlan  ->  admitWorldInfoUnits  ->  buildFromExecutionPlan
```

| 步骤 | 调用 | 做什么 |
|------|------|--------|
| ① 规划 | `PromptExecutionPlanner.buildPlan(request, resolvedContext)` | 收集单元、按 disable 覆盖层过滤、应用 override、按优先级排序、定位历史锚点，产出一份 `PromptExecutionPlan`。 |
| ② 准入 | `WorldInfoBudgetAdmissionService.admitWorldInfoUnits(plan)` | 按 token 预算裁剪世界书单元；返回同一份 plan，只是被裁过。 |
| ③ 拼装 | `CharacterMessageAssemblerPure.buildFromExecutionPlan(...)` | 把每个单元的文本过「宏 → 变量 → 正则」管道，按锚点把历史拼接进去，产出最终 `messages`。 |

宿主可以在**任意两步之间**插手做副作用（取数、附件读盘、预算微调）——这正是把 seam 暴露成三个调用、而非合成一个的原因。

## 快速上手

```dart
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';

// 1. 规划。
const planner = PromptExecutionPlanner();
final plan = planner.buildPlan(
  request: request,                 // CharacterAssemblyRequest
  resolvedContext: resolvedContext, // ResolvedPromptContext（宿主已解析）
  generationType: 'chat',
);

// 2. 按预算准入世界书。
const admission = WorldInfoBudgetAdmissionService();
final admittedPlan = admission.admitWorldInfoUnits(plan).plan;

// 3. 拼装成最终消息序列。
const assembler = CharacterMessageAssemblerPure();
final result = assembler.buildFromExecutionPlan(
  request: request,
  character: resolvedContext.character,
  resolvedContext: resolvedContext,
  executionPlan: admittedPlan,
  assembledHistory: assembledHistory,
);

result.messages; // List<TurnMessage>——可直接发送
```

### 往流水线里注入自己的内容

要注入你自己的数据，把它封成一个 `PromptBlock`，加进 `resolvedContext.resolvedPromptBlocks` 即可。`buildPlan` 会自动收集 prompt block；`priorityPolicy.sortOrder` 控制排序，`placementPolicy.anchor` 控制它相对历史/marker 落在哪里。**无需改动本包。**

## 确定性契约

所有不确定性输入（墙钟时间、随机、区域、日志）都以构造参数形式的 **Ports** 注入：生产用系统实现，测试把它们钉死：

```dart
MacroService(
  clock: FrozenClock(DateTime.utc(2025, 1, 1)),
  random: SeededRandomSource(0),
  locale: const LocaleTag('en_US'),
  logger: const NoopLogger(),
);
```

配合 `behavior_v1` 黄金用例，保证同一输入永远编译出**逐字节一致**的输出。

## 分层

| 层 | 内容 |
|----|------|
| 规划器 | `PromptExecutionPlanner`（const，无状态） |
| 世界书闸门 | `WorldInfoBudgetAdmissionService`、`WorldInfoMatcher` |
| 宏 | `MacroService`（Ports：Clock / RandomSource / LocaleTag / Logger） |
| 正则管道 | `RegexService`（Ports：Logger） |
| 预算 | `MessageBudgetPlanner` |
| 纯装配器 | `CharacterMessageAssemblerPure.buildFromExecutionPlan` |
| 变量 | `InMemoryVariableStore`、`VariableEngine` |
| Ports | `Clock`、`RandomSource`、`LocaleTag`、`Logger`、`VariableStore` + 确定性默认实现 |

## 刻意**不**放在这里的东西

- `PromptContextResolver` / `WorldInfoContextResolver`——依赖仓储层，仅宿主。
- `CharacterMessageAssembler.buildTurnMessages`——读 `File(attachment.path)` 且用 `DateTime.now()`，仅宿主。纯装配器会拒收附件。
- 任何触碰数据库、isolate 调度器、Riverpod 或 Flutter widget 的东西。

## 禁用依赖

以下被挡在纯内核之外（由 `pubspec.yaml` + `analysis_options.yaml` 强制）：`flutter` / 任何 `flutter_*` 包、`flutter_riverpod`、`freezed` / `freezed_annotation`、`dart:io`、`dart:ui`。如果你需要其中之一，那段代码属于宿主，不属于本包。

## 安装与测试

```bash
dart pub get
dart analyze
dart test
```

以 git 依赖引入：

```yaml
dependencies:
  starry_prompt_compiler:
    git:
      url: git@github.com:allenvissong-source/starry_prompt_compiler.git
```
