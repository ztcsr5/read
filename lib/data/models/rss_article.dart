class RssArticle {
  final String title;
  final String link;
  final String? pubDate;
  final String? description;
  final String? coverUrl;
  
  RssArticle({
    required this.title,
    required this.link,
    this.pubDate,
    this.description,
    this.coverUrl,
  });
}
