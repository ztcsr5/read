import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';
import '../../../data/models/source_diagnostic_history.dart';
import '../viewmodels/source_diagnostic_viewmodel.dart';
import '../widgets/health_trend_chart.dart';

class SourceDiagnosticPage extends ConsumerStatefulWidget {
  final BookSource source;

  const SourceDiagnosticPage({super.key, required this.source});

  @override
  ConsumerState<SourceDiagnosticPage> createState() =>
      _SourceDiagnosticPageState();
}

class _SourceDiagnosticPageState extends ConsumerState<SourceDiagnosticPage> {
  final TextEditingController _keywordController = TextEditingController(
    text: '斗破苍穹',
  );

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  Color _getRiskColor(String level) {
    if (level == '低') return const Color(0xFF10B981);
    if (level == '中') return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sourceDiagnosticViewModelProvider(widget.source));
    final viewModel = ref.read(
      sourceDiagnosticViewModelProvider(widget.source).notifier,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryBg = isDark
        ? const Color(0xFF121212)
        : const Color(0xFFF9F9FA);
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF2D2D2D)
        : const Color(0xFFE5E5EA);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subTextColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8A8A8F);

    return Scaffold(
      backgroundColor: primaryBg,
      appBar: AppBar(
        title: Text(
          '书源诊断中心',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.trash),
            onPressed: () {
              showCupertinoDialog(
                context: context,
                builder: (context) => CupertinoAlertDialog(
                  title: const Text('清空历史记录'),
                  content: const Text('确定要清空该书源的所有诊断历史记录吗？'),
                  actions: [
                    CupertinoDialogAction(
                      child: const Text('取消'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      child: const Text('清空'),
                      onPressed: () {
                        viewModel.clearHistory();
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007AFF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'LEGADO',
                            style: TextStyle(
                              color: Color(0xFF007AFF),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.source.bookSourceName,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.source.bookSourceUrl,
                      style: TextStyle(color: subTextColor, fontSize: 13),
                    ),
                    if (state.source.bookSourceGroup != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '分组: ${state.source.bookSourceGroup}',
                        style: TextStyle(
                          color: textColor.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '测试关键字',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            controller: _keywordController,
                            placeholder: '请输入测试书籍名称',
                            style: TextStyle(color: textColor),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : const Color(0xFFF2F2F7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          color: const Color(0xFF007AFF),
                          borderRadius: BorderRadius.circular(8),
                          onPressed: state.isDiagnosing
                              ? null
                              : () => viewModel.runDiagnosis(
                                  _keywordController.text,
                                ),
                          child: state.isDiagnosing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CupertinoActivityIndicator(
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '开始诊断',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (state.error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    state.error!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              if (state.report != null) ...[
                _buildReportSection(
                  context,
                  state.report!,
                  viewModel,
                  cardBg,
                  borderColor,
                  textColor,
                  subTextColor,
                ),
                const SizedBox(height: 20),
              ],

              HealthTrendChart(records: state.healthRecords),
              const SizedBox(height: 20),

              if (state.history.isNotEmpty) ...[
                Text(
                  '诊断历史记录',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.history.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final h = state.history[index];
                    return GestureDetector(
                      onTap: () {
                        ref
                            .read(
                              sourceDiagnosticViewModelProvider(
                                widget.source,
                              ).notifier,
                            )
                            .state = state.copyWith(
                          report: h.report,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '得分: ${h.score}',
                                  style: TextStyle(
                                    color: _getScoreColor(h.score),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  h.createTime.toLocal().toString().substring(
                                    0,
                                    19,
                                  ),
                                  style: TextStyle(
                                    color: subTextColor,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: CupertinoColors.inactiveGray,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportSection(
    BuildContext context,
    DiagnosticReport report,
    SourceDiagnosticViewModel viewModel,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Text(
                '兼容性综合得分',
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: report.score / 100.0,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getScoreColor(report.score),
                      ),
                    ),
                  ),
                  Text(
                    '${report.score}',
                    style: TextStyle(
                      color: _getScoreColor(report.score),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('风险等级：'),
                  Text(
                    report.riskLevel,
                    style: TextStyle(
                      color: _getRiskColor(report.riskLevel),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CupertinoButton(
                color: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                borderRadius: BorderRadius.circular(8),
                onPressed: () => viewModel.applyAutoRepair(),
                child: const Text(
                  '一键修复兼容性问题',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Text(
          '诊断流程明细',
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              _buildStageTile('搜索服务解析', report.searchSuccess, textColor),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildStageTile('书籍详情页面', report.bookInfoSuccess, textColor),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildStageTile('书籍目录抽取', report.tocSuccess, textColor),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _buildStageTile('章节正文解析', report.contentSuccess, textColor),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Text(
          '诊断故障与智能修复建议',
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        if (report.issues.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 10),
                Text(
                  '书源状况完美，暂未检测到兼容性问题。',
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: report.issues.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final issue = report.issues[index];
              final isHighRisk =
                  issue.stage == 'overall' ||
                  issue.reason.contains('失败') ||
                  issue.reason.contains('空');

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isHighRisk
                        ? const Color(0xFFEF4444).withOpacity(0.3)
                        : borderColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (isHighRisk
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFFF59E0B))
                                    .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            issue.stage.toUpperCase(),
                            style: TextStyle(
                              color: isHighRisk
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFFF59E0B),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (issue.field != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '字段: ${issue.field}',
                            style: TextStyle(
                              color: subTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      issue.reason,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '修复建议：${issue.suggestion}',
                      style: TextStyle(
                        color: textColor.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                    if (issue.htmlSnippet != null &&
                        issue.htmlSnippet!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF151515)
                              : const Color(0xFFF4F5F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            issue.htmlSnippet!.length > 1000
                                ? '${issue.htmlSnippet!.substring(0, 1000)}...'
                                : issue.htmlSnippet!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: CupertinoColors.inactiveGray,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (issue.suggestion.contains('可能替代') ||
                        issue.suggestion.contains('候补') ||
                        issue.suggestion.contains('检测到')) ...[
                      const SizedBox(height: 12),
                      _buildSuggestedActions(issue, viewModel),
                    ],
                    if (issue.reason.contains('目录反序') ||
                        (issue.stage == 'toc' &&
                            issue.reason.contains('目录'))) ...[
                      const SizedBox(height: 12),
                      CupertinoButton(
                        color: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        onPressed: () => viewModel.applyReverseChapters(),
                        child: const Text(
                          '一键反转目录列表',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildSuggestedActions(
    DiagnosticIssue issue,
    SourceDiagnosticViewModel viewModel,
  ) {
    final exp = RegExp(r'(?:\.|\#)[a-zA-Z0-9_\-\s\>\#\.\:\@\(\)]+');
    final matches = exp.allMatches(issue.suggestion);
    if (matches.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: matches.map((m) {
        final selector = m.group(0)!.trim();
        return CupertinoButton(
          color: const Color(0xFF007AFF).withOpacity(0.1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          borderRadius: BorderRadius.circular(6),
          onPressed: () =>
              viewModel.applyRuleSuggestion(issue.field ?? 'content', selector),
          child: Text(
            '应用 $selector',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF007AFF),
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStageTile(String title, bool success, Color textColor) {
    return ListTile(
      title: Text(title, style: TextStyle(color: textColor, fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            success ? '正常' : '异常',
            style: TextStyle(
              color: success
                  ? const Color(0xFF10B981)
                  : const Color(0xFFEF4444),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            success
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.xmark_circle_fill,
            color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            size: 20,
          ),
        ],
      ),
    );
  }
}
