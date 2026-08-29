import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the [SharedPreferences] instance a [PrefNotifier] should work against.
///
/// Defaults to [SharedPreferences.getInstance]. Override it to inject a fake in
/// tests, or to hand out a scoped/pre-warmed instance in an app.
typedef PrefsReader = Future<SharedPreferences> Function();

/// The provider type returned by [prefProvider].
///
/// Spelled out so call sites can annotate fields without repeating the generic
/// pair: `final PrefProvider<bool> darkModeProvider = prefProvider(...)`.
typedef PrefProvider<T> = AsyncNotifierProvider<PrefNotifier<T>, T>;

/// Declares a preference that lives in [SharedPreferences], in one line.
///
/// ```dart
/// final darkModeProvider = prefProvider<bool>('settings.dark_mode', false);
///
/// // read   : ref.watch(darkModeProvider).value ?? false
/// // await  : await ref.read(darkModeProvider.future)
/// // write  : ref.read(darkModeProvider.notifier).set(true)
/// ```
///
/// [T] must be a type `SharedPreferences` can store: `bool`, `int`, `double`,
/// `String` or `List<String>`. Anything else throws [ArgumentError] on write.
///
/// [normalize] runs on both ends — on the value read from disk and on every
/// value written. A stale or out-of-range value on disk can't get in, and an
/// out-of-range new value can't get out:
///
/// ```dart
/// final fontSizeProvider = prefProvider<int>(
///   'settings.font_size',
///   14,
///   normalize: (v) => v.clamp(10, 24),
/// );
/// ```
///
/// [prefs] overrides where the preferences come from; it defaults to
/// [SharedPreferences.getInstance]. It is a function, not an instance, so the
/// provider stays lazy and a test can swap the backing store between reads.
///
/// The provider is kept alive (not auto-disposed): a user preference has no
/// business being forgotten because nothing is watching it right now.
///
/// When a preference needs behaviour of its own ("show this hint at most five
/// times"), subclass [PrefNotifier] and wire it up with an
/// [AsyncNotifierProvider] directly.
PrefProvider<T> prefProvider<T>(
  String key,
  T defaultValue, {
  T Function(T value)? normalize,
  PrefsReader? prefs,
}) =>
    AsyncNotifierProvider<PrefNotifier<T>, T>(
      () => PrefNotifier<T>(key, defaultValue,
          normalize: normalize, prefs: prefs),
      name: key,
    );

/// The [AsyncNotifier] behind a single [SharedPreferences] key.
///
/// Usually created for you by [prefProvider]. Subclass it when the preference
/// owns a rule that callers shouldn't have to re-implement:
///
/// ```dart
/// class HintShows extends PrefNotifier<int> {
///   HintShows() : super('hint.shows', 0);
///
///   static const int maxShows = 5;
///
///   /// Whether the hint may be shown once more. Returns true after the
///   /// bumped count has been persisted.
///   Future<bool> tryConsume() async {
///     final current = state.value ?? await future;
///     if (current >= maxShows) return false;
///     await set(current + 1);
///     return true;
///   }
/// }
///
/// final hintShowsProvider =
///     AsyncNotifierProvider<HintShows, int>(HintShows.new, name: 'hintShows');
/// ```
class PrefNotifier<T> extends AsyncNotifier<T> {
  /// Creates a notifier for [key], falling back to [defaultValue] when nothing
  /// usable is stored. See [prefProvider] for [normalize] and [prefs].
  PrefNotifier(
    this.key,
    this.defaultValue, {
    T Function(T value)? normalize,
    PrefsReader? prefs,
  })  : _normalize = normalize,
        _prefs = prefs ?? SharedPreferences.getInstance;

  /// The `SharedPreferences` key this notifier owns.
  final String key;

  /// Returned when [key] holds nothing, or holds a value of the wrong type.
  final T defaultValue;

  final T Function(T value)? _normalize;
  final PrefsReader _prefs;

  T _norm(T value) => _normalize?.call(value) ?? value;

  @override
  Future<T> build() async {
    final prefs = await _prefs();
    return _norm(readPref<T>(prefs, key) ?? defaultValue);
  }

  /// Publishes [value] to the state immediately, then persists it.
  ///
  /// Writing the value already in state is a no-op — no disk write, no
  /// notification.
  Future<void> set(T value) async {
    final next = _norm(value);
    if (next == state.value) return;
    state = AsyncData(next);
    final prefs = await _prefs();
    await writePref(prefs, key, next);
  }

  /// The stored value, or `null` when [key] is empty or holds another type
  /// (e.g. an older release stored a `String` where an `int` now lives).
  static T? readPref<T>(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    return raw is T ? raw : null;
  }

  /// Stores [value] under [key], dispatching to the right `setX` call.
  ///
  /// Throws [ArgumentError] for a type `SharedPreferences` cannot store.
  static Future<void> writePref<T>(
    SharedPreferences prefs,
    String key,
    T value,
  ) =>
      switch (value) {
        bool v => prefs.setBool(key, v),
        int v => prefs.setInt(key, v),
        double v => prefs.setDouble(key, v),
        String v => prefs.setString(key, v),
        List<String> v => prefs.setStringList(key, v),
        _ => throw ArgumentError.value(
            value,
            'value',
            'SharedPreferences only stores bool / int / double / String / List<String>',
          ),
      };
}
