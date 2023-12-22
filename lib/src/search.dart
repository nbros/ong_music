import 'package:flutter/material.dart';
import 'entry.dart';
import 'entry_list.dart';

class EntrySearch extends SearchDelegate<Entry?> {
  final List<Entry> entries;
  final bool clickable;

  EntrySearch({required this.entries, required this.clickable});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: AnimatedIcon(
        icon: AnimatedIcons.menu_arrow,
        progress: transitionAnimation,
      ),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final searched = query.toLowerCase();
    final results = entries.where((entry) => entry.title.toLowerCase().contains(searched)).toList();
    return EntryList(entries: results, query: query, clickable: clickable);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final searched = query.toLowerCase();
    final suggestions = entries.where((entry) => entry.title.toLowerCase().contains(searched)).toList();
    return Column(
      children: [
        Expanded(
          child: EntryList(entries: suggestions, query: query, clickable: clickable),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Number of matches: ${suggestions.length}'),
        ),
      ],
    );
  }
}
