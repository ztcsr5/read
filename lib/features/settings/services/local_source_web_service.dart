import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/repositories/book_repository.dart';

final localSourceWebServiceProvider =
    StateNotifierProvider<LocalSourceWebService, LocalSourceWebState>((ref) {
      final repo = ref.watch(bookRepositoryProvider);
      final service = LocalSourceWebService(repo);
      ref.onDispose(service.stop);
      return service;
    });

class LocalSourceWebState {
  final bool isRunning;
  final String? url;
  final List<String> urls;
  final List<String> interfaceLabels;
  final int? port;
  final String accessToken;
  final String? error;
  final bool permissionProbeSent;
  final String? permissionProbeStatus;

  const LocalSourceWebState({
    required this.isRunning,
    required this.accessToken,
    this.urls = const [],
    this.interfaceLabels = const [],
    this.url,
    this.port,
    this.error,
    this.permissionProbeSent = false,
    this.permissionProbeStatus,
  });

  factory LocalSourceWebState.initial({String? accessToken}) {
    return LocalSourceWebState(
      isRunning: false,
      accessToken: accessToken ?? _randomToken(),
    );
  }

  LocalSourceWebState copyWith({
    bool? isRunning,
    String? url,
    List<String>? urls,
    List<String>? interfaceLabels,
    int? port,
    String? accessToken,
    String? error,
    bool? permissionProbeSent,
    String? permissionProbeStatus,
  }) {
    return LocalSourceWebState(
      isRunning: isRunning ?? this.isRunning,
      url: url ?? this.url,
      urls: urls ?? this.urls,
      interfaceLabels: interfaceLabels ?? this.interfaceLabels,
      port: port ?? this.port,
      accessToken: accessToken ?? this.accessToken,
      error: error,
      permissionProbeSent: permissionProbeSent ?? this.permissionProbeSent,
      permissionProbeStatus:
          permissionProbeStatus ?? this.permissionProbeStatus,
    );
  }
}

class LocalSourceWebService extends StateNotifier<LocalSourceWebState> {
  final BookRepository _repository;
  HttpServer? _server;

  LocalSourceWebService(this._repository)
    : super(LocalSourceWebState.initial());

