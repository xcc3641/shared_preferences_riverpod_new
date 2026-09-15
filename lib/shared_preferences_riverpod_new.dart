/// One-liner Riverpod 3 providers backed by `SharedPreferences`.
///
/// 两种形态，按 App 的启动方式选：
///
/// - [syncPrefProvider]：`SharedPreferences` 在 `runApp` 之前就 await 好了。
///   `ref.watch(p)` 直接给 `T`，没有加载态，也就没有「加载期间读到默认值」这类问题。
/// - [prefProvider]：偏好在运行中才可能就绪，状态是 `AsyncValue<T>`。
library;

export 'src/pref_provider.dart' show PrefNotifier, PrefProvider, prefProvider;
export 'src/sync_pref_provider.dart'
    show
        SyncPrefNotifier,
        SyncPrefProvider,
        registerSyncPrefs,
        resetSyncPrefs,
        syncPrefProvider;
