import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'options.dart';

class SettingsDrawer extends ConsumerWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandOption = ref.watch(expandOptionProvider);
    final dividersOption = ref.watch(dividersOptionProvider);
    final themeOption = ref.watch(themeProvider);
    final darkMode = themeOption == ThemeMode.dark;
    Color textColor = darkMode ? Colors.orange[100]! : Colors.black;
    Color backColor1 = darkMode ? Colors.orange[900]! : Colors.orange[300]!;
    Color backColor2 = darkMode ? Colors.orange[500]! : Colors.orange[400]!;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.deepOrange,
              gradient: LinearGradient(colors: [backColor1, backColor2], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: Center(
              child: Text('Settings', style: Theme.of(context).textTheme.displayLarge!.copyWith(color: textColor)),
            ),
          ),
          SwitchListTile(
            title: const Text('Detailed'),
            value: expandOption,
            onChanged: (bool value) {
              ref.read(expandOptionProvider.notifier).toggle();
            },
          ),
          SwitchListTile(
            title: const Text('Dividers'),
            value: dividersOption,
            onChanged: (bool value) {
              ref.read(dividersOptionProvider.notifier).toggle();
            },
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: themeOption == ThemeMode.dark,
            onChanged: (bool value) {
              ref.read(themeProvider.notifier).themeMode = value ? ThemeMode.dark : ThemeMode.light;
            },
          ),
        ],
      ),
    );
  }
}