  Future<void> start() async {
    if (_server != null) return;

    final token = state.accessToken.isEmpty
        ? _randomToken()
        : state.accessToken;
    try {
      HttpServer? server;
      Object? lastError;
      for (var port = 1122; port <= 1132; port++) {
        try {
          server = await HttpServer.bind(
            InternetAddress.anyIPv4,
            port,
            shared: true,
          );
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (server == null) {
        throw Exception('Web service port is unavailable: $lastError');
      }

      _server = server;
      server.autoCompress = true;
      unawaited(_serve(server));
      final endpoints = await _localWebEndpoints(server.port, token);
      final urls = endpoints.map((endpoint) => endpoint.url).toList();
      state = state.copyWith(
        isRunning: true,
        port: server.port,
        accessToken: token,
        url: urls.isEmpty
            ? 'http://127.0.0.1:${server.port}/?token=$token'
            : urls.first,
        urls: urls,
        interfaceLabels: endpoints.map((endpoint) => endpoint.label).toList(),
        permissionProbeSent: false,
        permissionProbeStatus: 'pending',
        error: null,
      );
      unawaited(
        _triggerLocalNetworkPermissionProbe(server.port).then((probe) {
          if (mounted && identical(_server, server)) {
            state = state.copyWith(
              permissionProbeSent: probe.sent,
              permissionProbeStatus: probe.status,
              error: null,
            );
          }
        }),
      );
    } catch (e) {
      state = state.copyWith(isRunning: false, error: e.toString());
    }
  }

  Future<void> restart() async {
    final token = state.accessToken;
    await stop(preserveToken: true);
    state = LocalSourceWebState.initial(accessToken: token);
    await start();
  }

  Future<void> stop({bool preserveToken = false}) async {
    final token = state.accessToken;
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
    }
    if (mounted) {
      state = LocalSourceWebState.initial(
        accessToken: preserveToken ? token : null,
      );
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } catch (e, stack) {
        debugPrint('LocalSourceWebService error: $e\n$stack');
        await _json(request, {
          'ok': false,
          'error': e.toString(),
        }, statusCode: HttpStatus.internalServerError);
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    _addCorsHeaders(request.response);

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    if (request.method == 'GET' && path == '/health') {
      await _text(request, 'READ_SOURCE_WEB_OK port=${state.port ?? '-'}');
      return;
    }

    if (request.method == 'GET' && (path == '/' || path == '/index.html')) {
      await _html(request, _editorHtml(state.accessToken));
      return;
    }

    if (!_authorized(request)) {
      await _json(request, {
        'ok': false,
        'error': 'Unauthorized',
      }, statusCode: HttpStatus.unauthorized);
      return;
    }

    if (request.method == 'GET' && path == '/api/status') {
      final sourceCount = await _repository.countBookSources();
      final enabledSourceCount = await _repository.countBookSources(
        enabled: true,
      );
      await _json(request, {
        'ok': true,
        'service': 'read-source-web',
        'port': state.port,
        'urls': state.urls,
        'interfaces': state.interfaceLabels,
        'permissionProbeSent': state.permissionProbeSent,
        'permissionProbeStatus': state.permissionProbeStatus,
        'sourceCount': sourceCount,
        'enabledSourceCount': enabledSourceCount,
      });
      return;
    }

    if (request.method == 'GET' && path == '/api/sources/export') {
      await _exportSources(request);
      return;
    }

    if (request.method == 'GET' && path == '/api/sources') {
      final q = request.uri.queryParameters['q']?.trim().toLowerCase() ?? '';
      final summary = _queryBool(request, 'summary');
      final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
      final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '');
      final total = await _repository.countBookSources();
      final filteredTotal = q.isEmpty
          ? total
          : await _repository.countBookSources(query: q);
      final start = (offset ?? 0).clamp(0, filteredTotal).toInt();
      final safeLimit = limit?.clamp(1, 1000).toInt();
      final page = await _repository.getBookSourcesPage(
        offset: start,
        limit: safeLimit,
        query: q,
      );
      final enabledCount = await _repository.countBookSources(enabled: true);
      await _json(request, {
        'ok': true,
        'total': total,
        'filteredTotal': filteredTotal,
        'offset': start,
        'limit': safeLimit,
        'hasMore': start + page.length < filteredTotal,
        'enabledCount': enabledCount,
        'data': page
            .map(summary ? _sourceSummaryJsonWithId : _sourceJsonWithId)
            .toList(),
      });
      return;
    }

    if (request.method == 'POST' && path == '/api/sources') {
      final body = await _readJsonBody(request);
      final source = _sourceFromBody(body);
      final id = await _repository.saveBookSource(source);
      await _json(request, {'ok': true, 'id': id});
      return;
    }

    if (request.method == 'POST' && path == '/api/sources/import') {
      final bodyText = await utf8.decoder.bind(request).join();
      final imported = await _importSources(bodyText);
      await _json(request, {
        'ok': true,
        'count': imported.savedCount,
        'parsedCount': imported.parsedCount,
      });
      return;
    }

    final sourceIdMatch = RegExp(r'^/api/sources/(\d+)$').firstMatch(path);
    if (sourceIdMatch != null) {
      final id = int.parse(sourceIdMatch.group(1)!);
      if (request.method == 'GET') {
        final source = await _sourceById(id);
        if (source == null) {
          await _notFound(request);
          return;
        }
        await _json(request, {'ok': true, 'data': _sourceJsonWithId(source)});
        return;
      }
      if (request.method == 'PUT') {
        final body = await _readJsonBody(request);
        final source = _sourceFromBody(body)..id = id;
        await _repository.saveBookSource(source);
        await _json(request, {'ok': true, 'id': id});
        return;
      }
      if (request.method == 'DELETE') {
        await _repository.deleteBookSource(id);
        await _json(request, {'ok': true});
        return;
      }
    }

    final testMatch = RegExp(r'^/api/sources/(\d+)/test$').firstMatch(path);
    if (testMatch != null && request.method == 'POST') {
      final id = int.parse(testMatch.group(1)!);
      final source = await _sourceById(id);
      if (source == null) {
        await _notFound(request);
        return;
      }
      final body = await _readJsonBody(request, allowEmpty: true);
      final keyword = body['keyword']?.toString().trim();
      final report = await LegadoParser.testSource(
        source,
        keyword == null || keyword.isEmpty ? '斗破苍穹' : keyword,
      );
      await _json(request, {'ok': true, 'data': _testReportJson(report)});
      return;
    }

    await _notFound(request);
  }

  bool _authorized(HttpRequest request) {
    final token = request.uri.queryParameters['token'];
    final header = request.headers.value('x-read-token');
    return state.accessToken.isNotEmpty &&
        (token == state.accessToken || header == state.accessToken);
  }

  Future<BookSource?> _sourceById(int id) async {
    return _repository.getBookSourceById(id);
  }

  Map<String, dynamic> _sourceJsonWithId(BookSource source) {
    return source.toJson()..['id'] = source.id;
  }

  Map<String, dynamic> _sourceSummaryJsonWithId(BookSource source) {
    return {
      'id': source.id,
      'bookSourceName': source.bookSourceName,
      'bookSourceUrl': source.bookSourceUrl,
      'bookSourceGroup': source.bookSourceGroup,
      'bookSourceType': source.bookSourceType,
      'enabled': source.enabled,
      'weight': source.weight,
      'searchUrl': source.searchUrl,
    };
  }

  bool _queryBool(HttpRequest request, String key) {
    final value = request.uri.queryParameters[key]?.toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  BookSource _sourceFromBody(Map<String, dynamic> body) {
    final data = body['data'];
    final raw = data is Map ? data : body;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final source = BookSource.fromJson(map);
    final id = map['id'];
    if (id is int && id > 0) {
      source.id = id;
    } else if (id is String) {
      source.id = int.tryParse(id) ?? Isar.autoIncrement;
    }
    return source;
  }

  Future<({int parsedCount, int savedCount})> _importSources(
    String rawBody,
  ) async {
    dynamic parsed;
    try {
      parsed = jsonDecode(rawBody);
    } catch (_) {
      final wrapped = jsonDecode(rawBody.isEmpty ? '{}' : rawBody);
      parsed = wrapped;
    }
    if (parsed is Map && parsed['json'] is String) {
      parsed = jsonDecode(parsed['json'] as String);
    }

    final items = _normalizeImportItems(parsed);
    final pendingByUrl = <String, BookSource>{};
    var parsedCount = 0;
    var savedCount = 0;
    Future<void> flushPending() async {
      if (pendingByUrl.isEmpty) return;
      savedCount += pendingByUrl.length;
      await _repository.saveBookSources(pendingByUrl.values.toList());
      pendingByUrl.clear();
    }

    for (final item in items) {
      if (item is! Map) continue;
      final map = item.map((key, value) => MapEntry(key.toString(), value));
      final hasBookSource =
          map.containsKey('bookSourceName') ||
          map.containsKey('bookSourceUrl') ||
          map.containsKey('sourceName') ||
          map.containsKey('sourceUrl') ||
          map.containsKey('searchUrl') ||
          map.containsKey('ruleSearchUrl') ||
          map.containsKey('ruleSearch') ||
          map.containsKey('rulesSearch') ||
          map.containsKey('ruleToc') ||
          map.containsKey('rulesToc') ||
          map.containsKey('ruleContent') ||
          map.containsKey('rulesContent') ||
          map.containsKey('ruleBookContent');
      if (!hasBookSource) continue;
      final source = BookSource.fromJson(map);
      if (source.bookSourceUrl.trim().isEmpty) continue;
      parsedCount++;
      pendingByUrl[source.bookSourceUrl] = source;
      if (pendingByUrl.length >= 500) {
        await flushPending();
      }
    }
    await flushPending();
    return (parsedCount: parsedCount, savedCount: savedCount);
  }

  List<dynamic> _normalizeImportItems(dynamic parsed) {
    if (parsed is List) return parsed;
    if (parsed is Map) {
      final data = parsed['data'];
      if (data is List) return data;
      if (data is Map && data['list'] is List) return data['list'] as List;
      for (final key in [
        'list',
        'items',
        'sources',
        'bookSources',
        'bookSource',
      ]) {
        if (parsed[key] is List) return parsed[key] as List;
      }
      return [parsed];
    }
    return const [];
  }

  Future<Map<String, dynamic>> _readJsonBody(
    HttpRequest request, {
    bool allowEmpty = false,
  }) async {
    final text = await utf8.decoder.bind(request).join();
    if (text.trim().isEmpty && allowEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const FormatException('JSON body must be an object');
  }

  Future<void> _exportSources(HttpRequest request) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers
      ..contentType = ContentType('application', 'json', charset: 'utf-8')
      ..set(
        'Content-Disposition',
        'attachment; filename="read-book-sources.json"',
      );

    const pageSize = 500;
    var offset = 0;
    var first = true;
    response.write('[');
    while (true) {
      final page = await _repository.getBookSourcesPage(
        offset: offset,
        limit: pageSize,
      );
      if (page.isEmpty) break;
      for (final source in page) {
        if (!first) response.write(',');
        response.write(jsonEncode(_sourceJsonWithId(source)));
        first = false;
      }
      offset += page.length;
      if (page.length < pageSize) break;
    }
    response.write(']');
    await response.close();
  }

  Map<String, dynamic> _testReportJson(LegadoTestReport report) {
    return {
      'hasFailure': report.hasFailure,
      'steps': report.steps.map((step) {
        return {
          'title': step.title,
          'message': step.message,
          'sample': step.sample,
          'status': step.status.name,
          'logs': step.logs,
        };
      }).toList(),
    };
  }

  Future<void> _html(HttpRequest request, String body) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'html',
      charset: 'utf-8',
    );
    response.write(body);
    await response.close();
  }

