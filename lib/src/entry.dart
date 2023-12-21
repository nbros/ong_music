class Entry {
  final String uploadDate;
  final int? seq;
  final String videoTitle;
  final String genre;
  final String videoLink;
  final String shortVideoOrRequestor;
  final String originalHighlight;
  final String additionalNotes;

  Entry({
    required this.uploadDate,
    required this.seq,
    required this.videoTitle,
    required this.genre,
    required this.videoLink,
    required this.shortVideoOrRequestor,
    required this.originalHighlight,
    required this.additionalNotes,
  });

  @override
  String toString() {
    return 'Entry{ '
        'uploadDate: $uploadDate, '
        'seq: $seq, '
        'videoTitle: $videoTitle, '
        'genre: $genre, '
        'videoLink: $videoLink, '
        'shortVideoOrRequestor: $shortVideoOrRequestor, '
        'originalHighlight: $originalHighlight, '
        'additionalNotes: $additionalNotes'
        ' }';
  }
}
