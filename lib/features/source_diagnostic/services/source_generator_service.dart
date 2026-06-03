import 'dart:convert';
import 'dart:math';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import 'package:http/http.dart' as http;
import '../../../data/models/book_source.dart';
import 'rule_rank_engine.dart';

class SourceGeneratorService {
  static Future<BookSource> generate(String targetUrl) async {
    final uri = Uri.parse(targetUrl.trim());
    final rootUrl = '${uri.scheme}://${uri.host}';

    final response = await http.get(
      Uri.parse(targetUrl),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('无法连接目标网站，HTTP Code: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    final doc = parse(html);

    // 1. Discover Book Source Name
    final title = doc.querySelector('title')?.text.trim() ?? '';
    final name = title.split(RegExp(r'[\_\-\|]')).first.trim();
    final sourceName = name.isNotEmpty ? name : uri.host;

    // 2. Discover Search Form and Input keys
    String? searchPath;
    final forms = doc.querySelectorAll('form');
    for (final form in forms) {
      final method = form.attributes['method']?.toLowerCase() ?? 'get';
      final action = form.attributes['action']?.trim() ?? '';
      
      final inputs = form.querySelectorAll('input');
      String? keywordParam;
      for (final input in inputs) {
        final nameAttr = input.attributes['name']?.trim() ?? '';
        final type = input.attributes['type']?.toLowerCase() ?? 'text';
        if (nameAttr.isNotEmpty && (type == 'text' || nameAttr.contains('key') || nameAttr.contains('search') || nameAttr.contains('wd') || nameAttr.contains('q'))) {
          keywordParam = nameAttr;
          break;
        }
      }

      if (keywordParam != null) {
        var actionUrl = action.isEmpty ? '/' : action;
        if (!actionUrl.startsWith('http')) {
          if (!actionUrl.startsWith('/')) {
            actionUrl = '/$actionUrl';
          }
        }
        searchPath = '$actionUrl?$keywordParam={{key}}';
        break;
      }
    }

    // 3. Fallback Active Collision checking if form detection failed
    if (searchPath == null) {
      final testPaths = [
        '/search.php?keyword=test',
        '/search?q=test',
        '/search?keyword=test',
        '/search.html?searchkey=test',
        '/index.php?s=tempkey&keyword=test',
      ];

      for (final testPath in testPaths) {
        try {
          final testUrl = '$rootUrl$testPath';
          final testRes = await http.get(
            Uri.parse(testUrl),
            headers: const {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          ).timeout(const Duration(milliseconds: 2500));
          
          if (testRes.statusCode == 200 || testRes.statusCode == 302) {
            searchPath = testPath.replaceAll('test', '{{key}}');
            break;
          }
        } catch (_) {}
      }
    }

    // Secondary fallback
    searchPath ??= '/search?keyword={{key}}';

    // 4. Scan potential candidates from DOM
    final bookListCandidates = RuleRankEngine.rankSelectors(html, 'search');
    final tocCandidates = RuleRankEngine.rankSelectors(html, 'toc');
    final contentCandidates = RuleRankEngine.rankSelectors(html, 'content');

    final bookListRule = bookListCandidates.isNotEmpty ? bookListCandidates.first.selector : '.book-item';
    final tocRule = tocCandidates.isNotEmpty ? tocCandidates.first.selector : 'ul li a';
    final contentRule = contentCandidates.isNotEmpty ? contentCandidates.first.selector : '#content';

    // 5. Construct rules maps
    final searchRuleMap = {
      'bookList': bookListRule,
      'name': 'a@text',
      'author': '.author@text',
      'bookUrl': 'a@href',
      'coverUrl': 'img@src',
    };

    final bookInfoRuleMap = {
      'name': 'h1@text',
      'author': '.author@text',
      'intro': '#intro@text',
      'coverUrl': 'img@src',
      'tocUrl': 'a:contains(目录)@href',
    };

    final tocRuleMap = {
      'chapterList': tocRule,
      'chapterName': 'text',
      'chapterUrl': 'href',
    };

    final contentRuleMap = {
      'content': contentRule,
    };

    final bookSource = BookSource()
      ..bookSourceName = sourceName
      ..bookSourceUrl = rootUrl
      ..enabled = true
      ..searchUrl = searchPath
      ..ruleSearch = jsonEncode(searchRuleMap)
      ..ruleBookInfo = jsonEncode(bookInfoRuleMap)
      ..ruleToc = jsonEncode(tocRuleMap)
      ..ruleContent = jsonEncode(contentRuleMap);

    return bookSource;
  }
}
