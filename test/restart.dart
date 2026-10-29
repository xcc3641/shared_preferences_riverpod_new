import 'package:shared_preferences/shared_preferences.dart';

/// 模拟一次重启:把已存的值按平台通道交回来的样子(列表是 `List<Object?>`)
/// 重新灌进一份新实例。直接用 setMockInitialValues 塞 `List<String>` 测不出
/// 「写得进、读不回」——那正是 0.2.0 漏掉的。
Future<SharedPreferences> restart() async {
  final before = await SharedPreferences.getInstance();
  SharedPreferences.setMockInitialValues({
    for (final key in before.getKeys())
      key: switch (before.get(key)) {
        final List<Object?> list => <Object?>[...list],
        final value => value!,
      },
  });
  return SharedPreferences.getInstance();
}
