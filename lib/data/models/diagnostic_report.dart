class DiagnosticIssue {
  final String stage; // search | detail | toc | content | compatibility
  final String? field; // bookList, name, author, bookUrl, etc.
  final String? rule;
  final String reason;
  final String suggestion;
  final String? htmlSnippet;

  DiagnosticIssue({
    required this.stage,
    this.field,
    this.rule,
    required this.reason,
    required this.suggestion,
    this.htmlSnippet,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'field': field,
    'rule': rule,
    'reason': reason,
    'suggestion': suggestion,
    'htmlSnippet': htmlSnippet,
  };

  factory DiagnosticIssue.fromJson(Map<String, dynamic> json) =>
      DiagnosticIssue(
        stage: json['stage']?.toString() ?? '',
        field: json['field']?.toString(),
        rule: json['rule']?.toString(),
        reason: json['reason']?.toString() ?? '',
        suggestion: json['suggestion']?.toString() ?? '',
        htmlSnippet: json['htmlSnippet']?.toString(),
      );
}

class DiagnosticStageSummary {
  final String stage;
  final String status; // ok | fail | skip | warning
  final String title;
  final String message;
  final String? field;

  const DiagnosticStageSummary({
    required this.stage,
    required this.status,
    required this.title,
    required this.message,
    this.field,
  });

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'status': status,
    'title': title,
    'message': message,
    'field': field,
  };

  factory DiagnosticStageSummary.fromJson(Map<String, dynamic> json) =>
      DiagnosticStageSummary(
        stage: json['stage']?.toString() ?? '',
        status: json['status']?.toString() ?? 'warning',
        title: json['title']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        field: json['field']?.toString(),
      );
}

class DiagnosticReport {
  final bool searchSuccess;
  final bool bookInfoSuccess;
  final bool tocSuccess;
  final bool contentSuccess;
  final int score;
  final String riskLevel; // low | medium | high, or legacy localized text
  final List<DiagnosticIssue> issues;
  final String primaryFailureStage;
  final String nextAction;
  final List<DiagnosticStageSummary> stageSummaries;

  DiagnosticReport({
    required this.searchSuccess,
    required this.bookInfoSuccess,
    required this.tocSuccess,
    required this.contentSuccess,
    required this.score,
    required this.riskLevel,
    required this.issues,
    String? primaryFailureStage,
    String? nextAction,
    List<DiagnosticStageSummary>? stageSummaries,
  }) : primaryFailureStage =
           primaryFailureStage ??
           _inferPrimaryFailureStage(
             searchSuccess: searchSuccess,
             bookInfoSuccess: bookInfoSuccess,
             tocSuccess: tocSuccess,
             contentSuccess: contentSuccess,
             issues: issues,
           ),
       nextAction =
           nextAction ??
           _inferNextAction(
             searchSuccess: searchSuccess,
             bookInfoSuccess: bookInfoSuccess,
             tocSuccess: tocSuccess,
             contentSuccess: contentSuccess,
             issues: issues,
           ),
       stageSummaries =
           stageSummaries ??
           _defaultStageSummaries(
             searchSuccess: searchSuccess,
             bookInfoSuccess: bookInfoSuccess,
             tocSuccess: tocSuccess,
             contentSuccess: contentSuccess,
             issues: issues,
           );

