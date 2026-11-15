# starry_prompt_compiler

[English](README.md) · **简体中文**

纯 Dart 领域提示词编译核心，并为独立 Dart 宿主提供单独的完整装配入口。
`lib/` 不依赖 Flutter、Riverpod、数据库或文件 I/O。

## 两个公开入口

| 入口 | 职责 |
|---|---|
| `starry_prompt_compiler.dart` | 领域规划、冻结展开、来源与位置模型、世界书准入 |
| `starry_prompt_standalone.dart` | 复用同一编译器，增加独立消息装配、成本与历史预算 |

调用方使用公开入口，不直接导入 `src/`。Starry 使用领域入口，由 Rust Host
统一生成最终消息、核算全局预算与管理历史压缩。每条宿主链只选择一个最终装配器。

## 领域流水线

```text
授权资源快照
→ PromptExecutionPlanner.buildDomainPlan
→ DomainPromptCompiler.prepareCandidates
→ 宿主提供成本与预算
→ DomainPromptCompiler.admitCandidates
→ CompiledPromptPlan
→ 宿主最终装配器
```

规划器统一处理角色、普通 Assistant、内置身份、Persona、Profile／Block 覆盖、
世界书、marker、outlet 和深度约束。prepare 按宏、scratch 变量、正则的顺序
展开单元；同单元多个 emission 复用正文，分别计费。admit 只选择完整冻结单元，
必选内容超预算明确失败。

宿主提供不可变来源、输入／历史摘要、时钟、随机源、locale、变量作用域与正则配置。
本轮 local／global scratch 分开，编译不隐式持久写入变量。

外部 `/v1/injections:resolve` 宿主显式选择 `flatInjections`、
`literalInjectionText`、`injectionAllowance`：保留裸正文与外部注入份额契约，
位置及最终模型预算由调用它的宿主负责。Starry 聊天不使用这些端点策略。

## 可运行示例

[普通 Assistant](example/standalone.dart) 与[角色上下文](example/character.dart)
包含完整的编译、准入及独立装配代码，无需 Flutter、Rust 或数据库：

```bash
dart run example/standalone.dart
dart run example/character.dart
```

独立宿主从领域流水线得到 `PreparedPromptCandidates` 后使用：

```dart
import 'package:starry_prompt_compiler/starry_prompt_standalone.dart';

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

独立装配器按完整历史组确定性淘汰旧历史，不调用模型生成摘要。宿主可提供已经
验证的摘要及保留历史。Starry 的生产模型链不调用这个装配器。

## 契约与验证

统一 schema、成本、布局和生产职责见
[domain-prompt-runtime-v1.md](../starry/docs/contracts/domain-prompt-runtime-v1.md)。
共享 fixtures 核验 Dart／Rust wire、成本、位置与 Skill frontmatter。
Skill 文档解析不授予工具权限。

```bash
dart analyze
dart test
dart format --output=none --set-exit-if-changed .
```

本包通过同级 path 或 Git 依赖复用；当前版本与依赖以 `pubspec.yaml` 为准。

## 许可

本包按 [Apache-2.0](LICENSE) 许可完整开源。
