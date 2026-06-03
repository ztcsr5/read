import 'dart:convert';
import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';
import '../../../data/models/source_health_record.dart';
import '../../../data/parsers/legado_parser.dart';
import 'compatibility_analyzer.dart';
import 'rule_suggest_engine.dart';
import 'redesign_detector.dart';

class SourceDiagnosticService {
  static Future<DiagnosticReport> diagnose(BookSource source, String testKeyword) async {
    final stopwatch = Stopwatch()..start();
    final report = await LegadoParser.testSource(source, testKeyword);
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMilliseconds;

    final issues = <DiagnosticIssue>[];

    bool searchSuccess = true;
    bool bookInfoSuccess = true;
    bool tocSuccess = true;
    bool contentSuccess = true;

    for (final step in report.steps) {
      if (step.status == LegadoStepStatus.fail) {
        String stage = 'compatibility';
        String? field;
        String suggestion = '请检查规则配置。';

        if (step.title.contains('搜索')) {
          searchSuccess = false;
          stage = 'search';
          field = 'bookList';
          suggestion = '搜索列表规则解析为空。建议使用【智能推荐规则】或检查选择器是否失效。';
        } else if (step.title.contains('详情') || step.title.contains('书籍详情')) {
          bookInfoSuccess = false;
          stage = 'detail';
          suggestion = '书籍详情规则解析失败。请核对详情页 URL 或 title 规则。';
        } else if (step.title.contains('目录')) {
          tocSuccess = false;
          stage = 'toc';
          field = 'chapterList';
          suggestion = '未解析出目录章节。请检查 chapterList 规则或编码是否正确。';
        } else if (step.title.contains('正文')) {
          contentSuccess = false;
          stage = 'content';
          field = 'content';
          suggestion = '章节正文解析为空。请检查 ruleContent.content 规则。';
        } else if (step.title.contains('异常')) {
          stage = 'overall';
          suggestion = '底层发起请求时出现未捕获异常，可能是连接超时、SSL 握手失败或 JS 语法错误。';
        }

        issues.add(DiagnosticIssue(
          stage: stage,
          field: field,
          rule: null,
          reason: step.message,
          suggestion: suggestion,
          htmlSnippet: step.logs.join('\n'),
        ));
      }
    }

    // Log the health record of today
    await SourceHealthRecord.logRecord(
      source.bookSourceUrl,
      searchOk: searchSuccess,
      tocOk: tocSuccess,
      contentOk: contentSuccess,
      responseTimeMs: elapsedMs,
    );

    // Run static compatibility checks
    final staticIssues = CompatibilityAnalyzer.analyze(source);
    issues.addAll(staticIssues);

    // Heuristics for rule extraction
    String getOldSelector(String? ruleJson, String fieldKey) {
      if (ruleJson == null || ruleJson.isEmpty) return '';
      try {
        final decoded = jsonDecode(ruleJson);
        if (decoded is Map) return decoded[fieldKey]?.toString() ?? '';
      } catch (_) {}
      return '';
    }

    // Dynamic checks & Redesign detection
    if (!searchSuccess) {
      try {
        final searchUrl = await LegadoParser.buildSearchUrl(source, testKeyword);
        final response = await LegadoParser.fetchHtml(source, searchUrl, keyword: testKeyword);
        final html = response.data?.toString() ?? '';
        if (html.isNotEmpty) {
          // 1. Redesign detection
          final oldSel = getOldSelector(source.ruleSearch, 'bookList');
          final redesignIssues = RedesignDetector.detect(
            source: source,
            stage: 'search',
            field: 'bookList',
            oldSelector: oldSel,
            pageHtml: html,
          );
          if (redesignIssues.isNotEmpty) {
            issues.addAll(redesignIssues);
          } else {
            // 2. Simple candidate suggestion
            final suggestions = RuleSuggestEngine.suggestBookListRules(html);
            if (suggestions.isNotEmpty) {
              issues.add(DiagnosticIssue(
                stage: 'search',
                field: 'bookList',
                reason: '搜索结果为空：推荐候补 CSS 规则',
                suggestion: '检测到可能替代的列表选择器：${suggestions.join("，")}',
                htmlSnippet: 'HTML 长度: ${html.length}',
              ));
            }
          }
        }
      } catch (_) {}
    }

    if (searchSuccess && !tocSuccess) {
      try {
        final books = await LegadoParser.searchBooks(source, testKeyword);
        if (books.isNotEmpty) {
          final firstBook = books.first;
          final response = await LegadoParser.fetchHtml(source, firstBook.filePath);
          final html = response.data?.toString() ?? '';
          if (html.isNotEmpty) {
            final oldSel = getOldSelector(source.ruleToc, 'chapterList');
            final redesignIssues = RedesignDetector.detect(
              source: source,
              stage: 'toc',
              field: 'chapterList',
              oldSelector: oldSel,
              pageHtml: html,
            );
            if (redesignIssues.isNotEmpty) {
              issues.addAll(redesignIssues);
            } else {
              final suggestions = RuleSuggestEngine.suggestChapterListRules(html);
              if (suggestions.isNotEmpty) {
                issues.add(DiagnosticIssue(
                  stage: 'toc',
                  field: 'chapterList',
                  reason: '目录解析失败：推荐候补 CSS 规则',
                  suggestion: '检测到可能替代的目录选择器：${suggestions.join("，")}',
                  htmlSnippet: 'HTML 长度: ${html.length}',
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    if (searchSuccess && tocSuccess && !contentSuccess) {
      try {
        final books = await LegadoParser.searchBooks(source, testKeyword);
        if (books.isNotEmpty) {
          final chapters = await LegadoParser.getChapterList(source, books.first);
          if (chapters.isNotEmpty) {
            final firstChapter = chapters.first;
            final url = firstChapter.content ?? firstChapter.url ?? '';
            if (url.isNotEmpty) {
              final response = await LegadoParser.fetchHtml(source, url);
              final html = response.data?.toString() ?? '';
              if (html.isNotEmpty) {
                final oldSel = getOldSelector(source.ruleContent, 'content');
                final redesignIssues = RedesignDetector.detect(
                  source: source,
                  stage: 'content',
                  field: 'content',
                  oldSelector: oldSel,
                  pageHtml: html,
                );
                if (redesignIssues.isNotEmpty) {
                  issues.addAll(redesignIssues);
                } else {
                  final suggestions = RuleSuggestEngine.suggestContentRules(html);
                  if (suggestions.isNotEmpty) {
                    issues.add(DiagnosticIssue(
                      stage: 'content',
                      field: 'content',
                      reason: '正文解析失败：推荐候补 CSS 规则',
                      suggestion: '检测到可能替代的正文选择器：${suggestions.join("，")}',
                      htmlSnippet: 'HTML 长度: ${html.length}',
                    ));
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // Calculate score
    int score = 100;
    if (!searchSuccess) score -= 30;
    if (!bookInfoSuccess) score -= 15;
    if (!tocSuccess) score -= 30;
    if (!contentSuccess) score -= 25;

    for (final issue in staticIssues) {
      if (issue.reason.contains('同步网络请求')) {
        score -= 5;
      }
      if (issue.reason.contains('XPath')) {
        score -= 3;
      }
    }
    if (score < 0) score = 0;

    String riskLevel = '低';
    if (score < 50) {
      riskLevel = '高';
    } else if (score < 80) {
      riskLevel = '中';
    }

    return DiagnosticReport(
      searchSuccess: searchSuccess,
      bookInfoSuccess: bookInfoSuccess,
      tocSuccess: tocSuccess,
      contentSuccess: contentSuccess,
      score: score,
      riskLevel: riskLevel,
      issues: issues,
    );
  }
}