  Future<void> _text(HttpRequest request, String body) async {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'text',
      'plain',
      charset: 'utf-8',
    );
    response.write(body);
    await response.close();
  }

  Future<void> _json(
    HttpRequest request,
    Map<String, dynamic> body, {
    int statusCode = HttpStatus.ok,
  }) async {
    final response = request.response;
    response.statusCode = statusCode;
    response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _notFound(HttpRequest request) async {
    await _json(request, {
      'ok': false,
      'error': 'Not found',
    }, statusCode: HttpStatus.notFound);
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        'content-type,x-read-token,authorization',
      )
      ..set('Access-Control-Allow-Private-Network', 'true')
      ..set('Cache-Control', 'no-store');
  }
}

class _LocalWebEndpoint {
  final String url;
  final String label;

  const _LocalWebEndpoint({required this.url, required this.label});
}

Future<List<_LocalWebEndpoint>> _localWebEndpoints(
  int port,
  String token,
) async {
  final endpoints = <({String address, String name, int score})>[];

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final value = address.address;
        if (value.startsWith('127.') || value.startsWith('169.254.')) continue;
        endpoints.add((
          address: value,
          name: interface.name,
          score: _addressPriority(interface.name, value),
        ));
      }
    }
  } catch (_) {
    // Fall back to loopback below.
  }

  endpoints.sort((a, b) {
    final score = a.score.compareTo(b.score);
    if (score != 0) return score;
    final name = a.name.compareTo(b.name);
    if (name != 0) return name;
    return a.address.compareTo(b.address);
  });

  final result = <_LocalWebEndpoint>[];
  for (final endpoint in endpoints) {
    result.add(
      _LocalWebEndpoint(
        url: 'http://${endpoint.address}:$port/?token=$token',
        label: '${endpoint.name} · ${endpoint.address}',
      ),
    );
  }

  result.add(
    _LocalWebEndpoint(
      url: 'http://127.0.0.1:$port/?token=$token',
      label: 'loopback · 127.0.0.1',
    ),
  );
  return result;
}

int _addressPriority(String interfaceName, String address) {
  final name = interfaceName.toLowerCase();
  if (_isLowPriorityInterface(name)) return 8;
  if (name == 'en0' || name.contains('wi-fi') || name.contains('wlan')) {
    return 0;
  }
  if (name.startsWith('eth') || name.contains('ethernet')) return 1;
  if (_isPrivateLanAddress(address)) return 2;
  return 3;
}

bool _isLowPriorityInterface(String name) {
  return name.startsWith('pdp') ||
      name.startsWith('utun') ||
      name.startsWith('awdl') ||
      name.startsWith('llw') ||
      name.contains('vpn') ||
      name.contains('tailscale') ||
      name.contains('zerotier') ||
      name.contains('vmnet') ||
      name.contains('vbox') ||
      name.contains('docker') ||
      name.contains('bridge');
}

bool _isPrivateLanAddress(String address) {
  if (address.startsWith('10.')) return true;
  if (address.startsWith('192.168.')) return true;
  final parts = address.split('.');
  if (parts.length == 4 && parts.first == '172') {
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }
  return false;
}

const _localNetworkChannel = MethodChannel('read/local_network');

Future<({bool sent, String status})> _triggerLocalNetworkPermissionProbe(
  int port,
) async {
  final nativeStatus = await _requestNativeLocalNetworkPermission();
  if (nativeStatus == 'granted' ||
      nativeStatus == 'not_required' ||
      nativeStatus == 'timeout') {
    return (sent: true, status: 'native:$nativeStatus');
  }
  if (nativeStatus == 'denied') {
    return (sent: false, status: 'native:denied');
  }

  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final payload = utf8.encode('read-source-web:$port');
    socket.send(payload, InternetAddress('255.255.255.255'), port);
    socket.send(payload, InternetAddress('224.0.0.251'), 5353);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return (
      sent: true,
      status: nativeStatus == null
          ? 'udp:sent'
          : 'native:$nativeStatus;udp:sent',
    );
  } catch (e) {
    return (
      sent: false,
      status: nativeStatus == null
          ? 'udp:failed:$e'
          : 'native:$nativeStatus;udp:failed:$e',
    );
  } finally {
    socket?.close();
  }
}

