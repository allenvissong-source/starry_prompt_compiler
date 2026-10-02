import 'package:starry_prompt_compiler/starry_prompt_compiler.dart';
import 'package:test/test.dart';

/// Instant-basis guard for the four persisted models that did NOT carry
/// `.toUtc()` before this change.
///
/// `character_entities.dart` and `worldbook_entities.dart` already normalized,
/// so the divergence was silent: the same package emitted two different
/// timestamp dialects. Every pre-existing round-trip case feeds a `...Z`
/// literal, which passes either way — that is why this defect survived 177
/// green cases.
///
/// The fixtures below feed a *non-UTC* `DateTime`, which is what production
/// actually persists: all four `fromJson` factories fall back to a bare
/// `DateTime.now()` (`prompt_profile.dart:44,47`, `prompt_manager.dart:855,856`,
/// `regex_profile.dart:91,94`, `regex_script.dart:120,123`) and `DateTime.now()`
/// is local.
///
/// The assertion is on the serialized *basis marker*, not on value equality.
/// A bare `toIso8601String()` on a local instance emits no `Z` and no offset on
/// any machine in any zone, so this is zone-independent and does not depend on
/// the agent host being UTC+8.
void main() {
  /// Deliberately NOT `DateTime.utc(...)` — `isUtc` is false.
  DateTime localAt() => DateTime(2026, 3, 4, 5, 6, 7);

  void expectUtcBasis(Object? serialized, String field) {
    expect(
      serialized,
      isA<String>(),
      reason: '$field must serialize to string',
    );
    final text = serialized! as String;
    expect(
      text.endsWith('Z'),
      isTrue,
      reason:
          '$field serialized as "$text", which carries no UTC basis marker; '
          'a reader cannot recover the writer zone',
    );
    final parsed = DateTime.parse(text);
    expect(parsed.isUtc, isTrue, reason: '$field must parse back as UTC');
    expect(
      parsed.isAtSameMomentAs(localAt()),
      isTrue,
      reason: '$field must denote the same instant it was given',
    );
  }

  test('fixture precondition: the input really is non-UTC', () {
    expect(localAt().isUtc, isFalse);
  });

  group('PromptProfileResource', () {
    Map<String, dynamic> json() => PromptProfileResource(
      id: 'profile-1',
      name: 'Profile',
      config: PromptManagerConfig.defaultConfig(),
      createdAt: localAt(),
      updatedAt: localAt(),
    ).toJson();

    test('a non-UTC createdAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['createdAt'], 'createdAt');
    });

    test('a non-UTC updatedAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['updatedAt'], 'updatedAt');
    });

    test('the json round trip preserves the instant', () {
      final restored = PromptProfileResource.fromJson(json());

      expect(restored.createdAt.isAtSameMomentAs(localAt()), isTrue);
      expect(restored.updatedAt.isAtSameMomentAs(localAt()), isTrue);
    });
  });

  group('PromptManagerPreset', () {
    Map<String, dynamic> json() => PromptManagerPreset(
      id: 'preset-1',
      name: 'Preset',
      config: PromptManagerConfig.defaultConfig(),
      createdAt: localAt(),
      updatedAt: localAt(),
    ).toJson();

    test('a non-UTC createdAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['createdAt'], 'createdAt');
    });

    test('a non-UTC updatedAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['updatedAt'], 'updatedAt');
    });

    test('the json round trip preserves createdAt', () {
      // Note: `PromptManagerPreset.fromJson` deliberately stamps `updatedAt`
      // with `DateTime.now()` (`prompt_manager.dart:856`), so only createdAt is
      // a round-trippable value here.
      final restored = PromptManagerPreset.fromJson(json());

      expect(restored.createdAt.isAtSameMomentAs(localAt()), isTrue);
    });
  });

  group('RegexProfileResource', () {
    Map<String, dynamic> json() => RegexProfileResource(
      id: 'regex-profile-1',
      name: 'Regex Profile',
      createdAt: localAt(),
      updatedAt: localAt(),
    ).toJson();

    test('a non-UTC createdAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['createdAt'], 'createdAt');
    });

    test('a non-UTC updatedAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['updatedAt'], 'updatedAt');
    });

    test('the json round trip preserves the instant', () {
      final restored = RegexProfileResource.fromJson(json());

      expect(restored.createdAt.isAtSameMomentAs(localAt()), isTrue);
      expect(restored.updatedAt.isAtSameMomentAs(localAt()), isTrue);
    });
  });

  group('RegexScript', () {
    Map<String, dynamic> json() => RegexScript(
      id: 'script-1',
      scriptName: 'Script',
      findRegex: 'a',
      replaceString: 'b',
      placement: const <RegexPlacement>[RegexPlacement.aiOutput],
      createdAt: localAt(),
      updatedAt: localAt(),
    ).toJson();

    test('a non-UTC createdAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['createdAt'], 'createdAt');
    });

    test('a non-UTC updatedAt is serialized on a UTC basis', () {
      expectUtcBasis(json()['updatedAt'], 'updatedAt');
    });

    test('the json round trip preserves the instant', () {
      final restored = RegexScript.fromJson(json());

      expect(restored.createdAt.isAtSameMomentAs(localAt()), isTrue);
      expect(restored.updatedAt.isAtSameMomentAs(localAt()), isTrue);
    });
  });

  group('SessionPromptContext.updatedAt', () {
    // `updated_at` is epoch seconds, not an ISO string. fromJson must materialize
    // it as a UTC instant, and toJson must project toUtc before emitting seconds,
    // so ordering/comparison never depends on the reader zone.
    Map<String, dynamic> json() =>
        SessionPromptContext(updatedAt: localAt()).toJson();

    test('a non-UTC updatedAt round-trips through epoch seconds as UTC', () {
      expect(json()['updated_at'], isA<int>());
      final restored = SessionPromptContext.fromJson(json());

      expect(restored.updatedAt, isNotNull);
      expect(restored.updatedAt!.isUtc, isTrue);
      expect(
        restored.updatedAt!.isAtSameMomentAs(localAt()),
        isTrue,
        reason: 'epoch-seconds round trip must preserve the instant',
      );
    });

    test('fromJson on a raw epoch-seconds int yields a UTC instant', () {
      final seconds = localAt().millisecondsSinceEpoch ~/ 1000;
      final restored = SessionPromptContext.fromJson({'updated_at': seconds});

      expect(restored.updatedAt, isNotNull);
      expect(restored.updatedAt!.isUtc, isTrue);
      expect(restored.updatedAt!.isAtSameMomentAs(localAt()), isTrue);
    });
  });

  // The two already-normalized models (`Character` in character_entities.dart,
  // `Worldbook` in worldbook_entities.dart) are NOT re-asserted here: both have
  // 16+ required constructor fields, and a fixture that large would assert more
  // about its own scaffolding than about the instant basis. Their `.toUtc()`
  // calls are verified by inspection instead
  // (`character_entities.dart:181,182,231,232`, `worldbook_entities.dart:112,113`)
  // and by the repo-wide "no bare toIso8601String in lib/" grep recorded in the
  // change log.
}
