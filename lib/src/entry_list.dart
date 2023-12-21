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
    return ListView.builder(
      //padding: const EdgeInsets.all(0),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final genre = entry.genre.trim().isEmpty ? '' : ' • ${entry.genre}';
        final date = entry.originalHighlight.trim().isEmpty ? '' : ' - ${entry.originalHighlight}';
        final uploadDate = entry.uploadDate.trim().isEmpty ? '' : ' (uploaded on ${entry.uploadDate})';
        final shortVideoOrRequestor = entry.shortVideoOrRequestor.trim();
        final requestor = shortVideoOrRequestor.isEmpty || shortVideoOrRequestor.startsWith('http') ? '' : "[$shortVideoOrRequestor]";
        final notes = entry.additionalNotes.trim().isEmpty ? '' : ' ${entry.additionalNotes}';
        final title = entry.videoTitle.trim();
        final seq = entry.seq;
        final formattedTitle = "$seq$date - $title$genre";

        Widget titleWidget;
        if ('' == query) {
          titleWidget = Text(formattedTitle);
        } else {
          final startIndex = title.toLowerCase().indexOf(query.toLowerCase());
          final endIndex = startIndex + query.length;
          final beforeMatch = title.substring(0, startIndex);
          final match = title.substring(startIndex, endIndex);
          final afterMatch = title.substring(endIndex);
          final Color? highlightColor = Theme.of(context).brightness == Brightness.dark ? Colors.lime[900] : Colors.lime[100];
          titleWidget = RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: <TextSpan>[
                TextSpan(text: seq?.toString()),
                TextSpan(text: date),
                const TextSpan(text: " - "),
                TextSpan(text: beforeMatch),
                TextSpan(text: match, style: TextStyle(backgroundColor: highlightColor)),
                TextSpan(text: afterMatch),
                TextSpan(text: genre),
              ],
            ),
          );

          // final titleParts = formattedTitle.splitMapJoin(
          //   RegExp(RegExp.escape(query), caseSensitive: false),
          //   onMatch: (m) => m.group(0)!,
          //   onNonMatch: (n) => n,
          // );

          // final titleParts = formattedTitle.split(RegExp('(${RegExp.escape(query)})', caseSensitive: false));
          // final titleSpans = titleParts.map((part) {
          //   return part.toLowerCase() == query.toLowerCase()
          //       ? TextSpan(text: part, style: const TextStyle(backgroundColor: Colors.yellow))
          //       : TextSpan(text: part);
          // }).toList();
          // final titleSpans = titleParts.map((part) {
          //   return TextSpan(
          //     text: part,
          //     style: part.toLowerCase() == query.toLowerCase() ? const TextStyle(backgroundColor: Colors.yellow) : null,
          //   );
          // }).toList();
          // titleWidget = RichText(text: TextSpan(style: DefaultTextStyle.of(context).style, children: titleSpans));
        }

        return ListTile(
          onTap: () async {
            final url = Uri.parse(entry.videoLink);
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            } else {
              throw 'Could not launch $url';
            }
          },
          //isThreeLine: expand,
          // horizontalTitleGap: 0,
          // minVerticalPadding: 1,
          // minLeadingWidth: 0,
          // contentPadding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          // visualDensity: VisualDensity.compact,
          title: titleWidget,
          subtitle: expand ? Text("$requestor$notes$uploadDate") : null,
        );
      },
    );
  }
}
