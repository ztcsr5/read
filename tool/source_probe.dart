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
  final quickJsPreflight = await _quickJsPreflight();
  if (quickJsPreflight.message.isNotEmpty) {
    stdout.writeln(quickJsPreflight.message);
  }
  final environment = Map<String, String>.from(Platform.environment)
    ..['SOURCE_PROBE_CONFIG'] = config
    ..['LEGADO_DISABLE_HEADLESS_WEBVIEW'] = '1';
  if (quickJsPreflight.dllPath != null) {
    environment['LIBQUICKJSC_TEST_PATH'] = quickJsPreflight.dllPath!;
    final dllDir = File(quickJsPreflight.dllPath!).parent.path;
    final path = environment['PATH'] ?? environment['Path'] ?? '';
    environment['PATH'] = path.isEmpty ? dllDir : '$dllDir;$path';
  }
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

Future<_QuickJsPreflight> _quickJsPreflight() async {
  if (!Platform.isWindows) return const _QuickJsPreflight();

  final explicit = Platform.environment['LIBQUICKJSC_TEST_PATH'];
  if (explicit != null && explicit.trim().isNotEmpty) {
    final file = File(explicit.trim());
    if (await file.exists()) {
      return _QuickJsPreflight(
        dllPath: file.absolute.path,
        message: 'QuickJS DLL: using LIBQUICKJSC_TEST_PATH=${file.path}',
      );
    }
    return _QuickJsPreflight(
      message:
          'QuickJS DLL preflight: LIBQUICKJSC_TEST_PATH is set but the file '
          'does not exist: ${file.path}',
    );
  }

  final packageRoot = await _quickJsPackageRoot();
  final candidates = <File>[
    File('quickjs_c_bridge_plugin.dll'),
    File('build\\windows\\x64\\runner\\Debug\\quickjs_c_bridge_plugin.dll'),
    File('build\\windows\\x64\\runner\\Release\\quickjs_c_bridge_plugin.dll'),
    if (packageRoot != null)
      File(
        '${packageRoot.path}\\native\\build\\Release\\quickjs_c_bridge_plugin.dll',
      ),
    if (packageRoot != null)
      File('${packageRoot.path}\\native\\build\\quickjs_c_bridge_plugin.dll'),
  ];
  for (final candidate in candidates) {
    if (await candidate.exists()) {
      return _QuickJsPreflight(
        dllPath: candidate.absolute.path,
        message: 'QuickJS DLL: found ${candidate.absolute.path}',
      );
    }
  }

  final missingTools = <String>[];
  if (!_commandExists('cmake')) missingTools.add('CMake');
  if (!_commandExists('cl')) missingTools.add('MSVC cl.exe');
  final buffer = StringBuffer()
    ..writeln(
      'QuickJS DLL preflight: quickjs_c_bridge_plugin.dll was not found.',
    );
  if (_commandExists('node')) {
    buffer.writeln(
      'Node.js fallback is available for Windows probing. Complex Android/Java '
      'bridges still require QuickJS/iOS App retest.',
    );
  } else {
    buffer.writeln(
      'JS-heavy sources will be marked BLOCKED instead of failed to avoid '
      'false negatives.',
    );
  }
  if (packageRoot != null) {
    buffer
      ..writeln('To enable JS source probing on Windows:')
      ..writeln('  cd "${packageRoot.path}"')
      ..writeln(
        '  powershell.exe -ExecutionPolicy Bypass -File tool\\build_native.ps1',
      )
      ..writeln(
        'Then rerun this probe; the CLI will auto-detect '
        'native\\build\\Release\\quickjs_c_bridge_plugin.dll.',
      );
  }
  if (missingTools.isNotEmpty) {
    buffer.writeln('Missing native build tools: ${missingTools.join(', ')}.');
  }
  return _QuickJsPreflight(message: buffer.toString().trimRight());
}

Future<Directory?> _quickJsPackageRoot() async {
  final packageConfig = File('.dart_tool\\package_config.json');
  if (!await packageConfig.exists()) return null;
  try {
    final decoded = jsonDecode(await packageConfig.readAsString());
    final packages = decoded is Map ? decoded['packages'] : null;
    if (packages is! List) return null;
    for (final item in packages) {
      if (item is! Map || item['name'] != 'quickjs_engine') continue;
      final rootUri = item['rootUri']?.toString();
      if (rootUri == null || rootUri.isEmpty) return null;
      final uri = Uri.parse(rootUri);
      final path = uri.isAbsolute
          ? uri.toFilePath(windows: Platform.isWindows)
          : Uri.file(
              '${Directory.current.path}\\.dart_tool\\',
            ).resolveUri(uri).toFilePath(windows: Platform.isWindows);
      return Directory(path);
    }
  } catch (_) {
    return null;
  }
  return null;
}

bool _commandExists(String command) {
  final result = Process.runSync(Platform.isWindows ? 'where.exe' : 'which', [
    command,
  ], runInShell: true);
  return result.exitCode == 0;
}

class _QuickJsPreflight {
  final String? dllPath;
  final String message;

  const _QuickJsPreflight({this.dllPath, this.message = ''});
}