Future<String?> _requestNativeLocalNetworkPermission() async {
  if (!Platform.isIOS) return null;
  try {
    final status = await _localNetworkChannel.invokeMethod<String>(
      'requestLocalNetworkAuthorization',
      {'timeoutMs': 3000},
    );
    return status?.trim().isEmpty == true ? null : status?.trim();
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    return 'failed:${e.code}';
  } catch (e) {
    return 'failed:$e';
  }
}

String _randomToken() {
  final random = Random.secure();
  return List.generate(6, (_) => random.nextInt(10)).join();
}

String _editorHtml(String token) {
  final encodedToken = htmlEscape.convert(token);
  return r'''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Read Web 书源工作台</title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #f5f6fa;
      --panel: rgba(255,255,255,.88);
      --panel-solid: #ffffff;
      --text: #14151a;
      --muted: #7b7f8b;
      --line: rgba(60,60,67,.15);
      --line-strong: rgba(60,60,67,.26);
      --blue: #5856d6;
      --blue-soft: rgba(88,86,214,.13);
      --green: #12b981;
      --green-soft: rgba(18,185,129,.14);
      --red: #ff3b30;
      --red-soft: rgba(255,59,48,.12);
      --orange: #ff9f0a;
      --shadow: 0 18px 45px rgba(26,28,38,.08);
      --radius: 18px;
      --mono: ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace;
      --font: -apple-system,BlinkMacSystemFont,"SF Pro Display","Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0f1015;
        --panel: rgba(30,32,40,.84);
        --panel-solid: #1c1e26;
        --text: #f4f5f7;
        --muted: #a5a8b2;
        --line: rgba(235,235,245,.12);
        --line-strong: rgba(235,235,245,.23);
        --blue-soft: rgba(120,118,255,.18);
        --green-soft: rgba(18,185,129,.18);
        --red-soft: rgba(255,69,58,.18);
        --shadow: 0 24px 55px rgba(0,0,0,.34);
      }
    }
    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body {
      margin: 0;
      color: var(--text);
      background:
        radial-gradient(circle at 12% -10%, rgba(88,86,214,.18), transparent 32%),
        linear-gradient(180deg, rgba(255,255,255,.3), transparent 220px),
        var(--bg);
      font: 15px/1.55 var(--font);
      -webkit-font-smoothing: antialiased;
    }
    button, input, textarea, select { font: inherit; }
    button {
      border: 0;
      min-height: 38px;
      border-radius: 12px;
      padding: 9px 14px;
      background: var(--blue);
      color: #fff;
      font-weight: 750;
      cursor: pointer;
      transition: transform .16s ease, opacity .16s ease, background .16s ease;
    }
    button:hover { transform: translateY(-1px); }
    button:active { transform: translateY(0); opacity: .78; }
    button.secondary { background: var(--panel-solid); color: var(--text); border: 1px solid var(--line); }
    button.ghost { background: transparent; color: var(--blue); }
    button.danger { background: var(--red); }
    button.soft { background: var(--blue-soft); color: var(--blue); }
    .topbar {
      height: 72px;
      position: sticky;
      top: 0;
      z-index: 20;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 0 26px;
      border-bottom: 1px solid var(--line);
      background: color-mix(in srgb, var(--panel) 88%, transparent);
      backdrop-filter: blur(26px) saturate(180%);
      -webkit-backdrop-filter: blur(26px) saturate(180%);
    }
    .brand { display: flex; align-items: center; gap: 13px; min-width: 260px; }
    .brand-icon {
      width: 42px; height: 42px; display: grid; place-items: center;
      border-radius: 14px; background: var(--blue); color: #fff;
      box-shadow: 0 12px 28px rgba(88,86,214,.25); font-size: 21px;
    }
    .brand h1 { margin: 0; font-size: 22px; letter-spacing: 0; }
    .brand p { margin: 1px 0 0; color: var(--muted); font-size: 12px; }
    .toolbar { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; justify-content: flex-end; }
    .layout { display: grid; grid-template-columns: 340px minmax(0,1fr); min-height: calc(100vh - 72px); }
    .sidebar { padding: 18px; border-right: 1px solid var(--line); overflow: auto; }
    .workspace { padding: 22px; overflow: auto; }
    .glass-card, .source-card, .editor-card, .empty-card, dialog {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
      backdrop-filter: blur(18px) saturate(160%);
      -webkit-backdrop-filter: blur(18px) saturate(160%);
    }
    .summary { padding: 15px; margin-bottom: 14px; display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .metric { padding: 12px; border-radius: 14px; background: color-mix(in srgb, var(--bg) 72%, transparent); }
    .metric b { display:block; font-size: 20px; line-height: 1.1; }
    .metric span { color: var(--muted); font-size: 12px; }
    .searchbox { position: sticky; top: 90px; z-index: 4; margin-bottom: 12px; }
    .searchbox input, input, textarea, select {
      width: 100%;
      border: 1px solid var(--line);
      border-radius: 13px;
      background: color-mix(in srgb, var(--panel-solid) 86%, transparent);
      color: var(--text);
      outline: none;
      padding: 11px 12px;
    }
    .searchbox input { padding-left: 39px; }
    .searchbox:before { content: "⌕"; position: absolute; left: 14px; top: 8px; color: var(--muted); font-size: 24px; }
    .source-card { padding: 13px; margin-bottom: 10px; cursor: pointer; box-shadow: none; transition: border .16s ease, background .16s ease, transform .16s ease; }
    .source-card:hover { transform: translateY(-1px); border-color: var(--line-strong); }
    .source-card.active { border-color: var(--blue); background: color-mix(in srgb, var(--blue-soft) 45%, var(--panel)); box-shadow: 0 0 0 3px var(--blue-soft); }
    .source-title { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
    .source-title b { overflow: hidden; white-space: nowrap; text-overflow: ellipsis; font-size: 15px; }
    .badge { display: inline-flex; align-items:center; gap: 4px; border-radius: 999px; padding: 3px 8px; font-size: 11px; font-weight: 800; color: var(--green); background: var(--green-soft); flex: none; }
    .badge.off { color: var(--red); background: var(--red-soft); }
    .source-card small { display:block; color: var(--muted); overflow:hidden; white-space:nowrap; text-overflow:ellipsis; margin-top: 5px; }
    .empty-card { min-height: 520px; display: grid; place-items: center; text-align: center; padding: 30px; }
    .empty-card h2 { margin: 12px 0 4px; font-size: 26px; }
    .empty-card p { margin: 0 auto 18px; color: var(--muted); max-width: 460px; }
    .hero-icon { width: 86px; height: 86px; border-radius: 28px; display:grid; place-items:center; background: var(--blue-soft); color: var(--blue); font-size: 42px; margin:auto; }
    .source-head { padding: 18px; margin-bottom: 14px; }
    .source-head-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; }
    .source-head h2 { margin: 0; font-size: 28px; line-height: 1.15; }
    .source-head p { margin: 6px 0 0; color: var(--muted); word-break: break-all; }
    .segmented { display: flex; gap: 4px; padding: 4px; margin-bottom: 14px; border-radius: 15px; background: color-mix(in srgb, var(--line) 38%, transparent); overflow-x: auto; }
    .segmented button { flex: 1; min-width: 74px; background: transparent; color: var(--text); border-radius: 11px; box-shadow: none; white-space: nowrap; }
    .segmented button.active { background: var(--panel-solid); color: var(--blue); box-shadow: 0 6px 16px rgba(0,0,0,.08); }
    .editor-card { padding: 16px; margin-bottom: 14px; }
    .section-title { display:flex; align-items:center; justify-content:space-between; gap: 12px; margin: 0 0 14px; }
    .section-title h3 { margin:0; font-size: 17px; }
    .section-title span { color: var(--muted); font-size: 12px; }
    .grid { display:grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 13px; }
    .field label { display:flex; align-items:center; justify-content:space-between; margin: 0 0 6px; color: var(--muted); font-size: 12px; font-weight: 700; }
    textarea { min-height: 96px; resize: vertical; font-family: var(--mono); font-size: 12.5px; line-height: 1.5; }
    .raw { min-height: 590px; tab-size: 2; }
    .hint { color: var(--muted); font-size: 12px; }
    .test-panel { display:none; }
    .steps { display:grid; gap: 11px; }
    .step { border: 1px solid var(--line); border-radius: 15px; padding: 13px; background: color-mix(in srgb, var(--panel-solid) 84%, transparent); }
    .step-head { display:flex; justify-content:space-between; align-items:center; gap: 12px; margin-bottom: 8px; }
    .step h4 { margin:0; font-size: 15px; }
    .step pre { margin: 10px 0 0; max-height: 290px; overflow:auto; white-space:pre-wrap; word-break:break-word; background: var(--bg); border: 1px solid var(--line); border-radius: 12px; padding: 11px; color: var(--muted); font-family: var(--mono); font-size: 12px; }
    .status-ok { color: var(--green); background: var(--green-soft); }
    .status-fail { color: var(--red); background: var(--red-soft); }
    .status-skip { color: var(--orange); background: rgba(255,159,10,.14); }
    .pill { border-radius: 999px; padding: 4px 9px; font-size: 11px; font-weight: 900; }
    .toast { position: fixed; left: 50%; top: 88px; transform: translate(-50%,-18px); opacity: 0; pointer-events:none; z-index: 50; padding: 11px 15px; border-radius: 999px; background: rgba(20,21,26,.88); color: #fff; box-shadow: var(--shadow); transition: .22s ease; }
    .toast.show { transform: translate(-50%,0); opacity: 1; }
    dialog { color: var(--text); border: 1px solid var(--line); width: min(820px, 94vw); padding: 0; }
    dialog::backdrop { background: rgba(0,0,0,.35); backdrop-filter: blur(8px); }
    .dialog-body { padding: 18px; }
    .dialog-head { padding: 16px 18px; border-bottom: 1px solid var(--line); display:flex; justify-content:space-between; align-items:center; }
    .dialog-head h2 { margin:0; font-size: 20px; }
    @media (max-width: 920px) {
      .topbar { height: auto; align-items:flex-start; padding: 16px; flex-direction: column; }
      .layout { grid-template-columns: 1fr; }
      .sidebar { border-right: 0; border-bottom: 1px solid var(--line); max-height: 44vh; }
      .workspace { padding: 16px; }
      .grid { grid-template-columns: 1fr; }
      .source-head-top { flex-direction: column; }
      .toolbar { justify-content: flex-start; }
    }
  </style>
</head>
<body>
  <div class="toast" id="toast"></div>
  <header class="topbar">
    <div class="brand">
      <div class="brand-icon">📖</div>
      <div>
        <h1>Read 书源工作台</h1>
        <p>局域网直连 App 数据库 · 本地运行</p>
      </div>
    </div>
    <div class="toolbar">
      <button class="secondary" onclick="loadSources()">刷新</button>
      <button class="soft" onclick="templateSource()">标准源模板</button>
      <button onclick="newSource()">新建书源</button>
      <button class="secondary" onclick="showImport()">导入 JSON</button>
      <button class="secondary" onclick="exportAllSources()">导出全部</button>
    </div>
  </header>

  <div class="layout">
    <aside class="sidebar">
      <div class="glass-card summary">
        <div class="metric"><b id="totalCount">0</b><span>书源总数</span></div>
        <div class="metric"><b id="enabledCount">0</b><span>已启用</span></div>
      </div>
      <div class="searchbox"><input id="filter" placeholder="搜索名称、URL、分组" oninput="scheduleLoadSources()"></div>
      <p class="hint" id="listHint" style="margin:0 2px 10px"></p>
      <div id="list"></div>
      <button id="loadMoreBtn" class="secondary" style="width:100%;display:none;margin-top:10px" onclick="loadMoreSources()">加载更多</button>
    </aside>

    <main class="workspace">
      <div id="empty" class="empty-card">
        <div>
          <div class="hero-icon">⌘</div>
          <h2>选择一个书源开始调试</h2>
          <p>这里可以直接编辑 App 里的书源 JSON。保存后手机端立即生效，适合修复搜索、目录、正文规则。</p>
          <div class="toolbar" style="justify-content:center">
            <button onclick="templateSource()">创建标准模板</button>
            <button class="secondary" onclick="showImport()">导入 JSON</button>
          </div>
        </div>
      </div>

      <section id="editor" style="display:none">
        <div class="source-head glass-card">
          <div class="source-head-top">
            <div>
              <h2 id="currentTitle"></h2>
              <p id="currentUrl"></p>
            </div>
            <div class="toolbar">
              <button class="secondary" onclick="copyCurrentJson()">复制 JSON</button>
              <button class="secondary" onclick="downloadCurrentJson()">下载当前</button>
              <button class="secondary" onclick="testSource()">测试书源</button>
              <button onclick="saveSource()">保存</button>
              <button class="danger" onclick="deleteSource()">删除</button>
            </div>
          </div>
        </div>
        <div class="segmented" id="tabs"></div>
        <div id="form"></div>
        <div id="testPanel" class="editor-card test-panel"></div>
      </section>
    </main>
  </div>

  <dialog id="importDialog">
    <div class="dialog-head">
      <h2>导入书源 JSON</h2>
      <button class="ghost" onclick="document.getElementById('importDialog').close()">关闭</button>
    </div>
    <div class="dialog-body">
      <textarea id="importText" class="raw" placeholder="粘贴 JSON 数组或单个书源 JSON"></textarea>
      <input id="importFile" type="file" accept=".json,application/json,text/plain" style="display:none" onchange="loadImportFile(event)">
      <p class="hint">支持粘贴 JSON，也可以从电脑选择 JSON 文件导入。导出全部可把 iOS App 内书源下载到 PC 备份或共享。</p>
      <div class="toolbar" style="justify-content:flex-end">
        <button class="secondary" onclick="document.getElementById('importFile').click()">选择文件</button>
        <button class="secondary" onclick="document.getElementById('importDialog').close()">取消</button>
        <button onclick="importJson(event)">导入</button>
      </div>
    </div>
  </dialog>

<script>
const TOKEN = "__TOKEN__";
let sources = [];
let sourceStats = {total: 0, enabledCount: 0, filteredTotal: 0, hasMore: false};
let current = null;
let tab = "base";
let loadTimer = 0;
let sourceOffset = 0;
let loadSeq = 0;
const sourcePageSize = 160;
const tabs = [
  ["base","基础"],["search","搜索"],["detail","详情"],["toc","目录"],["content","正文"],["explore","发现"],["raw","完整 JSON"]
];
const fields = {
  base: [["bookSourceName","源名称"],["bookSourceUrl","源 URL"],["bookSourceGroup","源分组"],["bookSourceType","源类型"],["enabled","启用状态"],["weight","权重"],["searchUrl","搜索 URL"],["exploreUrl","发现 URL"]],
  search: [["ruleSearch.bookList","bookList"],["ruleSearch.name","name"],["ruleSearch.author","author"],["ruleSearch.bookUrl","bookUrl"],["ruleSearch.coverUrl","coverUrl"],["ruleSearch.intro","intro"],["ruleSearch.kind","kind"],["ruleSearch.lastChapter","lastChapter"],["ruleSearch.checkKeyWord","checkKeyWord"]],
  detail: [["ruleBookInfo.init","init"],["ruleBookInfo.name","name"],["ruleBookInfo.author","author"],["ruleBookInfo.coverUrl","coverUrl"],["ruleBookInfo.intro","intro"],["ruleBookInfo.kind","kind"],["ruleBookInfo.lastChapter","lastChapter"],["ruleBookInfo.tocUrl","tocUrl"]],
  toc: [["ruleToc.chapterList","chapterList"],["ruleToc.chapterName","chapterName"],["ruleToc.chapterUrl","chapterUrl"],["ruleToc.isVip","isVip"],["ruleToc.isPay","isPay"],["ruleToc.nextTocUrl","nextTocUrl"],["ruleToc.updateTime","updateTime"]],
  content: [["ruleContent.content","content"],["ruleContent.nextContentUrl","nextContentUrl"],["ruleContent.webJs","webJs"],["ruleContent.sourceRegex","sourceRegex"],["ruleContent.replaceRegex","replaceRegex"],["ruleContent.imageStyle","imageStyle"]],
  explore: [["ruleExplore.bookList","bookList"],["ruleExplore.name","name"],["ruleExplore.author","author"],["ruleExplore.bookUrl","bookUrl"],["ruleExplore.coverUrl","coverUrl"],["ruleExplore.intro","intro"],["ruleExplore.kind","kind"]],
};
function api(path, opt={}) {
  const timeoutMs = opt.timeoutMs || 25000;
  delete opt.timeoutMs;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  opt.signal = opt.signal || controller.signal;
  opt.headers = Object.assign({"Content-Type":"application/json","X-Read-Token":TOKEN}, opt.headers || {});
  return fetch(path, opt).then(async r => {
    const text = await r.text();
    let data = {};
    try {
      data = text ? JSON.parse(text) : {};
    } catch (e) {
      throw new Error(`非 JSON 响应：${text.slice(0, 160)}`);
    }
    if (!r.ok || data.ok === false) throw new Error(data.error || r.statusText);
    return data;
  }).catch(e => {
    if (e && e.name === "AbortError") {
      throw new Error(`请求超时（${Math.round(timeoutMs / 1000)} 秒）。请确认手机未锁屏、App 仍在前台、PC 与 iPhone 在同一 Wi-Fi。`);
    }
    throw e;
  }).finally(() => {
    clearTimeout(timer);
  });
}
function scheduleLoadSources() {
  clearTimeout(loadTimer);
  loadTimer = setTimeout(() => loadSources(), 180);
}
async function loadSources() {
  return loadSourcePage(false);
}
async function loadMoreSources() {
  return loadSourcePage(true);
}
async function loadSourcePage(append) {
  const seq = ++loadSeq;
  const loadMoreBtn = document.getElementById("loadMoreBtn");
  if (loadMoreBtn) loadMoreBtn.disabled = true;
  try {
    const q = document.getElementById("filter").value.trim();
    const params = new URLSearchParams({summary:"1", limit:String(sourcePageSize), offset:String(append ? sourceOffset : 0)});
    if (q) params.set("q", q);
    const res = await api(`/api/sources?${params}`);
    if (seq !== loadSeq) return;
    const page = res.data || [];
    sources = append ? sources.concat(page) : page;
    sourceOffset = (res.offset ?? (append ? sourceOffset : 0)) + page.length;
    sourceStats = {
      total: res.total ?? sources.length,
      enabledCount: res.enabledCount ?? sources.filter(s => s.enabled !== false).length,
      filteredTotal: res.filteredTotal ?? sources.length,
      hasMore: !!res.hasMore,
    };
    renderList();
  } catch(e) {
    if (seq === loadSeq) toast("连接失败：" + e.message, true);
  } finally {
    if (seq === loadSeq && loadMoreBtn) loadMoreBtn.disabled = false;
  }
}
function renderList() {
  document.getElementById("totalCount").textContent = sourceStats.total;
  document.getElementById("enabledCount").textContent = sourceStats.enabledCount;
  const q = document.getElementById("filter").value.trim();
  const hint = document.getElementById("listHint");
  hint.textContent = q
    ? `匹配 ${sourceStats.filteredTotal} 个，当前显示 ${sources.length} 个${sourceStats.hasMore ? "，可继续加载或继续输入缩小范围" : ""}`
    : `当前显示 ${sources.length} / ${sourceStats.total} 个；搜索框支持服务端过滤，避免 8000+ 源一次性卡死`;
  const loadMoreBtn = document.getElementById("loadMoreBtn");
  loadMoreBtn.style.display = sourceStats.hasMore ? "" : "none";
  loadMoreBtn.textContent = sourceStats.hasMore ? `加载更多（已显示 ${sources.length} / ${sourceStats.filteredTotal}）` : "已全部加载";
  const root = document.getElementById("list");
  root.innerHTML = "";
  sources.forEach(s => {
    const div = document.createElement("div");
    div.className = "source-card" + (current && current.id === s.id ? " active" : "");
    div.onclick = () => selectSource(s.id);
    div.innerHTML = `<div class="source-title"><b>${escapeHtml(s.bookSourceName || "未命名")}</b><span class="badge ${s.enabled === false ? "off" : ""}">${s.enabled === false ? "停用" : "启用"}</span></div><small>${escapeHtml(s.bookSourceUrl || "")}</small><small>${escapeHtml(s.bookSourceGroup || "未分组")}</small>`;
    root.appendChild(div);
  });
}
async function selectSource(id) {
  const res = await api(`/api/sources/${id}`);
  current = res.data;
  tab = tab || "base";
  renderEditor();
  renderList();
}
function newSource() {
  current = {bookSourceName:"新书源",bookSourceUrl:"https://example.com",bookSourceType:0,enabled:true,weight:0,ruleSearch:{},ruleBookInfo:{},ruleToc:{},ruleContent:{},ruleExplore:{}};
  tab = "base";
  renderEditor();
  toast("已创建空白书源，保存后写入 App");
}
function templateSource() {
  current = {
    bookSourceName:"自建标准源模板",
    bookSourceUrl:"https://example.com",
    bookSourceGroup:"自建源",
    bookSourceType:0,
    enabled:true,
    weight:100,
    searchUrl:"/search?keyword={{key}}&page={{page}}",
    ruleSearch:{bookList:".book-item",name:".book-title@text",author:".author@text",bookUrl:"a@href",coverUrl:"img@src",intro:".intro@text",kind:".cat@text",lastChapter:".latest@text"},
    ruleBookInfo:{name:"h1@text",author:".author@text",coverUrl:".cover img@src",intro:".intro@text",tocUrl:"text.目录@href"},
    ruleToc:{chapterList:".chapter-list a",chapterName:"@text",chapterUrl:"@href"},
    ruleContent:{content:"#content@html",nextContentUrl:""},
    ruleExplore:{}
  };
  tab = "base";
  renderEditor();
  toast("已载入标准源模板");
}
function renderEditor() {
  document.getElementById("empty").style.display = "none";
  document.getElementById("editor").style.display = "";
  document.getElementById("currentTitle").textContent = current.bookSourceName || "未命名";
  document.getElementById("currentUrl").textContent = current.bookSourceUrl || "未设置 URL";
  document.getElementById("tabs").innerHTML = tabs.map(t => `<button class="${tab===t[0]?"active":""}" onclick="tab='${t[0]}';renderEditor()">${t[1]}</button>`).join("");
  document.getElementById("testPanel").style.display = "none";
  if (tab === "raw") {
    document.getElementById("form").innerHTML = `<div class="editor-card"><div class="section-title"><div><h3>完整 JSON</h3><span>直接编辑原始结构，适合粘贴阅读 3.0 规则</span></div></div><textarea id="rawJson" class="raw">${escapeHtml(JSON.stringify(current,null,2))}</textarea></div>`;
    return;
  }
  const rows = fields[tab] || [];
  document.getElementById("form").innerHTML = `<div class="editor-card"><div class="section-title"><div><h3>${tabs.find(t=>t[0]===tab)?.[1] || "规则"}</h3><span>保存后立即写入 App 内 Isar 数据库</span></div></div><div class="grid">${rows.map(fieldHtml).join("")}</div></div>`;
}
function fieldHtml(f) {
  const key = f[0], label = f[1], value = getPath(current, key);
  if (typeof value === "boolean" || key === "enabled") {
    return `<div class="field"><label>${label}</label><select data-key="${key}" onchange="setField(this)"><option value="true" ${value!==false?"selected":""}>启用</option><option value="false" ${value===false?"selected":""}>停用</option></select></div>`;
  }
  const text = value == null ? "" : value;
  const area = key.includes("rule") || String(text).length > 72 || key.endsWith("Url");
  return `<div class="field"><label>${label}<span>${key}</span></label>${area ? `<textarea data-key="${key}" oninput="setField(this)">${escapeHtml(text)}</textarea>` : `<input data-key="${key}" value="${escapeHtml(text)}" oninput="setField(this)">`}</div>`;
}
function setField(el) {
  let value = el.value;
  if (el.tagName === "SELECT") value = value === "true";
  if (["bookSourceType","weight"].includes(el.dataset.key)) value = Number(value || 0);
  setPath(current, el.dataset.key, value);
  document.getElementById("currentTitle").textContent = current.bookSourceName || "未命名";
  document.getElementById("currentUrl").textContent = current.bookSourceUrl || "未设置 URL";
}
async function saveSource() {
  try {
    if (tab === "raw") current = JSON.parse(document.getElementById("rawJson").value);
    const method = current.id ? "PUT" : "POST";
    const path = current.id ? `/api/sources/${current.id}` : "/api/sources";
    const res = await api(path, {method, body: JSON.stringify(current), timeoutMs: 45000});
    await loadSources();
    if (res.id) await selectSource(res.id);
    toast("保存成功");
  } catch(e) { toast("保存失败：" + e.message, true); }
}
async function deleteSource() {
  if (!current || !current.id || !confirm("删除这个书源？")) return;
  await api(`/api/sources/${current.id}`, {method:"DELETE"});
  current = null;
  document.getElementById("editor").style.display = "none";
  document.getElementById("empty").style.display = "";
  await loadSources();
  toast("已删除书源");
}
async function testSource() {
  if (!current || !current.id) { toast("请先保存书源", true); return; }
  const keyword = prompt("测试关键词", "斗破苍穹") || "斗破苍穹";
  const panel = document.getElementById("testPanel");
  panel.style.display = "block";
  panel.innerHTML = `<div class="section-title"><h3>书源测试</h3><span>正在运行 ${escapeHtml(keyword)}</span></div><p class="hint">测试中...</p>`;
  try {
    const res = await api(`/api/sources/${current.id}/test`, {method:"POST", body:JSON.stringify({keyword}), timeoutMs: 90000});
    const steps = res.data.steps || [];
    panel.innerHTML = `<div class="section-title"><div><h3>测试结果</h3><span>${res.data.hasFailure ? "存在失败步骤" : "全部通过"}</span></div><span class="pill ${res.data.hasFailure ? "status-fail" : "status-ok"}">${res.data.hasFailure ? "FAIL" : "OK"}</span></div><div class="steps">${steps.map(stepHtml).join("")}</div>`;
  } catch(e) { panel.innerHTML = `<span class="pill status-fail">测试失败</span><p>${escapeHtml(e.message)}</p>`; }
}
function stepHtml(s) {
  const cls = s.status === "fail" ? "status-fail" : (s.status === "skip" ? "status-skip" : "status-ok");
  const logs = [s.sample, ...(s.logs || [])].filter(Boolean).join("\n");
  return `<div class="step"><div class="step-head"><h4>${escapeHtml(s.title)}</h4><span class="pill ${cls}">${escapeHtml(s.status)}</span></div><div>${escapeHtml(s.message || "")}</div>${logs ? `<pre>${escapeHtml(logs)}</pre>` : ""}</div>`;
}
function showImport(){ document.getElementById("importDialog").showModal(); }
async function importJson(event) {
  event.preventDefault();
  try {
    const text = document.getElementById("importText").value;
    const res = await api("/api/sources/import", {method:"POST", body:text, timeoutMs: 120000});
    document.getElementById("importDialog").close();
    await loadSources();
    toast(`导入成功：${res.count} 个书源${res.parsedCount && res.parsedCount !== res.count ? `（解析 ${res.parsedCount} 个，已按 URL 去重）` : ""}`);
  } catch(e) { toast("导入失败：" + e.message, true); }
}
async function copyCurrentJson() {
  if (!current) return;
  if (tab === "raw") current = JSON.parse(document.getElementById("rawJson").value);
  await navigator.clipboard.writeText(JSON.stringify(current, null, 2));
  toast("JSON 已复制");
}
async function downloadCurrentJson() {
  if (!current) return;
  if (tab === "raw") current = JSON.parse(document.getElementById("rawJson").value);
  downloadJson(`${safeFileName(current.bookSourceName || "book-source")}.json`, current);
  toast("当前书源已下载");
}
async function exportAllSources() {
  try {
    toast("正在准备导出，浏览器会直接下载 JSON...");
    const date = new Date().toISOString().slice(0, 10);
    const a = document.createElement("a");
    a.href = `/api/sources/export?token=${encodeURIComponent(TOKEN)}&t=${Date.now()}`;
    a.download = `read-book-sources-${date}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    toast("已开始导出全部书源");
  } catch(e) { toast("导出失败：" + e.message, true); }
}
async function loadImportFile(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  try {
    const text = await file.text();
    document.getElementById("importText").value = text;
    toast(`已载入文件：${file.name}`);
  } catch(e) { toast("读取文件失败：" + e.message, true); }
  event.target.value = "";
}
function downloadJson(filename, data) {
  const blob = new Blob([JSON.stringify(data, null, 2)], {type:"application/json;charset=utf-8"});
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function safeFileName(name) {
  return String(name || "book-source").replace(/[\\/:*?"<>|]+/g, "_").slice(0, 80);
}
function getPath(obj, path) { return path.split(".").reduce((o,k)=>o && o[k], obj); }
function setPath(obj, path, value) {
  const parts = path.split(".");
  let target = obj;
  for (let i=0;i<parts.length-1;i++) target = target[parts[i]] ||= {};
  target[parts[parts.length-1]] = value;
}
function escapeHtml(v){return String(v ?? "").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));}
function toast(message, danger=false) {
  const el = document.getElementById("toast");
  el.textContent = message;
  el.style.background = danger ? "rgba(255,59,48,.92)" : "rgba(20,21,26,.9)";
  el.classList.add("show");
  clearTimeout(window.__toastTimer);
  window.__toastTimer = setTimeout(()=>el.classList.remove("show"), 2300);
}
loadSources();
</script>
</body>
</html>
'''
      .replaceAll('__TOKEN__', encodedToken);
}
