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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('falls back to the default; set publishes then persists', () async {
    final p = prefProvider<bool>('t.flag', false);
    final c = container();
    expect(await c.read(p.future), isFalse);

    await c.read(p.notifier).set(true);
    expect(c.read(p).value, isTrue);
    expect((await SharedPreferences.getInstance()).getBool('t.flag'), isTrue);
  });

  test('cold start reads the stored value back', () async {
    SharedPreferences.setMockInitialValues({'t.count': 7});
    final p = prefProvider<int>('t.count', 0);
    expect(await container().read(p.future), 7);
  });

  test('a stored value of the wrong type is ignored', () async {
    SharedPreferences.setMockInitialValues({'t.count': 'seven'});
    final p = prefProvider<int>('t.count', 3);
    expect(await container().read(p.future), 3);
  });

  test('normalize clamps on both ends: read and write', () async {
    SharedPreferences.setMockInitialValues({'t.sec': 99});
    final p = prefProvider<int>('t.sec', 5, normalize: (v) => v.clamp(3, 10));
    final c = container();
    expect(await c.read(p.future), 10);

    await c.read(p.notifier).set(1);
    expect(c.read(p).value, 3);
    expect((await SharedPreferences.getInstance()).getInt('t.sec'), 3);
  });

  test('writing the current value does not touch the disk', () async {
    SharedPreferences.setMockInitialValues({'t.name': 'a'});
    final p = prefProvider<String>('t.name', '');
    final c = container();
    await c.read(p.future);
    // Swap in a blank store: a real write would put 'a' back.
    SharedPreferences.setMockInitialValues({});
    await c.read(p.notifier).set('a');
    expect((await SharedPreferences.getInstance()).getString('t.name'), isNull);
  });

  test('all five storable types round-trip', () async {
    final prefs = await SharedPreferences.getInstance();
    await PrefNotifier.writePref(prefs, 'b', true);
    await PrefNotifier.writePref(prefs, 'i', 1);
    await PrefNotifier.writePref(prefs, 'd', 1.5);
    await PrefNotifier.writePref(prefs, 's', 'x');
    await PrefNotifier.writePref(prefs, 'l', ['x', 'y']);
    expect(PrefNotifier.readPref<bool>(prefs, 'b'), isTrue);
    expect(PrefNotifier.readPref<int>(prefs, 'i'), 1);
    expect(PrefNotifier.readPref<double>(prefs, 'd'), 1.5);
    expect(PrefNotifier.readPref<String>(prefs, 's'), 'x');
    expect(PrefNotifier.readPref<List<String>>(prefs, 'l'), ['x', 'y']);
    expect(
      () => PrefNotifier.writePref(prefs, 'bad', const Duration(seconds: 1)),
      throwsArgumentError,
    );
  });

  test('an injected reader is used instead of getInstance', () async {
    SharedPreferences.setMockInitialValues({'t.injected': 42});
    final injected = await SharedPreferences.getInstance();
    // Anything reaching for getInstance() from here on sees an empty store.
    SharedPreferences.setMockInitialValues({});

    var calls = 0;
    final p = prefProvider<int>(
      't.injected',
      0,
      prefs: () async {
        calls++;
        return injected;
      },
    );
    final c = container();
    expect(await c.read(p.future), 42);
    expect(calls, 1);

    await c.read(p.notifier).set(43);
    expect(injected.getInt('t.injected'), 43);
    expect(calls, 2);
  });

  test('a subclass can add behaviour on top of the stored value', () async {
    final c = container();
    expect(await c.read(hintShowsProvider.future), 0);

    expect(await c.read(hintShowsProvider.notifier).tryConsume(), isTrue);
    expect(await c.read(hintShowsProvider.notifier).tryConsume(), isTrue);
    expect(c.read(hintShowsProvider).value, 2);
    expect(
      (await SharedPreferences.getInstance()).getInt('t.hint_shows'),
      2,
    );

    await c.read(hintShowsProvider.notifier).set(HintShows.maxShows);
    expect(await c.read(hintShowsProvider.notifier).tryConsume(), isFalse);
  });
}

class HintShows extends PrefNotifier<int> {
  HintShows() : super('t.hint_shows', 0);

  static const int maxShows = 3;

  Future<bool> tryConsume() async {
    final current = state.value ?? await future;
    if (current >= maxShows) return false;
    await set(current + 1);
    return true;
  }
}

final hintShowsProvider = AsyncNotifierProvider<HintShows, int>(
  HintShows.new,
  name: 'hintShows',
);
