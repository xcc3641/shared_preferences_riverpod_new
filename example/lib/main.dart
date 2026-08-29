import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences_riverpod_new/shared_preferences_riverpod_new.dart';

/// A persisted flag, in one line.
final darkModeProvider = prefProvider<bool>('settings.dark_mode', false);

/// A persisted int, clamped on both read and write.
final fontSizeProvider = prefProvider<int>(
  'settings.font_size',
  14,
  normalize: (v) => v.clamp(10, 24),
);

/// A preference that owns a rule: show the hint at most [HintShows.maxShows]
/// times, ever.
class HintShows extends PrefNotifier<int> {
  HintShows() : super('settings.hint_shows', 0);

  static const int maxShows = 3;

  /// Whether the hint may be shown once more. Returns true after the bumped
  /// count has been persisted.
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

void main() => runApp(const ProviderScope(child: ExampleApp()));

class ExampleApp extends ConsumerWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(darkModeProvider).value ?? false;
    final fontSize = ref.watch(fontSizeProvider).value ?? 14;

    return MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        appBar: AppBar(title: const Text('Preferences')),
        body: ListView(
          children: [
            SwitchListTile(
              title: const Text('Dark mode'),
              subtitle: const Text('Survives relaunch'),
              value: dark,
              onChanged: (v) => ref.read(darkModeProvider.notifier).set(v),
            ),
            ListTile(
              title: Text('Font size: $fontSize',
                  style: TextStyle(fontSize: fontSize.toDouble())),
              subtitle: const Text('Clamped to 10..24 on read and write'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () =>
                        ref.read(fontSizeProvider.notifier).set(fontSize - 2),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        ref.read(fontSizeProvider.notifier).set(fontSize + 2),
                  ),
                ],
              ),
            ),
            ListTile(
              title: Text(
                'Hint shown ${ref.watch(hintShowsProvider).value ?? 0}'
                ' / ${HintShows.maxShows} times',
              ),
              subtitle: const Text('Tap to consume one show'),
              onTap: () async {
                final allowed =
                    await ref.read(hintShowsProvider.notifier).tryConsume();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text(allowed ? 'Here is the hint' : 'No more hints'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
