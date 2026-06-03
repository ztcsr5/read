class DiagnosticIssue {
  final String stage; // 'search' | 'detail' | 'toc' | 'content' | 'compatibility'
  final String? field; // 'bookList', 'name', 'author', 'bookUrl', etc.
  final String? rule; // 对应出问题的具体规则内容
  final String reason; // 问题原因
  final String suggestion; // 建议修复操作
  final String? htmlSnippet; // HTML 样例或日志片段

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

  factory DiagnosticIssue.fromJson(Map<String, dynamic> json) => DiagnosticIssue(
        stage: json['stage']?.toString() ?? '',
        field: json['field']?.toString(),
        rule: json['rule']?.toString(),
        reason: json['reason']?.toString() ?? '',
        suggestion: json['suggestion']?.toString() ?? '',
        htmlSnippet: json['htmlSnippet']?.toString(),
      );
}

class DiagnosticReport {
  final bool searchSuccess;
  final bool bookInfoSuccess;
  final bool tocSuccess;
  final bool contentSuccess;
  final int score;
  final String riskLevel; // '低' | '中' | '高'
  final List<DiagnosticIssue> issues;

  DiagnosticReport({
    required this.searchSuccess,
    required this.bookInfoSuccess,
    required this.tocSuccess,
    required this.contentSuccess,
    required this.score,
    required this.riskLevel,
    required this.issues,
  });

  Map<String, dynamic> toJson() => {
        'searchSuccess': searchSuccess,
        'bookInfoSuccess': bookInfoSuccess,
        'tocSuccess': tocSuccess,
        'contentSuccess': contentSuccess,
        'score': score,
        'riskLevel': riskLevel,
        'issues': issues.map((e) => e.toJson()).toList(),
      };

  factory DiagnosticReport.fromJson(Map<String, dynamic> json) {
    var rawIssues = json['issues'];
    List<DiagnosticIssue> issuesList = [];
    if (rawIssues is List) {
      issuesList = rawIssues.map((e) => DiagnosticIssue.fromJson(e as Map<String, dynamic>)).toList();
    }
    return DiagnosticReport(
      searchSuccess: json['searchSuccess'] == true,
      bookInfoSuccess: json['bookInfoSuccess'] == true,
      tocSuccess: json['tocSuccess'] == true,
      contentSuccess: json['contentSuccess'] == true,
      score: json['score'] is int ? json['score'] as int : 0,
      riskLevel: json['riskLevel']?.toString() ?? '低',
      issues: issuesList,
    );
  }
}
