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
/// `String` or `List<String>`. Anything else throws [ArgumentError] right here,
/// when the provider is declared — not later on the first write.
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
}) {
  PrefNotifier.checkStorable<T>();
  return AsyncNotifierProvider<PrefNotifier<T>, T>(
    () =>
        PrefNotifier<T>(key, defaultValue, normalize: normalize, prefs: prefs),
    name: key,
  );
}

/// The types `SharedPreferences` can store. [PrefNotifier.readPref] and
/// [PrefNotifier.writePref] both dispatch on this, so whatever can be written
/// can also be read back.
enum _Storable { boolean, integer, decimal, string, stringList }

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

  /// Throws [ArgumentError] unless [T] is one of the five types
  /// `SharedPreferences` can store. The provider factories call it up front so
  /// a bad type fails where it is declared.
  static void checkStorable<T>() => _storableOf<T>();

  static _Storable _storableOf<T>() => switch (T) {
        const (bool) => _Storable.boolean,
        const (int) => _Storable.integer,
        const (double) => _Storable.decimal,
        const (String) => _Storable.string,
        const (List<String>) => _Storable.stringList,
        _ => throw ArgumentError(
            'SharedPreferences only stores bool / int / double / String / '
            'List<String>, not $T',
          ),
      };

  /// The stored value, or `null` when [key] is empty or holds another type
  /// (e.g. an older release stored a `String` where an `int` now lives).
  static T? readPref<T>(SharedPreferences prefs, String key) {
    final raw = prefs.get(key);
    final Object? value = switch (_storableOf<T>()) {
      _Storable.boolean => raw is bool ? raw : null,
      _Storable.integer => raw is int ? raw : null,
      _Storable.decimal => raw is double ? raw : null,
      _Storable.string => raw is String ? raw : null,
      // A list loaded from disk is a `List<Object?>`, never a `List<String>`:
      // check the elements, not the list's static type.
      _Storable.stringList => raw is List && raw.every((e) => e is String)
          ? List<String>.from(raw)
          : null,
    };
    return value as T?;
  }

  /// Stores [value] under [key], dispatching to the right `setX` call.
  ///
  /// Throws [ArgumentError] for a type `SharedPreferences` cannot store.
  static Future<void> writePref<T>(
    SharedPreferences prefs,
    String key,
    T value,
  ) =>
      switch (_storableOf<T>()) {
        _Storable.boolean => prefs.setBool(key, value as bool),
        _Storable.integer => prefs.setInt(key, value as int),
        _Storable.decimal => prefs.setDouble(key, value as double),
        _Storable.string => prefs.setString(key, value as String),
        _Storable.stringList => prefs.setStringList(key, value as List<String>),
      };
}
