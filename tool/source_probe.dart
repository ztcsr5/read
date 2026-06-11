import 'dart:convert';
import 'dart:io';

import 'source_probe_core.dart';

Future<void> main(List<String> args) async {
  final options = ProbeOptions.parse(args);
  if (options.help) {
    stdout.writeln(sourceProbeUsage);
    return;
  }
  if (options.inputs.isEmpty) {
    stderr.writeln('No input JSON files or directories.');
    stderr.writeln(sourceProbeUsage);
    exitCode = 64;
    return;
  }

  if (options.dryRun) {
    await _runStaticProbe(options);
    return;
  }

  final config = base64Url.encode(utf8.encode(jsonEncode(options.toJson())));
  final flutter = _flutterExecutable();
  stdout.writeln('Launching Flutter test runner for live probing...');
  stdout.writeln('Executable: $flutter');
  final environment = Map<String, String>.from(Platform.environment)
    ..['SOURCE_PROBE_CONFIG'] = config;
  final process = await Process.start(
    flutter,
    [
      'test',
      'test/source_probe_runner_test.dart',
      '--plain-name',
      'source-probe-live',
      '--concurrency=1',
    ],
    workingDirectory: Directory.current.path,
    environment: environment,
    runInShell: Platform.isWindows,
  );
  stdout.addStream(process.stdout);
  stderr.addStream(process.stderr);
  exitCode = await process.exitCode;
}

Future<void> _runStaticProbe(ProbeOptions options) async {
  final startedAt = DateTime.now();
  final loaded = await loadProbeInputs(options.inputs);
  final selected = selectProbeSources(loaded, options);
  stdout.writeln(
    'Loaded ${loaded.length} raw items, selected ${selected.length} sources.',
  );
  stdout.writeln('Static dry-run only: no network requests.');
  final results = selected.map(ProbeResult.staticOnly).toList();
  final report = ProbeReport(
    startedAt: startedAt,
    finishedAt: DateTime.now(),
    options: options,
    totalRawItems: loaded.length,
    selectedSources: selected.length,
    results: results,
  );
  await writeProbeReport(report);
  stdout.writeln(report.shortSummary());
  stdout.writeln('Wrote reports to ${options.outDir}');
}

String _flutterExecutable() {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    return Platform.isWindows
        ? '$flutterRoot\\bin\\flutter.bat'
        : '$flutterRoot/bin/flutter';
  }
  var dir = File(Platform.resolvedExecutable).absolute.parent;
  for (var i = 0; i < 8; i++) {
    final direct = Platform.isWindows
        ? File('${dir.path}\\flutter.bat')
        : File('${dir.path}/flutter');
    if (direct.existsSync()) return direct.path;
    final nested = Platform.isWindows
        ? File('${dir.path}\\bin\\flutter.bat')
        : File('${dir.path}/bin/flutter');
    if (nested.existsSync()) return nested.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Platform.isWindows ? 'flutter.bat' : 'flutter';
}
