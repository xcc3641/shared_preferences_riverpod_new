# shared_preferences_riverpod_new

One line per persisted preference, on Riverpod 3.

```dart
final darkModeProvider = prefProvider<bool>('settings.dark_mode', false);
```

That's the whole declaration. Read it, await it, write it:

```dart
final isDark = ref.watch(darkModeProvider).value ?? false;  // sync-ish read
final isDark = await ref.read(darkModeProvider.future);     // first load
ref.read(darkModeProvider.notifier).set(true);              // write
```

This is a rewrite of [`shared_preferences_riverpod`][orig], which stopped at
Riverpod 2. Same idea, rebuilt on `AsyncNotifier`, no code generation, no
`hooks_riverpod` dependency.

[orig]: https://pub.dev/packages/shared_preferences_riverpod

## Why

Five preferences means five copies of the same fifteen lines: `getInstance()`
in `build`, then compare / `AsyncData` / `getInstance()` / `setX` in the
setter — differing only in key, default and type. This collapses them into one
generic notifier, and call sites read exactly like any other `AsyncNotifier`.

## Install

```yaml
dependencies:
  shared_preferences_riverpod_new: ^0.1.0
```

## Supported types

Whatever `SharedPreferences` can store: `bool`, `int`, `double`, `String`,
`List<String>`. Anything else throws `ArgumentError` on write.

A value on disk whose type no longer matches (an older release stored a
`String` where an `int` now lives) is treated as absent — you get the default
back instead of a crash.

## `normalize`: guard both ends

`normalize` runs on the value read from disk **and** on every value written.
Junk on disk can't get in, and an out-of-range new value can't get out:

```dart
final fontSizeProvider = prefProvider<int>(
  'settings.font_size',
  14,
  normalize: (v) => v.clamp(10, 24),
);
```

## Same value, no write

`set` compares against the current state first. Writing the value that's
already there does nothing: no disk write, no notification.

## Preferences with behaviour

When the rule belongs to the preference rather than to its callers, subclass
`PrefNotifier` and wire it to an `AsyncNotifierProvider` yourself:

```dart
class HintShows extends PrefNotifier<int> {
  HintShows() : super('hint.shows', 0);

  static const int maxShows = 5;

  /// Whether the hint may be shown once more. Returns true after the bumped
  /// count has been persisted.
  Future<bool> tryConsume() async {
    final current = state.value ?? await future;
    if (current >= maxShows) return false;
    await set(current + 1);
    return true;
  }
}

final hintShowsProvider =
    AsyncNotifierProvider<HintShows, int>(HintShows.new, name: 'hintShows');
```

Clamping constants live with the preference the same way:

```dart
class CustomSeconds extends PrefNotifier<int> {
  CustomSeconds() : super('capture.custom_seconds', fallback, normalize: _clamp);

  static const int min = 3;
  static const int max = 10;
  static const int fallback = 5;

  static int _clamp(int seconds) => seconds.clamp(min, max);
}
```

## Injecting the store

By default every notifier calls `SharedPreferences.getInstance()`. Pass `prefs`
to point it somewhere else — a pre-warmed instance, a scoped store, a fake:

```dart
final p = prefProvider<int>('t.count', 0, prefs: () async => myPrefs);
```

It's a function, not an instance, so the provider stays lazy. There is no
global singleton to set up or tear down.

## Testing

`SharedPreferences.setMockInitialValues` works as usual:

```dart
setUp(() => SharedPreferences.setMockInitialValues({}));

test('cold start reads the stored value back', () async {
  SharedPreferences.setMockInitialValues({'t.count': 7});
  final p = prefProvider<int>('t.count', 0);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  expect(await container.read(p.future), 7);
});
```

## Notes

- Providers are kept alive, not auto-disposed. A user preference has no
  business being forgotten because nothing is watching it this second.
- No code generation. `prefProvider` is a generic factory, and `@Riverpod`
  can't generate a generic notifier.
- The package depends on `riverpod`, not `hooks_riverpod` — bring your own
  binding layer (`flutter_riverpod`, `hooks_riverpod`, whichever).

## License

MIT
