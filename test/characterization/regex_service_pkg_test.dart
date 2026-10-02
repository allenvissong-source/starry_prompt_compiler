// Characterization tests for RegexService (behavior baseline),
// extracted from the main-project dual-SUT test into a pure-Dart, in-package
// test. Source of truth:
//   test/features/prompt_compiler/regex_service_characterization_test.dart
// (SUT=package groups). Import rewrites + `pkg.` prefix stripped.
import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

RegexScript _pkgScript({
  required String id,
  required String find,
  required String replace,
  List<RegexPlacement> placement = const [RegexPlacement.aiOutput],
  bool disabled = false,
  bool promptOnly = false,
  bool markdownOnly = false,
  bool runOnEdit = false,
  List<String> trimStrings = const [],
  SubstituteRegex substituteRegex = SubstituteRegex.none,
  int order = 0,
  int? minDepth,
  int? maxDepth,
}) {
  final ts = DateTime.utc(2020, 1, 1);
  return RegexScript(
    id: id,
    scriptName: id,
    findRegex: find,
    replaceString: replace,
    placement: placement,
    createdAt: ts,
    updatedAt: ts,
    disabled: disabled,
    promptOnly: promptOnly,
    markdownOnly: markdownOnly,
    runOnEdit: runOnEdit,
    trimStrings: trimStrings,
    substituteRegex: substituteRegex,
    order: order,
    minDepth: minDepth,
    maxDepth: maxDepth,
  );
}

