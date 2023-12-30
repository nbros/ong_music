import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'entry.dart';
import 'entry_list.dart';

class EntrySearch extends SearchDelegate<Entry?> {
  final List<Entry> entries;
  final bool clickable;
  final String name;

  EntrySearch({required this.entries, required this.clickable, required this.name});

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
    final searched = removeDiacritics(query.toLowerCase());
    final results = entries.where((entry) => removeDiacritics(entry.title.toLowerCase()).contains(searched)).toList();
    return EntryList(
      entries: results,
      query: query,
      clickable: clickable,
      name: name,
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final searched = removeDiacritics(query.toLowerCase());
    final suggestions = entries.where((entry) => removeDiacritics(entry.title.toLowerCase()).contains(searched)).toList();
    return Column(
      children: [
        if (searched.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Number of matches:'),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(
                        suggestions.length.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: EntryList(
            entries: suggestions,
            query: query,
            clickable: clickable,
            name: name,
          ),
        ),
      ],
    );
  }
}
