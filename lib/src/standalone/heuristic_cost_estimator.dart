/// Cost contract shared with Rust: ASCII / 4 rounded up, non-ASCII / 1,
/// four tokens per text message. This is an estimate, not a tokenizer.
abstract class PromptCostEstimator {
  const PromptCostEstimator();

  String get id;
  int text(String value);
  int message(String value) => 4 + text(value);
}

class HeuristicPromptCostEstimator extends PromptCostEstimator {
  const HeuristicPromptCostEstimator();

  @override
  String get id => 'starry_ascii4_unicode1_image16384_v1';

  @override
  int text(String value) {
    var ascii = 0;
    var other = 0;
    for (final rune in value.runes) {
      if (rune <= 127) {
        ascii++;
      } else {
        other++;
      }
    }
    return (ascii + 3) ~/ 4 + other;
  }
}
