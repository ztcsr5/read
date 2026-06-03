import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';

class CompatibilityAnalyzer {
  static List<DiagnosticIssue> analyze(BookSource source) {
    final issues = <DiagnosticIssue>[];

    _analyzeRule(source.ruleSearch, 'search', issues);
    _analyzeRule(source.ruleBookInfo, 'detail', issues);
    _analyzeRule(source.ruleToc, 'toc', issues);
    _analyzeRule(source.ruleContent, 'content', issues);

    // GBK Check
    final customConfigLower = source.customConfig?.toLowerCase() ?? '';
    if (customConfigLower.contains('gbk') || customConfigLower.contains('gb2312') || customConfigLower.contains('gb18030')) {
      issues.add(DiagnosticIssue(
        stage: 'compatibility',
        field: 'charset',
        reason: '使用 GBK 系列编码格式',
        suggestion: '系统已启用底层 GBK/GB2312/GB18030 兼容，但在部分老旧网站中仍可能出现特定字符解码失败风险。建议确认是否支持 UTF-8。',
      ));
    }

    // JS rules check
    final searchUrl = source.searchUrl ?? '';
    if (searchUrl.contains('@js:') || searchUrl.contains('<js>')) {
      issues.add(DiagnosticIssue(
        stage: 'compatibility',
        field: 'searchUrl',
        rule: searchUrl,
        reason: '搜索 URL 包含 JS 逻辑',
        suggestion: 'JS 规则执行开销较大，且如果使用 java.ajax 进行二次请求，可能触发同步 JS 崩溃。',
      ));
    }

    return issues;
  }

  static void _analyzeRule(String? ruleJson, String stage, List<DiagnosticIssue> issues) {
    if (ruleJson == null || ruleJson.isEmpty) return;

    if (ruleJson.contains('java.ajax') || ruleJson.contains('java.connect') || ruleJson.contains('java.post')) {
      issues.add(DiagnosticIssue(
        stage: stage,
        reason: '使用 java.ajax / java.connect 同步网络请求',
        suggestion: '当前版本已配置 JsCompatibilityTransformer 自动升级包裹为 async/await 异步。请确保 QuickJS 的沙盒安全性。',
        rule: ruleJson,
      ));
    }

    if (ruleJson.contains('org.jsoup') || ruleJson.contains('Jsoup.parse')) {
      issues.add(DiagnosticIssue(
        stage: stage,
        reason: '使用 org.jsoup.Jsoup 等 Java API 元素',
        suggestion: 'QuickJS 模拟了基本 Jsoup 接口，但对于高级 org.jsoup 操作可能会产生执行未定义异常。',
        rule: ruleJson,
      ));
    }

    // XPath risk detector
    _detectXPathRisks(ruleJson, stage, issues);
  }

  static void _detectXPathRisks(String ruleJson, String stage, List<DiagnosticIssue> issues) {
    final hasXPathChars = ruleJson.contains('//') || ruleJson.contains('/text()') || RegExp(r'/[a-zA-Z0-9_]+/@').hasMatch(ruleJson);
    final hasXPathPrefix = ruleJson.contains('@xpath:');
    
    if (hasXPathChars && !hasXPathPrefix) {
      issues.add(DiagnosticIssue(
        stage: stage,
        reason: '检测到潜在 XPath 规则字符但未声明 @xpath: 前缀',
        suggestion: '如果该规则是 XPath，建议加上 @xpath: 前缀，以防止被引擎误判为 CSS 选择器。',
        rule: ruleJson,
      ));
    }
  }
}
