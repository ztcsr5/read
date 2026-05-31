class SourceImportLinkParser {
  static SourceImportInput parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return const SourceImportInput.empty();
    if (_looksLikeJson(text)) return SourceImportInput.json(text);

    final directUri = Uri.tryParse(text);
    final direct = _fromUri(directUri);
    if (direct != null) return direct;

    final embeddedUrl =
        _firstUrl(text) ?? _firstUrl(text.replaceAll(r'\/', '/'));
    if (embeddedUrl != null) {
      final uri = Uri.tryParse(embeddedUrl);
      final parsed = _fromUri(uri);
      if (parsed != null) return parsed;
    }

    return SourceImportInput.unknown(text);
  }

  static SourceImportInput? _fromUri(Uri? uri) {
    if (uri == null || !uri.hasScheme) return null;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return SourceImportInput.url(_trimUrl(uri.toString()));
    }

    final src = _firstQueryValue(uri, const [
      'src',
      'url',
      'source',
      'sourceUrl',
      'bookSourceUrl',
      'rssSourceUrl',
    ]);
    if (src != null && src.trim().isNotEmpty) {
      final decoded = _safeDecode(src.trim());
      final nested = parse(decoded);
      if (!nested.isEmpty && !nested.isUnknown) return nested;
      return SourceImportInput.url(decoded);
    }

    final text = uri.toString();
    if (text.contains('booksource') ||
        text.contains('book-source') ||
        text.contains('rsssource')) {
      return SourceImportInput.unsupportedScheme(text);
    }
    return null;
  }

  static String? _firstQueryValue(Uri uri, List<String> keys) {
    try {
      for (final key in keys) {
        final value = uri.queryParameters[key];
        if (value != null && value.trim().isNotEmpty) return value;
      }
    } on FormatException {
      final rawQuery = uri.query;
      for (final key in keys) {
        final match = RegExp('(?:^|&)$key=([^&]+)').firstMatch(rawQuery);
        final value = match?.group(1);
        if (value != null && value.trim().isNotEmpty) return value;
      }
    }
    return null;
  }

  static String _safeDecode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  static String? _firstUrl(String text) {
    final match = RegExp(
      r'''(https?://[^\s'"<>]+|[a-zA-Z][a-zA-Z0-9+.-]*://[^\s'"<>]+)''',
    ).firstMatch(text);
    final url = match?.group(0);
    if (url == null) return null;
    return _trimUrl(url);
  }

  static String _trimUrl(String url) {
    return url.replaceFirst(
      RegExp(
        r'(%EF%BC%89|%EF%BC%8C|%E3%80%82|%EF%BC%9B|[),，。；;])+$',
        caseSensitive: false,
      ),
      '',
    );
  }

  static bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }
}

class SourceImportInput {
  final SourceImportInputKind kind;
  final String value;

  const SourceImportInput._(this.kind, this.value);

  const SourceImportInput.empty() : this._(SourceImportInputKind.empty, '');

  const SourceImportInput.json(String value)
    : this._(SourceImportInputKind.json, value);

  const SourceImportInput.url(String value)
    : this._(SourceImportInputKind.url, value);

  const SourceImportInput.unsupportedScheme(String value)
    : this._(SourceImportInputKind.unsupportedScheme, value);

  const SourceImportInput.unknown(String value)
    : this._(SourceImportInputKind.unknown, value);

  bool get isEmpty => kind == SourceImportInputKind.empty;
  bool get isUnknown => kind == SourceImportInputKind.unknown;
}

enum SourceImportInputKind { empty, json, url, unsupportedScheme, unknown }
