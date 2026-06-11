import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:read/data/models/book_source.dart';
import 'package:read/data/repositories/book_repository.dart';
import 'package:read/features/settings/services/local_source_web_service.dart';

void main() {
  test('local source web service exposes and updates book sources', () async {
    final repo = BookRepository(null);
    final source = BookSource()
      ..bookSourceName = 'Web Source'
      ..bookSourceUrl = 'https://example.com'
      ..bookSourceType = 0
      ..enabled = true
      ..weight = 1
      ..searchUrl = '/search?q={{key}}'
      ..ruleSearch = jsonEncode({'bookList': '.item', 'name': 'a@text'});
    final sourceId = await repo.saveBookSource(source);

    final service = LocalSourceWebService(repo);
    await service.start();
    addTearDown(() => service.stop());

    final token = service.state.accessToken;
    final base = 'http://127.0.0.1:${service.state.port}';
    final headers = {'X-Read-Token': token, 'Content-Type': 'application/json'};

    expect(service.state.urls, isNotEmpty);
    expect(service.state.urls.any((url) => url.contains('127.0.0.1')), isTrue);

    final healthResponse = await http.get(Uri.parse('$base/health'));
    expect(healthResponse.statusCode, 200);
    expect(healthResponse.body, contains('READ_SOURCE_WEB_OK'));

    final statusResponse = await http.get(
      Uri.parse('$base/api/status'),
      headers: headers,
    );
    expect(statusResponse.statusCode, 200);
    final statusJson = jsonDecode(statusResponse.body) as Map<String, dynamic>;
    expect(statusJson['urls'], isA<List>());
    expect(statusJson['permissionProbeSent'], isA<bool>());
    expect(statusJson['sourceCount'], 1);
    expect(statusJson['enabledSourceCount'], 1);
    expect(
      statusResponse.headers['access-control-allow-private-network'],
      'true',
    );

    final listResponse = await http.get(
      Uri.parse('$base/api/sources'),
      headers: headers,
    );
    expect(listResponse.statusCode, 200);
    final listJson = jsonDecode(listResponse.body) as Map<String, dynamic>;
    expect(listJson['ok'], true);
    expect(listJson['total'], 1);
    expect(listJson['filteredTotal'], 1);
    final fullSource = (listJson['data'] as List).single as Map;
    expect(fullSource['bookSourceName'], 'Web Source');
    expect(fullSource['ruleSearch'], isA<Map>());

    final exportResponse = await http.get(
      Uri.parse('$base/api/sources/export?token=$token'),
    );
    expect(exportResponse.statusCode, 200);
    expect(
      exportResponse.headers['content-disposition'],
      contains('read-book-sources.json'),
    );
    final exported = jsonDecode(exportResponse.body) as List;
    expect(exported, hasLength(1));
    expect((exported.single as Map)['bookSourceName'], 'Web Source');

    final summaryResponse = await http.get(
      Uri.parse('$base/api/sources?summary=1&limit=1&q=web'),
      headers: headers,
    );
    expect(summaryResponse.statusCode, 200);
    final summaryJson =
        jsonDecode(summaryResponse.body) as Map<String, dynamic>;
    final summary =
        (summaryJson['data'] as List).single as Map<String, dynamic>;
    expect(summary['bookSourceName'], 'Web Source');
    expect(summary['ruleSearch'], isNull);

    final htmlResponse = await http.get(Uri.parse('$base/?token=$token'));
    expect(htmlResponse.statusCode, 200);
    expect(htmlResponse.body, contains('exportAllSources()'));
    expect(htmlResponse.body, contains('downloadCurrentJson()'));
    expect(htmlResponse.body, contains('loadImportFile(event)'));
    expect(htmlResponse.body, contains('loadMoreSources()'));

    final updated = source.toJson()
      ..['id'] = sourceId
      ..['bookSourceName'] = 'Edited Source'
      ..['ruleSearch'] = {'bookList': '.item', 'name': 'a@text'};
    final saveResponse = await http.put(
      Uri.parse('$base/api/sources/$sourceId'),
      headers: headers,
      body: jsonEncode(updated),
    );
    expect(saveResponse.statusCode, 200);

    final saved = (await repo.getAllBookSources()).single;
    expect(saved.bookSourceName, 'Edited Source');
    expect(saved.ruleSearch, contains('bookList'));

    final importResponse = await http.post(
      Uri.parse('$base/api/sources/import'),
      headers: headers,
      body: jsonEncode([
        {
          'sourceName': 'Alias Web Import',
          'sourceUrl': 'https://alias-web.example.com',
          'rulesSearch': {'bookList': 'data.list', 'name': 'title'},
        },
      ]),
    );
    expect(importResponse.statusCode, 200);
    final importJson = jsonDecode(importResponse.body) as Map<String, dynamic>;
    expect(importJson['count'], 1);
    final imported = (await repo.getAllBookSources()).firstWhere(
      (source) => source.bookSourceUrl == 'https://alias-web.example.com',
    );
    expect(imported.bookSourceName, 'Alias Web Import');
    expect(imported.ruleSearch, contains('data.list'));
  });
}
