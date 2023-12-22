import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'entry.dart';
import 'options.dart';

class EntryList extends ConsumerWidget {
  final List<Entry> entries;
  final String query;
  const EntryList({super.key, required this.entries, this.query = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return EntryTile(
          entry: entries[index],
          query: query,
        );
      },
    );
  }
}

class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.query,
  });

  final Entry entry;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final darkMode = themeMode == ThemeMode.dark;
    final expand = ref.watch(expandOptionProvider);
    final dividersEnabled = ref.watch(dividersOptionProvider);
    final enabled = entry.videoLink.isNotEmpty;
    final textStyle = enabled
        ? Theme.of(context).textTheme.bodyLarge
        : Theme.of(context).textTheme.bodyLarge!.copyWith(color: darkMode ? Colors.grey[700] : Colors.grey[500]);

    Widget titleWidget;
    if ('' == query) {
      titleWidget = Text(entry.formattedTitle, style: textStyle);
    } else {
      var formattedTitle = entry.formattedTitle;
      final startIndex = formattedTitle.toLowerCase().indexOf(query.toLowerCase());
      final endIndex = startIndex + query.length;
      final beforeMatch = formattedTitle.substring(0, startIndex);
      final match = formattedTitle.substring(startIndex, endIndex);
      final afterMatch = formattedTitle.substring(endIndex);
      final Color? highlightColor = darkMode ? Colors.lime[900] : Colors.lime[100];
      titleWidget = RichText(
        text: TextSpan(
          style: textStyle,
          children: <TextSpan>[
            TextSpan(text: beforeMatch),
            TextSpan(text: match, style: TextStyle(backgroundColor: highlightColor)),
            TextSpan(text: afterMatch),
          ],
        ),
      );
    }

    Widget widget = ListTile(
      enabled: enabled,
      onTap: () async {
        final url = Uri.parse(entry.videoLink);
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else if (context.mounted) {
          _showErrorDialog(context, 'Could not launch URL $url');
        }
      },
      title: titleWidget,
      subtitle: expand ? Text(entry.formattedSubtitle) : null,
    );

    if (dividersEnabled) {
      widget = Column(
        children: [
          widget,
          const Divider(height: 0),
        ],
      );
    }

    if (!expand) {
      widget = Tooltip(
        message: entry.formattedSubtitle,
        textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: darkMode ? Colors.white : Colors.black),
        decoration: BoxDecoration(
          color: darkMode ? Colors.grey[800] : Colors.amber[100],
          borderRadius: BorderRadius.circular(4),
        ),
        waitDuration: const Duration(milliseconds: 500),
        child: widget,
      );
    }
    return widget;
  }
}

void _showErrorDialog(BuildContext context, String msg) {
  final alert = AlertDialog(
    title: const Text("Error"),
    content: Text(msg),
    actions: [
      TextButton(
        child: const Text("OK"),
        onPressed: () {
          Navigator.of(context).pop();
        },
      )
    ],
  );

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}
