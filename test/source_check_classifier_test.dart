import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/features/settings/services/source_check_classifier.dart';

void main() {
  group('source check failure classifier', () {
    test('keeps plain css search miss as a real failure', () {
      final source = BookSource()
        ..bookSourceName = 'Plain'
        ..bookSourceUrl = 'https://plain.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = '{"bookList":".item","name":"a@text"}';

      expect(
        classifySourceCheckFailure(
          source,
          failStep: '搜索结果',
          message: '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
        ),
        SourceCheckFailureClass.failed,
      );
    });

    test('blocks runtime and access dependent misses', () {
      final source = BookSource()
        ..bookSourceName = 'Cookie JS'
        ..bookSourceUrl = 'https://cookie.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = '@js:java.ajax("/api")'
        ..ruleContent = 'body@text'
        ..customConfig = '{"headers":{"Cookie":"sid=1"}}';

      expect(
        classifySourceCheckFailure(
          source,
          failStep: '搜索结果',
          message: '没有解析出书籍',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '正文',
          message: '正文太短，可能需要分页或登录',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '目录',
          message: '没有解析出章节，请检查 ruleToc.chapterList',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '搜索 URL',
          message: 'Node JS fallback failed: JavaImporter is not defined',
        ),
        SourceCheckFailureClass.blocked,
      );
    });

    test('blocks verification and transient network failures', () {
      final source = BookSource()
        ..bookSourceName = 'Verify'
        ..bookSourceUrl = 'https://verify.example.com';

      expect(
        classifySourceCheckFailure(
          source,
          failStep: '站点验证',
          message: '需要跳验证后复测',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '异常',
          message: 'HandshakeException: Connection terminated during handshake',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '搜索结果',
          message: '{"retCode":2,"retMsg":"接口鉴权不合法"}',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(
          source,
          failStep: '目录',
          message: '{"Result":-3,"Message":"签名错误"}',
        ),
        SourceCheckFailureClass.blocked,
      );
      expect(
        classifySourceCheckFailure(source, failStep: '请求搜索页', message: '响应体为空'),
        SourceCheckFailureClass.blocked,
      );
    });

    test('blocks imported js function sources as runtime dependent', () {
      final source = BookSource()
        ..bookSourceName = 'JS Function'
        ..bookSourceUrl = 'https://js.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = '{"bookList":"<js>search(key, page, result)</js>"}'
        ..customConfig =
            '{"engine":"quickjs","sourceFormat":"js","jsLib":"function search(){}"}';

      expect(sourceNeedsRuntimeOrAccess(source), isTrue);
      expect(
        classifySourceCheckFailure(
          source,
          failStep: 'search result',
          message: 'empty result',
        ),
        SourceCheckFailureClass.blocked,
      );
    });

    test('blocks browser, webjs and access state dependent sources', () {
      final source = BookSource()
        ..bookSourceName = 'Browser'
        ..bookSourceUrl = 'https://browser.example.com'
        ..ruleSearch = '@js:java.startBrowser(baseUrl)'
        ..customConfig =
            '{"webJs":"document.body.innerText","headers":{"Cookie":"sid=1"}}';

      expect(sourceNeedsRuntimeOrAccess(source), isTrue);
      expect(
        classifySourceCheckFailure(
          source,
          failStep: 'content',
          message: 'Access denied: rate limit',
        ),
        SourceCheckFailureClass.blocked,
      );
    });
  });
}
