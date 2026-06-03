import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';

class CompatibilityAnalyzer {
  static List<DiagnosticIssue> analyze(BookSource source) {
    final issues = <DiagnosticIssue>[];

    _analyzeText(source.searchUrl, 'search', 'searchUrl', issues);
    _analyzeText(source.ruleSearch, 'search', 'ruleSearch', issues);
    _analyzeText(source.ruleBookInfo, 'detail', 'ruleBookInfo', issues);
    _analyzeText(source.ruleToc, 'toc', 'ruleToc', issues);
    _analyzeText(source.ruleContent, 'content', 'ruleContent', issues);
    _analyzeText(source.customConfig, 'compatibility', 'customConfig', issues);

    return _dedupe(issues);
  }

  static void _analyzeText(
    String? text,
    String stage,
    String field,
    List<DiagnosticIssue> issues,
  ) {
    if (text == null || text.trim().isEmpty) return;
    final lower = text.toLowerCase();

    if (lower.contains('gbk') ||
        lower.contains('gb2312') ||
        lower.contains('gb18030')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 GBK/GB2312/GB18030 编码依赖',
          suggestion: '底层请求已统一走自动解码；如果仍为空，优先查看网络响应是否被验证页或压缩内容替代。',
        ),
      );
    }

    if (text.contains('@js:') ||
        text.contains('<js>') ||
        text.contains('@js')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 JavaScript 规则',
          suggestion:
              'QuickJS 会本地执行该规则；若规则内还有网络请求，需确认 java.ajax/java.connect 桥接是否被触发。',
        ),
      );
    }

    if (text.contains('@get:') || text.contains('@get{')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 @get 变量读取',
          suggestion: '确认前序规则是否用 @put 写入了同名变量；诊断时可查看变量链是否断开。',
        ),
      );
    }

    if (text.contains('@put:') || text.contains('@put{')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 @put 变量写入',
          suggestion: '该规则依赖跨步骤变量传递；如果后续为空，优先排查变量名和 JSON 路径。',
        ),
      );
    }

    if (RegExp(r'java\.(ajax|connect|post|startBrowser)\b').hasMatch(text)) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 java.ajax/java.connect 等网络桥接',
          suggestion:
              'JS 引擎会自动转 async/await；若站点需要签名、Cookie 或跳验证，建议配合网络调试查看请求头和响应。',
        ),
      );
    }

    if (text.contains('Jsoup.parse') ||
        text.contains('org.jsoup') ||
        text.contains('jsoup.parse')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到 Jsoup API 依赖',
          suggestion:
              '已提供轻量 Jsoup.parse/select/attr/text 兼容层；复杂 Java 对象链仍可能需要后续补齐。',
        ),
      );
    }

    if (lower.contains('cloudflare') ||
        lower.contains('cf_clearance') ||
        lower.contains('captcha') ||
        lower.contains('challenge')) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: text,
          reason: '检测到验证页或反爬关键词',
          suggestion: '请求被拦截时会进入 Cloudflare/验证队列；同一 Host 会合并验证，避免重复弹窗。',
        ),
      );
    }

    _detectXPathRisks(text, stage, field, issues);
  }

  static void _detectXPathRisks(
    String rule,
    String stage,
    String field,
    List<DiagnosticIssue> issues,
  ) {
    final hasXPathChars =
        rule.contains('//') ||
        rule.contains('/text()') ||
        RegExp(r'/[a-zA-Z0-9_]+/@').hasMatch(rule);
    final hasXPathPrefix = rule.contains('@xpath:') || rule.contains('xpath:');

    if (hasXPathChars && !hasXPathPrefix) {
      issues.add(
        DiagnosticIssue(
          stage: stage,
          field: field,
          rule: rule,
          reason: '疑似 XPath 规则未声明 @xpath 前缀',
          suggestion: '如果这是 XPath，请加上 @xpath: 前缀；否则可能被 CSS 解析器误判。',
        ),
      );
    }
  }

  static List<DiagnosticIssue> _dedupe(List<DiagnosticIssue> issues) {
    final seen = <String>{};
    final result = <DiagnosticIssue>[];
    for (final issue in issues) {
      final key =
          '${issue.stage}|${issue.field}|${issue.reason}|${issue.suggestion}';
      if (seen.add(key)) result.add(issue);
    }
    return result;
  }
}
