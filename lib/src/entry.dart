class Entry {
  final int seq;
  final String title;
  final String subtitle;
  final String? url;

  Entry({required this.seq, required this.title, required this.subtitle, this.url});

  @override
  String toString() {
    return 'Entry{$title}';
  }
}