  Map<String, dynamic> toJson() => {
    'searchSuccess': searchSuccess,
    'bookInfoSuccess': bookInfoSuccess,
    'tocSuccess': tocSuccess,
    'contentSuccess': contentSuccess,
    'score': score,
    'riskLevel': riskLevel,
    'issues': issues.map((e) => e.toJson()).toList(),
    'primaryFailureStage': primaryFailureStage,
    'nextAction': nextAction,
    'stageSummaries': stageSummaries.map((e) => e.toJson()).toList(),
  };

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) {
    final rawIssues = json['issues'];
    var issuesList = <DiagnosticIssue>[];
    if (rawIssues is List) {
      issuesList = rawIssues
          .whereType<Map>()
          .map((e) => DiagnosticIssue.fromJson(e.cast<String, dynamic>()))
          .toList();
    }

    final rawStageSummaries = json['stageSummaries'];
    List<DiagnosticStageSummary>? stageSummaries;
    if (rawStageSummaries is List) {
      stageSummaries = rawStageSummaries
          .whereType<Map>()
          .map(
            (e) => DiagnosticStageSummary.fromJson(e.cast<String, dynamic>()),
          )
          .toList();
    }

    return DiagnosticReport(
      searchSuccess: json['searchSuccess'] == true,
      bookInfoSuccess: json['bookInfoSuccess'] == true,
      tocSuccess: json['tocSuccess'] == true,
      contentSuccess: json['contentSuccess'] == true,
      score: json['score'] is int ? json['score'] as int : 0,
      riskLevel: json['riskLevel']?.toString() ?? 'low',
      issues: issuesList,
      primaryFailureStage: json['primaryFailureStage']?.toString(),
      nextAction: json['nextAction']?.toString(),
      stageSummaries: stageSummaries,
    );
  }

  static String _inferPrimaryFailureStage({
    required bool searchSuccess,
    required bool bookInfoSuccess,
    required bool tocSuccess,
    required bool contentSuccess,
    required List<DiagnosticIssue> issues,
  }) {
    if (!searchSuccess) return 'search';
    if (!bookInfoSuccess) return 'detail';
    if (!tocSuccess) return 'toc';
    if (!contentSuccess) return 'content';
    if (issues.any((issue) => issue.stage == 'compatibility')) {
      return 'compatibility';
    }
    return 'none';
  }

  static String _inferNextAction({
    required bool searchSuccess,
    required bool bookInfoSuccess,
    required bool tocSuccess,
    required bool contentSuccess,
    required List<DiagnosticIssue> issues,
  }) {
    final firstIssue = issues.isEmpty ? null : issues.first;
    if (!searchSuccess) {
      return firstIssue?.suggestion ??
          'Check searchUrl and ruleSearch.bookList/name/bookUrl.';
    }
    if (!bookInfoSuccess) {
      return firstIssue?.suggestion ??
          'Check detail page URL and ruleBookInfo.';
    }
    if (!tocSuccess) {
      return firstIssue?.suggestion ??
          'Check ruleSearch.bookUrl, ruleBookInfo.tocUrl and ruleToc.chapterList.';
    }
    if (!contentSuccess) {
      return firstIssue?.suggestion ?? 'Check ruleContent.content.';
    }
    if (issues.isNotEmpty) {
      return firstIssue!.suggestion;
    }
    return 'No blocking issue detected.';
  }

  static List<DiagnosticStageSummary> _defaultStageSummaries({
    required bool searchSuccess,
    required bool bookInfoSuccess,
    required bool tocSuccess,
    required bool contentSuccess,
    required List<DiagnosticIssue> issues,
  }) {
    DiagnosticStageSummary make(
      String stage,
      String title,
      bool success,
      String okMessage,
    ) {
      final issue = issues.where((item) => item.stage == stage).firstOrNull;
      return DiagnosticStageSummary(
        stage: stage,
        status: success ? 'ok' : 'fail',
        title: title,
        message: success ? okMessage : (issue?.reason ?? 'Stage failed.'),
        field: issue?.field,
      );
    }

    return [
      make(
        'search',
        'Search',
        searchSuccess,
        'Search parsed at least one book.',
      ),
      make(
        'detail',
        'Book detail',
        bookInfoSuccess,
        'Book detail stage passed or was not required.',
      ),
      make('toc', 'Table of contents', tocSuccess, 'TOC parsed chapters.'),
      make('content', 'Content', contentSuccess, 'Content parsed text.'),
    ];
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
