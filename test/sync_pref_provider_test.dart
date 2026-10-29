import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_riverpod_new/shared_preferences_riverpod_new.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  late SharedPreferences prefs;

  Future<void> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    registerSyncPrefs(prefs);
  }

  setUp(() => resetSyncPrefs());
  tearDown(() => resetSyncPrefs());

  test('第一次读就是存储值，不经过默认值', () async {
    await seed({'t.flag': false});
    final p = syncPrefProvider<bool>('t.flag', true);
    final c = container();

    final seen = <bool>[];
    c.listen(p, (_, next) => seen.add(next), fireImmediately: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // 关键断言：只有一个状态，且直接是 false。异步版这里会先给出默认值 true。
    expect(seen, [false]);
  });

  test('键为空时用默认值', () async {
    await seed({});
    expect(container().read(syncPrefProvider<int>('t.count', 7)), 7);
  });

  test('存着别的类型时忽略，用默认值', () async {
    await seed({'t.count': 'seven'});
    expect(container().read(syncPrefProvider<int>('t.count', 3)), 3);
  });

  test('磁盘读回来的字符串列表(List<Object?>)照样认得', () async {
    // 平台通道载入的列表元素类型是 Object?,不是 List<String>。
    await seed({
      't.list': <Object?>['a', 'b'],
    });
    expect(
      container().read(syncPrefProvider<List<String>>('t.list', const [])),
      ['a', 'b'],
    );
  });

  test('set 先改 state 再落盘', () async {
    await seed({});
    final p = syncPrefProvider<bool>('t.flag', false);
    final c = container();

    final write = c.read(p.notifier).set(true);
    expect(c.read(p), isTrue, reason: 'state 应该同步就变了');
    await write;
    expect(prefs.getBool('t.flag'), isTrue);
  });

  test('normalize 两端都生效：读回来和写进去', () async {
    await seed({'t.sec': 99});
    final p =
        syncPrefProvider<int>('t.sec', 5, normalize: (v) => v.clamp(3, 10));
    final c = container();
    expect(c.read(p), 10);

    await c.read(p.notifier).set(1);
    expect(c.read(p), 3);
    expect(prefs.getInt('t.sec'), 3);
  });

  test('写入与当前相同的值不碰磁盘', () async {
    await seed({'t.name': 'a'});
    final p = syncPrefProvider<String>('t.name', '');
    final c = container();
    expect(c.read(p), 'a');

    // 换一份空存储：真发生写入的话 'a' 会被写回去
    SharedPreferences.setMockInitialValues({});
    registerSyncPrefs(await SharedPreferences.getInstance());
    await c.read(p.notifier).set('a');
    expect((await SharedPreferences.getInstance()).getString('t.name'), isNull);
  });

  test('没注册也没传 prefs 时抛错，而不是悄悄给默认值', () async {
    SharedPreferences.setMockInitialValues({'t.flag': false});
    final p = syncPrefProvider<bool>('t.flag', true);
    // riverpod 3 会把 provider 抛出的错包一层 ProviderException
    expect(
      () => container().read(p),
      throwsA(
        predicate(
          (e) => '$e'.contains('registerSyncPrefs'),
          '错误信息里点名 registerSyncPrefs',
        ),
      ),
    );
  });

  test('provider 自带的 prefs 覆盖全局注册的那个', () async {
    await seed({'t.flag': false});
    SharedPreferences.setMockInitialValues({'t.flag': true});
    final other = await SharedPreferences.getInstance();
    final p = syncPrefProvider<bool>('t.flag', false, prefs: () => other);
    expect(container().read(p), isTrue);
  });
}
