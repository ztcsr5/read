import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/parsers/source_import_link_parser.dart';

void main() {
  group('SourceImportLinkParser', () {
    test('keeps http json urls as urls', () {
      final input = SourceImportLinkParser.parse('https://example.com/a.json');

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/a.json');
    });

    test('recognizes pasted json', () {
      final input = SourceImportLinkParser.parse('[{"bookSourceName":"A"}]');

      expect(input.kind, SourceImportInputKind.json);
      expect(input.value, '[{"bookSourceName":"A"}]');
    });

    test('extracts src from yuedu import links', () {
      final input = SourceImportLinkParser.parse(
        'yuedu://booksource/importonline?src=https%3A%2F%2Fexample.com%2Fsources.json',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/sources.json');
    });

    test('extracts url from other import schemes', () {
      final input = SourceImportLinkParser.parse(
        'legado://import?url=https%3A%2F%2Fexample.com%2Fpack.json',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/pack.json');
    });

    test('extracts src from modern legado links', () {
      final input = SourceImportLinkParser.parse(
        'legado://import/bookSource?src=https%3A%2F%2Fexample.com%2Fsource.json',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/source.json');
    });

    test('extracts url from nested share text', () {
      final input = SourceImportLinkParser.parse(
        '阅读导入链接 yuedu://rsssource/importonline?url=https%3A%2F%2Fexample.com%2Frss.json',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/rss.json');
    });

    test('extracts urls from shared text', () {
      final input = SourceImportLinkParser.parse(
        '分享一个书源 https://example.com/source.json 可以导入',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/source.json');
    });

    test('trims punctuation around shared urls', () {
      final input = SourceImportLinkParser.parse(
        '导入地址：https://example.com/source.json）；',
      );

      expect(input.kind, SourceImportInputKind.url);
      expect(input.value, 'https://example.com/source.json');
    });

    test('marks import scheme without src as unsupported', () {
      final input = SourceImportLinkParser.parse(
        'yuedu://booksource/importonline',
      );

      expect(input.kind, SourceImportInputKind.unsupportedScheme);
    });
  });
}
