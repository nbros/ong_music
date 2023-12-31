import 'dart:io';

import 'package:diacritic/diacritic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'entry.dart';
import 'options.dart';

class EntryList extends ConsumerWidget {
  final List<Entry> entries;
  final String query;
  final bool clickable;
  final String name;
  const EntryList({super.key, required this.entries, this.query = '', required this.clickable, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final dividersEnabled = ref.watch(dividersOptionProvider);
    return ListView.builder(
      primary: true,
      // use a fixed itemExtent on platforms that have a scrollbar that allows jumping around, to improve performance
      // these platforms also likely have a larger screen, so we can afford to use more horizontal space
      itemExtent: platformHasScrollbar ? (dividersEnabled ? 48 : 40) : null,
      key: PageStorageKey(name),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        return EntryTile(
          entry: entries[index],
          query: query,
          clickable: clickable,
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
    required this.clickable,
  });

  final Entry entry;
  final String query;

  // do we expect the entry to be clickable?
  // if clickable and it has no url, then it will appear grayed out
  final bool clickable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final darkMode = themeMode == ThemeMode.dark;
    final dividersEnabled = ref.watch(dividersOptionProvider);
    bool enabled = !clickable || (entry.url?.trim().isNotEmpty ?? false);
    final textStyle = enabled
        ? Theme.of(context).textTheme.bodyLarge
        : Theme.of(context).textTheme.bodyLarge!.copyWith(color: darkMode ? Colors.grey[700] : Colors.grey[500]);

    Widget titleWidget;
    if ('' == query) {
      titleWidget = Text(
        overflow: platformHasScrollbar ? TextOverflow.ellipsis : TextOverflow.clip,
        entry.title,
        style: textStyle,
      );
    } else {
      var formattedTitle = entry.title;
      final startIndex = removeDiacritics(formattedTitle.toLowerCase()).indexOf(removeDiacritics(query.toLowerCase()));
      final endIndex = startIndex + query.length;
      final beforeMatch = formattedTitle.substring(0, startIndex);
      final match = formattedTitle.substring(startIndex, endIndex);
      final afterMatch = formattedTitle.substring(endIndex);
      final Color? highlightColor = darkMode ? Colors.lime[900] : Colors.lime[100];
      titleWidget = RichText(
        overflow: platformHasScrollbar ? TextOverflow.ellipsis : TextOverflow.clip,
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

    if (platformHasScrollbar) {
      titleWidget = SizedBox(
        height: 24.0,
        child: titleWidget,
      );
    }

    Widget widget = ListTile(
      enabled: enabled,
      onTap: clickable && enabled
          ? () async {
              if (entry.url != null) {
                final url = Uri.parse(entry.url!);
                await launchUrl(url);
              }
            }
          : null,
      title: titleWidget,
    );

    if (dividersEnabled) {
      widget = Column(
        children: [
          widget,
          const Divider(height: 0),
        ],
      );
    }

    widget = Tooltip(
      message: entry.subtitle,
      textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(color: darkMode ? Colors.white : Colors.black),
      decoration: BoxDecoration(
        color: darkMode ? Colors.grey[800]!.withOpacity(0.95) : Colors.amber[100]!.withOpacity(0.95),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      waitDuration: const Duration(milliseconds: 500),
      showDuration: !kIsWeb && Platform.isAndroid ? const Duration(seconds: 8) : null,
      triggerMode: TooltipTriggerMode.longPress,
      child: widget,
    );
    return widget;
  }
}
