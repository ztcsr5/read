import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado_parser.dart';

import '../tool/source_probe_core.dart';

void main() {
  test('source-probe-live', () async {
    final encoded = Platform.environment['SOURCE_PROBE_CONFIG'];
    if (encoded == null || encoded.isEmpty) {
      markTestSkipped(
        'SOURCE_PROBE_CONFIG is only set by tool/source_probe.dart',
      );
      return;
    }
    final config = jsonDecode(utf8.decode(base64Url.decode(encoded)));
    final options = ProbeOptions.fromJson(
      (config as Map).map((key, value) => MapEntry(key.toString(), value)),
    );
    final startedAt = DateTime.now();
    final loaded = await loadProbeInputs(options.inputs);
    final selected = selectProbeSources(loaded, options);
    stdout.writeln(
      'Loaded ${loaded.length} raw items, selected ${selected.length} sources.',
    );
    stdout.writeln(
      'Running live probe: keyword="${options.keyword}", '
      'concurrency=${options.concurrency}, '
      'timeout=${options.timeoutSeconds}s.',
    );

    final results = List<ProbeResult?>.filled(selected.length, null);
    var next = 0;
    final workers = List<Future<void>>.generate(options.concurrency, (_) async {
      while (true) {
        final index = next++;
        if (index >= selected.length) return;
        final result = await _runProbe(selected[index], options);
        results[index] = result;
        _printProgress(index + 1, selected.length, result);
      }
    });
    await Future.wait(workers);

    final report = ProbeReport(
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      options: options,
      totalRawItems: loaded.length,
      selectedSources: selected.length,
      results: results.whereType<ProbeResult>().toList(),
    );
    await writeProbeReport(report);
    stdout.writeln(report.shortSummary());
    stdout.writeln('Wrote reports to ${options.outDir}');
  }, timeout: const Timeout(Duration(hours: 12)));
}

Future<ProbeResult> _runProbe(LoadedSource entry, ProbeOptions options) async {
  final watch = Stopwatch()..start();
  try {
    final source = BookSource.fromJson(entry.raw);
    final report = await LegadoParser.testSource(
      source,
      options.keyword,
    ).timeout(Duration(seconds: options.timeoutSeconds));
    watch.stop();
    return _resultFromReport(
      entry: entry,
      source: source,
      report: report,
      durationMs: watch.elapsedMilliseconds,
      includeLogs: options.includeLogs,
      failLogLines: options.failLogLines,
    );
  } on TimeoutException catch (e) {
    watch.stop();
    return ProbeResult.error(
      entry: entry,
      status: 'timeout',
      failStep: 'timeout',
      message: e.message ?? 'timeout after ${options.timeoutSeconds}s',
      durationMs: watch.elapsedMilliseconds,
    );
  } catch (e, stack) {
    watch.stop();
    return ProbeResult.error(
      entry: entry,
      status: 'error',
      failStep: 'exception',
      message: e.toString(),
      durationMs: watch.elapsedMilliseconds,
      logs: options.includeLogs ? [stack.toString()] : const [],
    );
  }
}

ProbeResult _resultFromReport({
  required LoadedSource entry,
  required BookSource source,
  required LegadoTestReport report,
  required int durationMs,
  required bool includeLogs,
  required int failLogLines,
}) {
  final fail = _firstFailingStep(report);
  final features = featureTags(entry.raw);
  final steps = report.steps.map((step) {
    return {
      'title': step.title,
      'status': step.status.name,
      'message': step.message,
      if (step.sample != null) 'sample': step.sample,
      if (includeLogs) 'logs': step.logs,
    };
  }).toList();
  final message =
      fail?.message ?? (report.steps.isEmpty ? '' : report.steps.last.message);
  final failLogs = fail == null
      ? const <String>[]
      : fail.logs.take(failLogLines).toList();
  return ProbeResult(
    file: entry.file,
    rawIndex: entry.rawIndex,
    sourceName: source.bookSourceName,
    sourceUrl: source.bookSourceUrl,
    sourceGroup: source.bookSourceGroup ?? '',
    sourceType: source.bookSourceType,
    status: report.hasFailure ? 'fail' : 'ok',
    failStep: fail?.title,
    message: message,
    durationMs: durationMs,
    booksCount: _extractCount(report, RegExp(r'解析到\s*(\d+)\s*本')),
    chaptersCount: _extractCount(report, RegExp(r'解析到\s*(\d+)\s*章')),
    contentLength: _extractCount(report, RegExp(r'正文字数:\s*(\d+)')),
    features: features,
    compatHint: buildCompatHint(fail?.title, features, message),
    steps: steps,
    failLogs: failLogs,
  );
}

LegadoTestStep? _firstFailingStep(LegadoTestReport report) {
  for (final step in report.steps) {
    if (step.status == LegadoStepStatus.fail) return step;
  }
  return null;
}

int? _extractCount(LegadoTestReport report, RegExp pattern) {
  for (final step in report.steps) {
    final match = pattern.firstMatch(step.message);
    if (match != null) return int.tryParse(match.group(1)!);
    for (final log in step.logs) {
      final logMatch = pattern.firstMatch(log);
      if (logMatch != null) return int.tryParse(logMatch.group(1)!);
    }
  }
  return null;
}

void _printProgress(int done, int total, ProbeResult result) {
  final status = result.status.padRight(7);
  final fail = result.failStep == null ? '' : ' ${result.failStep}';
  stdout.writeln(
    '[$done/$total] $status ${result.sourceName} '
    '(${result.durationMs}ms)$fail',
  );
}
