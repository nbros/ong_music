class Entry {
  final String uploadDate;
  final int? seq;
  final String videoTitle;
  final String genre;
  final String videoLink;
  final String shortVideoOrRequestor;
  final String originalHighlight;
  final String additionalNotes;
  String? _formattedTitle;
  String? _formattedSubtitle;

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

  String get requestor => shortVideoOrRequestor.startsWith('http') ? '' : shortVideoOrRequestor;

  String get formattedTitle {
    if (_formattedTitle == null) {
      final genreStr = genre.trim().isEmpty ? '' : ' • $genre';
      final date = originalHighlight.trim().isEmpty ? '' : ' - $originalHighlight';
      final requestor = this.requestor.isEmpty ? '' : " [${this.requestor}]";
      final title = videoTitle.trim();
      _formattedTitle = "$seq$date - $title$genreStr$requestor";
    }
    return _formattedTitle!;
  }

  String get formattedSubtitle {
    if (_formattedSubtitle == null) {
      final uploadDateStr = uploadDate.trim().isEmpty ? '' : ' (uploaded on $uploadDate)';
      final notes = additionalNotes.trim().isEmpty ? '' : additionalNotes;
      final requestor = this.requestor.isEmpty ? '' : "[${this.requestor}] ";
      _formattedSubtitle = "$requestor$notes$uploadDateStr";
    }
    return _formattedSubtitle!;
  }

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
