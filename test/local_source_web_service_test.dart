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
      ..searchUrl = '/search?q={{key}}';
    final sourceId = await repo.saveBookSource(source);

    final service = LocalSourceWebService(repo);
    await service.start();
    addTearDown(service.stop);

    final token = service.state.accessToken;
    final base = 'http://127.0.0.1:${service.state.port}';
    final headers = {'X-Read-Token': token, 'Content-Type': 'application/json'};

    final listResponse = await http.get(
      Uri.parse('$base/api/sources'),
      headers: headers,
    );
    expect(listResponse.statusCode, 200);
    final listJson = jsonDecode(listResponse.body) as Map<String, dynamic>;
    expect(listJson['ok'], true);
    expect((listJson['data'] as List).single['bookSourceName'], 'Web Source');

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
  });
}
