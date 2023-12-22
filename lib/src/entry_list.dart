import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'entry.dart';
import 'options.dart';

class EntryList extends ConsumerWidget {
  final List<Entry> entries;
  final String query;
//
  const EntryList({super.key, required this.entries, this.query = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var expand = ref.watch(expandOptionProvider);
    ref.watch(themeProvider);
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final darkMode = Theme.of(context).brightness == Brightness.dark;
        final entry = entries[index];
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

        final listTile = ListTile(
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

        final dividersEnabled = ref.watch(dividersOptionProvider);
        if (dividersEnabled) {
          return Column(
            children: [
              listTile,
              const Divider(height: 0),
            ],
          );
        }

        if (expand) {
          return listTile;
        } else {
          return Tooltip(
            message: entry.formattedSubtitle,
            waitDuration: const Duration(milliseconds: 500),
            child: listTile,
          );
        }
      },
    );
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
