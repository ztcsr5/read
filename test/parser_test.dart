import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado_parser.dart';

void main() {
  test('Test Biquge source', () async {
    final sourceJson = {
      "bookSourceUrl": "https://www.biquge.com.cn",
      "bookSourceName": "笔趣阁",
      "searchUrl": "/search.php?keyword={{key}}",
      "ruleSearch": {
        "bookList": ".result-item",
        "name": ".result-game-item-title-link@text",
        "author": ".result-game-item-info p:nth-of-type(1) span:nth-of-type(2)@text",
        "bookUrl": ".result-game-item-title-link@href"
      }
    };

    final source = BookSource.fromJson(sourceJson);
    final report = await LegadoParser.testSource(source, '斗破苍穹');
    
    for (final step in report.steps) {
      print('[\${step.status.name.toUpperCase()}] \${step.title}: \${step.message}');
      if (step.sample != null) {
        print('  Sample: \${step.sample}');
      }
    }
  });
}
