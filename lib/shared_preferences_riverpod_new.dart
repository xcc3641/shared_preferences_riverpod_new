/// One-liner Riverpod 3 providers backed by `SharedPreferences`.
///
/// See [prefProvider] to declare a persisted preference in a single line, and
/// [PrefNotifier] to subclass when a preference needs its own business methods.
library;

export 'src/pref_provider.dart' show PrefNotifier, PrefProvider, prefProvider;