void main() {
  final pkgSvc = RegexService(logger: const NoopLogger());

  group('SUT=package | RegexService.runRegexScript (single script)', () {
    test('plain find/replace', () {
      final s = _pkgScript(id: 's', find: 'foo', replace: 'bar');
      expect(pkgSvc.runRegexScript(s, 'a foo b foo'), 'a bar b bar');
    });

    test('/pattern/flags with i flag is case-insensitive', () {
      final s = _pkgScript(id: 's', find: '/foo/i', replace: 'X');
      expect(pkgSvc.runRegexScript(s, 'FOO foo Foo'), 'X X X');
    });

    test('numbered capture groups \$1', () {
      final s = _pkgScript(id: 's', find: r'/(\w+)@(\w+)/', replace: r'$2/$1');
      expect(pkgSvc.runRegexScript(s, 'user@host'), 'host/user');
    });

    test('{{match}} references the whole match', () {
      final s = _pkgScript(id: 's', find: r'/\d+/', replace: '[{{match}}]');
      expect(pkgSvc.runRegexScript(s, 'x42y'), 'x[42]y');
    });

    test('named capture group \$<name>', () {
      final s = _pkgScript(
        id: 's',
        find: r'/(?<num>\d+)/',
        replace: r'#$<num>',
      );
      expect(pkgSvc.runRegexScript(s, 'ab12cd'), 'ab#12cd');
    });

    test('trimStrings strips substrings from captured groups', () {
      final s = _pkgScript(
        id: 's',
        find: r'/<(.+?)>/',
        replace: r'$1',
        trimStrings: ['*'],
      );
      expect(pkgSvc.runRegexScript(s, '<a*b*c>'), 'abc');
    });

    test('macro substitution in replacement (raw always applies)', () {
      final s = _pkgScript(id: 's', find: 'NAME', replace: '{{char}}');
      expect(
        pkgSvc.runRegexScript(s, 'Hi NAME', characterName: 'Zed'),
        'Hi Zed',
      );
    });

    test('substituteRegex.raw expands macros inside the find pattern', () {
      final s = _pkgScript(
        id: 's',
        find: '{{char}}',
        replace: 'X',
        substituteRegex: SubstituteRegex.raw,
      );
      expect(
        pkgSvc.runRegexScript(s, 'meet Zed now', characterName: 'Zed'),
        'meet X now',
      );
    });

    test('disabled script is a no-op', () {
      final s = _pkgScript(
        id: 's',
        find: 'foo',
        replace: 'bar',
        disabled: true,
      );
      expect(pkgSvc.runRegexScript(s, 'foo'), 'foo');
    });

    test('empty input or empty find is a no-op', () {
      expect(
        pkgSvc.runRegexScript(_pkgScript(id: 's', find: 'x', replace: 'y'), ''),
        '',
      );
      expect(
        pkgSvc.runRegexScript(_pkgScript(id: 's', find: '', replace: 'y'), 'x'),
        'x',
      );
    });
  });

  group('SUT=package | RegexService.getRegexedString (script list gating)', () {
    test('only scripts whose placement matches are applied', () {
      final scripts = [
        _pkgScript(
          id: 'ai',
          find: 'foo',
          replace: 'AI',
          placement: [RegexPlacement.aiOutput],
        ),
        _pkgScript(
          id: 'ui',
          find: 'foo',
          replace: 'UI',
          placement: [RegexPlacement.userInput],
        ),
      ];
      expect(
        pkgSvc.getRegexedString('foo', RegexPlacement.aiOutput, scripts),
        'AI',
      );
      expect(
        pkgSvc.getRegexedString('foo', RegexPlacement.userInput, scripts),
        'UI',
      );
    });

    test('scripts run in ascending order and chain', () {
      final scripts = [
        _pkgScript(id: 'second', find: 'B', replace: 'C', order: 2),
        _pkgScript(id: 'first', find: 'A', replace: 'B', order: 1),
      ];
      expect(
        pkgSvc.getRegexedString('A', RegexPlacement.aiOutput, scripts),
        'C',
      );
    });

    test('disabled scripts in the list are skipped', () {
      final scripts = [
        _pkgScript(id: 'd', find: 'foo', replace: 'X', disabled: true),
      ];
      expect(
        pkgSvc.getRegexedString('foo', RegexPlacement.aiOutput, scripts),
        'foo',
      );
    });

    test('promptOnly runs only when isPrompt is true', () {
      final scripts = [
        _pkgScript(id: 'p', find: 'foo', replace: 'X', promptOnly: true),
      ];
      expect(
        pkgSvc.getRegexedString(
          'foo',
          RegexPlacement.aiOutput,
          scripts,
          isPrompt: true,
        ),
        'X',
      );
      expect(
        pkgSvc.getRegexedString('foo', RegexPlacement.aiOutput, scripts),
        'foo',
      );
    });

    test(
      'a plain (non-prompt/non-markdown) script is skipped while isPrompt',
      () {
        final scripts = [_pkgScript(id: 'plain', find: 'foo', replace: 'X')];
        expect(
          pkgSvc.getRegexedString(
            'foo',
            RegexPlacement.aiOutput,
            scripts,
            isPrompt: true,
          ),
          'foo',
        );
      },
    );

    test('depth gating: minDepth/maxDepth bound applicability', () {
      final scripts = [
        _pkgScript(
          id: 'deep',
          find: 'foo',
          replace: 'X',
          minDepth: 2,
          maxDepth: 4,
        ),
      ];
      expect(
        pkgSvc.getRegexedString(
          'foo',
          RegexPlacement.aiOutput,
          scripts,
          depth: 3,
        ),
        'X',
      );
      expect(
        pkgSvc.getRegexedString(
          'foo',
          RegexPlacement.aiOutput,
          scripts,
          depth: 1,
        ),
        'foo',
      );
      expect(
        pkgSvc.getRegexedString(
          'foo',
          RegexPlacement.aiOutput,
          scripts,
          depth: 5,
        ),
        'foo',
      );
    });

    test('empty input short-circuits', () {
      final scripts = [_pkgScript(id: 's', find: 'foo', replace: 'X')];
      expect(pkgSvc.getRegexedString('', RegexPlacement.aiOutput, scripts), '');
    });
  });

  group('RegexService.clearCache', () {
    test('clearing the cache between runs leaves results unchanged', () {
      // The compiled-pattern cache is private and Dart canonicalizes RegExp
      // instances, so object identity cannot observe a cache miss. This pins
      // the observable, contract-level property: clearing is safe, the service
      // rebuilds on demand, business output is identical, and no diagnostic is
      // raised.
      final warns = <String>[];
      final svc = RegexService(
        logger: CallbackLogger((level, message, [error, stack]) {
          if (level == 'warn' || level == 'error') warns.add(message);
        }),
      );
      final script = _pkgScript(id: 'c', find: r'foo(\d+)', replace: r'[$1]');
      const input = 'x foo123 y foo45 z';

      final warm = svc.runRegexScript(script, input);

      svc.clearCache();

      // After clearing, the pattern recompiles on demand and output matches.
      expect(svc.getRegex(r'foo(\d+)'), isNotNull);
      expect(svc.runRegexScript(script, input), warm);

      // Repeated clears (including on an already-empty cache) are also safe.
      svc.clearCache();
      svc.clearCache();
      expect(svc.runRegexScript(script, input), warm);
      expect(warns, isEmpty);
    });
  });
}
