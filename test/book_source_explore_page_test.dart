import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado_parser.dart';
import 'package:read/features/explore/views/book_source_explore_page.dart';

void main() {
  group('book source explore url parsing', () {
    test('parses json explore list and skips separator entries', () {
      final groups = parseExploreUrl(
        '[{"title":"男频","url":""},'
        '{"title":"玄幻","url":"/xuanhuan/{{page}}"}]',
      );

      expect(groups, hasLength(1));
      expect(groups.single.subCategories, hasLength(1));
      expect(groups.single.subCategories.single.name, '玄幻');
      expect(groups.single.subCategories.single.url, '/xuanhuan/{{page}}');
    });

    test('parses text groups and skips empty urls', () {
      final groups = parseExploreUrl(
        '男频::玄幻::/xuanhuan/{{page}}&&都市::/dushi/{{page}}\n'
        '女生::言情::/yanqing/{{page}}&&分隔::',
      );

      expect(groups, hasLength(2));
      expect(groups[0].name, '男频');
      expect(groups[0].subCategories.map((item) => item.name), ['玄幻', '都市']);
      expect(groups[1].subCategories.map((item) => item.name), ['言情']);
    });

    test('evaluates javascript generated explore url', () async {
      final source = BookSource()
        ..bookSourceName = 'JS Explore'
        ..bookSourceUrl = 'https://example.com'
        ..exploreUrl = '''
<js>
var list = [];
list.push("玄幻::/xuanhuan/{{page}}");
list.push("都市::/dushi/{{page+1}}");
list.join("\\n");
</js>
''';

      final output = await LegadoParser.buildExploreUrl(source);
      final groups = parseExploreUrl(output);

      expect(output, contains('/dushi/2'));
      expect(groups.single.subCategories.map((item) => item.name), [
        '玄幻',
        '都市',
      ]);
    });
  });
}
