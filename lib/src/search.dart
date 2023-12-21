import 'package:flutter/material.dart';
import 'entry.dart';
import 'entry_list.dart';

class EntrySearch extends SearchDelegate<Entry?> {
  final List<Entry> entries;

  EntrySearch(this.entries);

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
    final results = entries.where((entry) => entry.formattedTitle.toLowerCase().contains(query.toLowerCase())).toList();
    return EntryList(entries: results, query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final suggestions = entries.where((entry) => entry.formattedTitle.toLowerCase().contains(query.toLowerCase())).toList();
    return EntryList(entries: suggestions, query: query);
  }
}
