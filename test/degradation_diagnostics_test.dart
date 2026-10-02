import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

/// Degradation-diagnostics contract for the three pure services that swallow
/// errors and pass through a safe result:
///
///   * [RegexService] -- an un-compilable regex degrades to `null`;
///   * [VariableEngine] -- a stored value that is not a JSON list degrades the
///     array-add to the number/concat path;
///   * [InMemoryVariableStore] -- an indexed read that cannot JSON-decode /
///     index degrades to returning the value as-is.
///
/// The pass-through *results* are pinned unchanged; the point of these tests is
/// that each degradation now has a REAL, injectable diagnostic exit
/// ([Logger] -- here a [CallbackLogger] capturing every `warn`), rather than a
/// silently swallowed error.
void main() {
  Logger captureWarns(List<String> sink) =>
      CallbackLogger((level, message, [error, stackTrace]) {
        if (level == 'warn') sink.add(message);
      });

  group('RegexService degradation', () {
    test('an un-compilable pattern warns and degrades to null', () {
      final warns = <String>[];
      final svc = RegexService(logger: captureWarns(warns));

      expect(svc.getRegex('([unclosed'), isNull);
      expect(warns, hasLength(1));
      expect(warns.single, contains('Failed to compile regex'));
    });

    test('a valid pattern logs nothing', () {
      final warns = <String>[];
      final svc = RegexService(logger: captureWarns(warns));

      expect(svc.getRegex('foo'), isNotNull);
      expect(warns, isEmpty);
    });
  });

  group('VariableEngine degradation', () {
    test('a non-JSON-list global warns and still falls back to concat', () {
      final warns = <String>[];
      final store = InMemoryVariableStore();
      final engine = VariableEngine(store: store, logger: captureWarns(warns));

      store.setGlobal('greet', 'not-a-list');
      // Pass-through result: array-add degrades to number/concat, and there is
      // no number here, so it concatenates exactly as before the hook existed.
      expect(engine.addGlobal('greet', '!'), 'not-a-list!');

      expect(warns, hasLength(1));
      expect(warns.single, contains('not a JSON list'));
    });

    test('a valid JSON list warns nothing', () {
      final warns = <String>[];
      final store = InMemoryVariableStore();
      final engine = VariableEngine(store: store, logger: captureWarns(warns));

      store.setGlobal('items', '[1,2]');
      expect(engine.addGlobal('items', 3), <dynamic>[1, 2, 3]);
      expect(warns, isEmpty);
    });
  });

  group('InMemoryVariableStore degradation', () {
    test('an indexed read of a non-JSON value warns and returns as-is', () {
      final warns = <String>[];
      final store = InMemoryVariableStore(logger: captureWarns(warns));

      store.setLocal('c1', 'raw', '{not-json');
      // Pass-through result: the value comes back verbatim (the indexed decode
      // failed), and the failure is now observable.
      expect(store.getLocal('c1', 'raw', index: '0'), '{not-json');

      expect(warns, hasLength(1));
      expect(warns.single, contains('indexed read coercion failed'));
    });
  });
}
