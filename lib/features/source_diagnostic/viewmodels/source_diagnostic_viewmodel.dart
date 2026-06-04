import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';
import '../../../data/models/source_diagnostic_history.dart';
import '../../../data/models/source_health_record.dart';
import '../../../data/repositories/book_repository.dart';
import '../services/source_auto_repair_service.dart';
import '../services/source_diagnostic_service.dart';

class SourceDiagnosticState {
  final BookSource source;
  final bool isDiagnosing;
  final DiagnosticReport? report;
  final List<SourceDiagnosticHistory> history;
  final List<SourceHealthRecord> healthRecords;
  final String? error;
  final String? message;

  SourceDiagnosticState({
    required this.source,
    this.isDiagnosing = false,
    this.report,
    this.history = const [],
    this.healthRecords = const [],
    this.error,
    this.message,
  });

  SourceDiagnosticState copyWith({
    BookSource? source,
    bool? isDiagnosing,
    DiagnosticReport? report,
    List<SourceDiagnosticHistory>? history,
    List<SourceHealthRecord>? healthRecords,
    String? error,
    String? message,
  }) {
    return SourceDiagnosticState(
      source: source ?? this.source,
      isDiagnosing: isDiagnosing ?? this.isDiagnosing,
      report: report ?? this.report,
      history: history ?? this.history,
      healthRecords: healthRecords ?? this.healthRecords,
      error: error,
      message: message,
    );
  }
}

class SourceDiagnosticViewModel extends StateNotifier<SourceDiagnosticState> {
  final BookRepository _repository;

  SourceDiagnosticViewModel(this._repository, BookSource source)
    : super(SourceDiagnosticState(source: source)) {
    loadHistory();
  }

  Future<void> loadHistory() async {
    final allHistory = await SourceDiagnosticHistory.getHistoryForSource(
      state.source.bookSourceUrl,
    );
    final allHealth = await SourceHealthRecord.getRecordsForSource(
      state.source.bookSourceUrl,
    );
    state = state.copyWith(history: allHistory, healthRecords: allHealth);
  }

  Future<void> runDiagnosis(String keyword) async {
    state = state.copyWith(isDiagnosing: true, error: null, message: null);
    try {
      final report = await SourceDiagnosticService.diagnose(
        state.source,
        keyword,
      );

      final record = SourceDiagnosticHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sourceUrl: state.source.bookSourceUrl,
        score: report.score,
        reportJson: jsonEncode(report.toJson()),
        createTime: DateTime.now(),
      );
      await SourceDiagnosticHistory.save(record);

      await loadHistory();
      state = state.copyWith(isDiagnosing: false, report: report);
    } catch (e) {
      state = state.copyWith(isDiagnosing: false, error: '诊断失败: $e');
    }
  }

  Future<void> applyAutoRepair() async {
    state = state.copyWith(isDiagnosing: true, error: null, message: null);
    try {
      final result = SourceAutoRepairService.repairWithReport(
        state.source,
        report: state.report,
      );
      final repairedSource = result.source;
      await _repository.saveBookSource(repairedSource);
      final message = result.changes.isEmpty
          ? '没有发现可确定自动修复的规则，已重新诊断。'
          : '已保存自动修复：${result.changes.join('；')}';
      state = state.copyWith(source: repairedSource, message: message);
      await runDiagnosis('斗破苍穹');
      state = state.copyWith(message: message);
    } catch (e) {
      state = state.copyWith(isDiagnosing: false, error: '自动修复失败: $e');
    }
  }

  Future<void> applyReverseChapters() async {
    state = state.copyWith(isDiagnosing: true, error: null, message: null);
    try {
      final repairedSource = SourceAutoRepairService.reverseChapters(
        state.source,
      );
      await _repository.saveBookSource(repairedSource);
      state = state.copyWith(source: repairedSource);
      await runDiagnosis('斗破苍穹');
    } catch (e) {
      state = state.copyWith(isDiagnosing: false, error: '反转章节失败: $e');
    }
  }

  Future<void> applyRuleSuggestion(String field, String ruleSelector) async {
    state = state.copyWith(isDiagnosing: true, error: null, message: null);
    try {
      final source = state.source.duplicate();
      if (field == 'bookList') {
        if (source.ruleSearch != null) {
          final map = jsonDecode(source.ruleSearch!) as Map<String, dynamic>;
          map['bookList'] = ruleSelector;
          source.ruleSearch = jsonEncode(map);
        }
      } else if (field == 'chapterList') {
        if (source.ruleToc != null) {
          final map = jsonDecode(source.ruleToc!) as Map<String, dynamic>;
          map['chapterList'] = ruleSelector;
          source.ruleToc = jsonEncode(map);
        }
      } else if (field == 'content') {
        if (source.ruleContent != null) {
          final map = jsonDecode(source.ruleContent!) as Map<String, dynamic>;
          map['content'] = ruleSelector;
          source.ruleContent = jsonEncode(map);
        }
      }

      await _repository.saveBookSource(source);
      const message = '已保存推荐规则并重新诊断。';
      state = state.copyWith(source: source, message: message);
      await runDiagnosis('斗破苍穹');
      state = state.copyWith(message: message);
    } catch (e) {
      state = state.copyWith(isDiagnosing: false, error: '应用推荐规则失败: $e');
    }
  }

  Future<void> clearHistory() async {
    await SourceDiagnosticHistory.clearHistoryForSource(
      state.source.bookSourceUrl,
    );
    await SourceHealthRecord.clearHistoryForSource(state.source.bookSourceUrl);
    await loadHistory();
  }
}

final sourceDiagnosticViewModelProvider =
    StateNotifierProvider.family<
      SourceDiagnosticViewModel,
      SourceDiagnosticState,
      BookSource
    >((ref, source) {
      final repo = ref.watch(bookRepositoryProvider);
      return SourceDiagnosticViewModel(repo, source);
    });
