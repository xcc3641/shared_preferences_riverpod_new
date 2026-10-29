import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pref_provider.dart';

SharedPreferences? _registered;

/// 注册一个已经加载完成的 [SharedPreferences]，供 [syncPrefProvider] 默认使用。
///
/// 在 `runApp` 之前调一次：
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   registerSyncPrefs(await SharedPreferences.getInstance());
///   runApp(const MyApp());
/// }
/// ```
void registerSyncPrefs(SharedPreferences prefs) => _registered = prefs;

/// 清掉已注册的实例，测试用。
void resetSyncPrefs() => _registered = null;

/// [syncPrefProvider] 返回的 provider 类型。
typedef SyncPrefProvider<T> = NotifierProvider<SyncPrefNotifier<T>, T>;

/// 同步版的偏好 provider：`ref.watch(p)` 直接给 `T`，没有 [AsyncValue]。
///
/// 什么时候用它而不是 [prefProvider]：**App 在 `runApp` 之前已经 await 过
/// `SharedPreferences.getInstance()`**。这种情况下值早就在内存里了，异步建模的是
/// 一个不存在的问题，代价却是真的：
///
/// - 每个读取点都要写 `.value ?? 默认值`，而 `AsyncLoading` 期间这个表达式
///   悄悄给出默认值——不是 null，是一个看起来完全合理的错值，调用方分辨不了。
/// - 在回调里一次性 `ref.read(p)` 而该 provider 又没被 watch 过时，拿到的
///   一定是默认值。
///
/// 同步版一次读完，只有一个状态，上面两类问题在类型层面就不存在。
///
/// [prefs] 不传就用 [registerSyncPrefs] 注册过的实例；两者都没有会抛
/// [StateError]，而不是悄悄退回默认值。
SyncPrefProvider<T> syncPrefProvider<T>(
  String key,
  T defaultValue, {
  SharedPreferences Function()? prefs,
  T Function(T value)? normalize,
}) {
  PrefNotifier.checkStorable<T>();
  return NotifierProvider<SyncPrefNotifier<T>, T>(
    () => SyncPrefNotifier<T>(
      key,
      defaultValue,
      prefs: prefs,
      normalize: normalize,
    ),
    name: key,
  );
}

/// [syncPrefProvider] 背后的 notifier。需要给某个偏好加业务方法时继承它。
class SyncPrefNotifier<T> extends Notifier<T> {
  /// 见 [syncPrefProvider]。
  SyncPrefNotifier(
    this.key,
    this.defaultValue, {
    SharedPreferences Function()? prefs,
    T Function(T value)? normalize,
  })  : _prefs = prefs,
        _normalize = normalize;

  /// 这个 notifier 负责的 `SharedPreferences` 键。
  final String key;

  /// 键为空、或存着别的类型时的兜底值。
  final T defaultValue;

  final SharedPreferences Function()? _prefs;
  final T Function(T value)? _normalize;

  SharedPreferences get _store {
    final p = _prefs?.call() ?? _registered;
    if (p == null) {
      throw StateError(
        'syncPrefProvider("$key") 拿不到 SharedPreferences：'
        '要么在 runApp 之前调 registerSyncPrefs()，要么给这个 provider 传 prefs。',
      );
    }
    return p;
  }

  T _norm(T value) => _normalize?.call(value) ?? value;

  @override
  T build() => _norm(PrefNotifier.readPref<T>(_store, key) ?? defaultValue);

  /// 先更新 state（同步可见），再落盘。
  ///
  /// 写入和 state 里已有的值相同时整个跳过：不写盘，也不通知。
  Future<void> set(T value) async {
    final next = _norm(value);
    if (next == state) return;
    state = next;
    await PrefNotifier.writePref(_store, key, next);
  }
}
