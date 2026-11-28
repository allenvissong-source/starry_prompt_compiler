<p align="center">
  <img src=".github/assets/starry-logo.png" alt="Starry logo" width="120" height="120">
</p>
<h1 align="center">Starry Prompt Compiler</h1>
<p align="center"><strong>English</strong> · <a href="README.zh-CN.md">简体中文</a></p>

A pure Dart library that compiles character settings, worldbook entries, and conversation context into prompts. It expands macros, matches worldbook entries, and selects prompt content within a budget.

## Quick start

Clone this repository with Dart 3.9.2 or later and run either example:

```sh
dart pub get
dart run example/standalone.dart
dart run example/character.dart
```

The [standalone example](example/standalone.dart) assembles messages for a general assistant. The [character example](example/character.dart) adds a character description and a user persona.

Use [`starry_prompt_compiler.dart`](lib/starry_prompt_compiler.dart) if your application assembles its own messages, or [`starry_prompt_standalone.dart`](lib/starry_prompt_standalone.dart) for message assembly and history budgeting.

## License

[Apache 2.0](LICENSE)
