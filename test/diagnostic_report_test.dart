import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/diagnostic_report.dart';

void main() {
  group('DiagnosticReport', () {
    test('infers primary failure stage and next action', () {
      final report = DiagnosticReport(
        searchSuccess: true,
        bookInfoSuccess: true,
        tocSuccess: false,
        contentSuccess: true,
        score: 70,
        riskLevel: 'medium',
        issues: [
          DiagnosticIssue(
            stage: 'toc',
            field: 'chapterList',
            reason: 'No chapters parsed',
            suggestion: 'Check ruleToc.chapterList.',
          ),
        ],
      );

      expect(report.primaryFailureStage, 'toc');
      expect(report.nextAction, 'Check ruleToc.chapterList.');
      expect(report.stageSummaries, hasLength(4));
      expect(report.stageSummaries[2].stage, 'toc');
      expect(report.stageSummaries[2].status, 'fail');
      expect(report.stageSummaries[2].field, 'chapterList');
    });

    test('keeps old diagnostic json backward compatible', () {
      final report = DiagnosticReport.fromJson({
        'searchSuccess': true,
        'bookInfoSuccess': true,
        'tocSuccess': true,
        'contentSuccess': true,
        'score': 100,
        'riskLevel': 'low',
        'issues': <Map<String, dynamic>>[],
      });

      expect(report.primaryFailureStage, 'none');
      expect(report.nextAction, 'No blocking issue detected.');
      expect(
        report.stageSummaries.map((item) => item.status),
        everyElement('ok'),
      );
    });

    test('round trips explicit summary fields', () {
      final report = DiagnosticReport(
        searchSuccess: false,
        bookInfoSuccess: true,
        tocSuccess: true,
        contentSuccess: true,
        score: 60,
        riskLevel: 'medium',
        issues: const [],
        primaryFailureStage: 'search',
        nextAction: 'Fix search rules first.',
        stageSummaries: const [
          DiagnosticStageSummary(
            stage: 'search',
            status: 'fail',
            title: 'Search',
            message: 'Search failed.',
            field: 'bookList',
          ),
        ],
      );

      final decoded = DiagnosticReport.fromJson(report.toJson());

      expect(decoded.primaryFailureStage, 'search');
      expect(decoded.nextAction, 'Fix search rules first.');
      expect(decoded.stageSummaries, hasLength(1));
      expect(decoded.stageSummaries.single.field, 'bookList');
    });
  });
}
