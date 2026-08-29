## 0.1.0

Initial release.

- `prefProvider<T>(key, defaultValue, {normalize, prefs})` — declare a
  `SharedPreferences`-backed preference in one line, on Riverpod 3's
  `AsyncNotifier`.
- `PrefNotifier<T>` — subclass it when a preference needs its own methods.
- `normalize` runs on both ends: values read from disk and values written.
- Same-value writes are skipped entirely.
- `prefs` accepts a `Future<SharedPreferences> Function()` for injection; no
  global singleton is involved.
