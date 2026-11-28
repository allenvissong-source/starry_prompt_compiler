<p align="center">
  <img src=".github/assets/starry-logo.png" alt="Starry 标志" width="120" height="120">
</p>
<h1 align="center">Starry Prompt Compiler</h1>
<p align="center"><a href="README.md">English</a> · <strong>简体中文</strong></p>

一个纯 Dart 提示词编译库，将角色设定、世界书条目和对话上下文编译成提示词。支持展开宏、匹配世界书条目，以及在预算内筛选内容。

## 快速开始

使用 Dart 3.9.2 或更新版本。克隆本仓库后，可直接运行示例：

```sh
dart pub get
dart run example/standalone.dart
dart run example/character.dart
```

[通用助手示例](example/standalone.dart)演示如何组装消息；[角色示例](example/character.dart)在消息中加入角色描述与用户人设。

应用自行组装消息时使用 [`starry_prompt_compiler.dart`](lib/starry_prompt_compiler.dart)；需要库组装消息、为历史记录分配预算时，使用 [`starry_prompt_standalone.dart`](lib/starry_prompt_standalone.dart)。

## 许可证

[Apache 2.0](LICENSE)
