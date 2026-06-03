import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';
import 'rule_rank_engine.dart';

class RedesignDetector {
  static List<DiagnosticIssue> detect({
    required BookSource source,
    required String stage, // 'search' | 'toc' | 'content'
    required String field, // e.g. 'bookList', 'chapterList', 'content'
    required String oldSelector,
    required String pageHtml,
  }) {
    if (pageHtml.isEmpty || oldSelector.isEmpty) return [];

    final issues = <DiagnosticIssue>[];
    
    // Mode to pass to rank selectors
    final mode = stage == 'search' ? 'search' : (stage == 'toc' ? 'toc' : 'content');
    
    // Rank selectors on the HTML using RuleRankEngine
    final candidates = RuleRankEngine.rankSelectors(pageHtml, mode);
    if (candidates.isEmpty) return [];

    final topCandidate = candidates.first;
    // Check if the top candidate has a high score and differs from the old one
    if (topCandidate.score >= 70 && topCandidate.selector != oldSelector) {
      // Create comparison details
      final compDetails = '旧规则: $oldSelector\n新规则候选: ${topCandidate.selector} (得分: ${topCandidate.score.round()})\n匹配到的节点数: ${topCandidate.nodeCount}';
      
      issues.add(DiagnosticIssue(
        stage: stage,
        field: field,
        rule: oldSelector,
        reason: '检测到网站结构可能改版：旧选择器已无法捕获内容',
        suggestion: '检测到高权重备选规则！建议将旧选择器 "$oldSelector" 自动替换为 "${topCandidate.selector}"',
        htmlSnippet: compDetails,
      ));
    }

    return issues;
  }
}
