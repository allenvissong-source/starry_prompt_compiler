# AGENTS.md — starry_prompt_compiler

Starry 的领域提示词编译核心。**纯 Dart,宿主无关**:无 Flutter、无 Riverpod、无 I/O、
无数据库。领域匹配、覆盖、展开、位置约束和世界书子预算准入在这里；
执行宿主提供统一成本及额度，并决定最终消息、全局预算与历史窗口。

本包是依赖链的最底层:

```
starry_prompt_compiler          ← 本包,不依赖任何兄弟仓
  └── starry_domain_entities
        └── starry_character_card_codec
              └── starry_injection_service
```

## 1. 架构边界

领域主路径是 `buildDomainPlan` → `prepareCandidates` → 宿主计费 →
`admitCandidates`。候选正文仅展开一次，准入消费冻结结果，不回放宏。
普通 Assistant 不要求假造 Character。所有宿主均使用同一 planner 和 compiler；
不得绕过筛选、覆盖和位置决策，手工生成另一份执行计划。

`/v1/injections:resolve` 是扁平外部注入宿主，明确使用 `flatInjections`、
`literalInjectionText` 和 `injectionAllowance`；保留裸正文、外部注入额度及
原 UTF-16 成本口径，位置、展开和最终总预算由调用它的宿主负责。
Starry 完整模型链默认使用 contextual／expanded／required 策略，不使用这些
外部端点策略。默认必选内容超限必须报错，不得把外部份额策略用于模型链。

`starry_prompt_compiler.dart` 提供领域入口。
`starry_prompt_standalone.dart` 提供独立 Dart 宿主的完整装配、成本及历史策略。
Starry 的生产调用不得使用 standalone 装配器；最终消息由 Rust Host 物化。
独立示例：`dart run example/standalone.dart` 和 `dart run example/character.dart`。

领域 API 不接受最终装配请求、附件路径或宿主全局裁剪计划；有效行为测试直接驱动
领域编译和明确选择的宿主装配器，禁止为测试恢复生产兼容接口。

- **匹配、排序、预算准入只有一份实现**。`MacroService` / `RegexService` /
  `WorldInfoMatcher` 是各自领域的唯一真源;上层不得重新实现,只能调用。
- **不引入 I/O 与平台依赖**。`lib/` 下 `dart:io`、`dart:ui`、`package:flutter`
  一律禁止(当前零违反)。`test/` 下有一处例外
  (`text_recall_calibration_test.dart:21` 用 `dart:io` 读标定数据),
  测试侧按需放行,生产代码不行。
- 依赖保持最小:当前仅 `intl`。新增依赖需先确认它也是纯 Dart 且无平台绑定。

## 2. `SessionPromptContext` 只有当前 V1 形态

`SessionPromptContext` 不再写入或读取开发期 `version` 字段。当前只存在一套会话提示词上下文语义；旧 JSON 中多余的 `version` 键会被 `fromJson` 自然忽略。

- 不要重新引入没有行为分支的版本戳、兼容 shim 或双轨结构。
- 只有外部契约出现真实且不可压平的多版本输入时，才应先定义差异语义与迁移测试，再讨论版本字段。

## 3. override 决策收敛为 trace

`ExecutionOverrideDecision` 是 planner 内部计算 override 结果的中间模型。`_applyOverrides` 将这些决策转换为 `ExecutionTraceEntry`，最终 `PromptExecutionPlan` 只公开 `trace`，不再重复公开 `effectiveOverrides`。

- 新增 override 类型时应继续写入 `ExecutionTraceStage.override` 的 trace。
- 不要恢复两份表达同一决策的公共结果字段。

## 4. 验证

```powershell
dart analyze
dart test
dart format --set-exit-if-changed .
```

验证以实际命令结果为准，不以历史测试数量代替当前检查。

使用满足锁文件约束的 SDK。GitHub Actions 已停用；
分析、测试与格式检查均在本地完成，不触发付费 CI。

改动影响上层时，回同级主工程 `starry` 跑
`flutter analyze` 与 `flutter test`——本包全绿不代表上层能编译。

## 5. 约定

- 不写墓碑注释("这里删了 X / 待清理"),版本历史可追溯。
- 不为假想的未来场景预埋兼容层、fallback 或双轨逻辑。
- 判断"零调用"时先分清:**生产写入** / 仅测试读取 / 真零引用。三者处置不同。
- 临时产物放系统临时目录，正式交付遵守工作区 `AGENTS.md`。
