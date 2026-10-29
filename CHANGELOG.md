## 0.2.1

- 修复存进去的 `List<String>` 重启后读成默认值：从磁盘载入的字符串列表是
  `List<Object?>`，原先的类型判断恒为 false。同步版和异步版都受影响。

## 0.2.0

- 新增 `syncPrefProvider<T>(key, defaultValue)`，同步版：`ref.watch(p)` 直接给 `T`，
  没有 `AsyncValue`。给「`runApp` 之前已经 await 过 `SharedPreferences.getInstance()`」
  的 App 用。
- 新增 `registerSyncPrefs(prefs)` 注册全局实例，省得每个 provider 都传一遍。
- 新增 `SyncPrefNotifier<T>`，需要给某个偏好加业务方法时继承它。

为什么加这个：异步版的 `AsyncLoading` 期间，`ref.watch(p).value ?? 默认值` 这种惯用
写法给出的是默认值——不是 null，是一个看起来完全合理的错值，调用方分辨不了。在回调里
一次性 `ref.read(p)` 而该 provider 又没被 watch 过时更明显，拿到的一定是默认值。偏好在
`runApp` 之前就已就绪的 App 里，这个加载态建模的是一个不存在的问题。同步版一次读完，只
有一个状态，这类问题在类型层面就不存在。

异步版 `prefProvider` 不变，偏好在运行中才可能就绪的场景继续用它。

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
