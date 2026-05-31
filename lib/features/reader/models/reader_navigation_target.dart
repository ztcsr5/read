class ReaderNavigationTarget {
  final int chapterIndex;
  final int charOffset;

  const ReaderNavigationTarget({
    required this.chapterIndex,
    this.charOffset = 0,
  });
}
