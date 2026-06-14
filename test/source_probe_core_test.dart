import 'package:flutter_test/flutter_test.dart';

import '../tool/source_probe_core.dart';

void main() {
  group('source probe failure classification', () {
    test('treats transient network exceptions as blocked', () {
      final hint = buildCompatHint('异常', const [
        'cookie',
      ], 'HandshakeException: Connection terminated during handshake');

      expect(hint, 'network-transient');
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '异常',
          features: const ['cookie'],
          message: 'HandshakeException: Connection terminated during handshake',
        ),
        isTrue,
      );
    });

    test(
      'does not auto-fail search misses on auth or runtime-heavy sources',
      () {
        expect(
          shouldTreatProbeFailureAsBlocked(
            failStep: '搜索结果',
            features: const ['cookie', 'header', 'login'],
            message: '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
          ),
          isTrue,
        );
        expect(
          shouldTreatProbeFailureAsBlocked(
            failStep: '搜索结果',
            features: const ['@js', 'java.ajax'],
            message: '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
          ),
          isTrue,
        );
      },
    );

    test('keeps plain css search misses as parser failures', () {
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '搜索结果',
          features: const [],
          message: '没有解析出书籍，请检查 ruleSearch.bookList/name/bookUrl',
        ),
        isFalse,
      );
    });

    test('does not auto-fail content misses on gated paginated sources', () {
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '正文',
          features: const ['cookie', 'nextContentUrl'],
          message: '正文太短，可能是登录页、验证页或分页未继续加载',
        ),
        isTrue,
      );
    });

    test('treats auth signatures and empty responses as blocked evidence', () {
      expect(
        buildCompatHint(
          '搜索结果',
          const [],
          '响应内容前缀采样: {"retCode":2,"retMsg":"接口鉴权不合法"}',
        ),
        'auth-or-signature',
      );
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '搜索结果',
          features: const [],
          message: '当前详情页 HTML 响应前缀取证:\n{"Result":-3,"Message":"签名错误"}',
        ),
        isTrue,
      );
      expect(
        buildCompatHint(
          '搜索结果',
          const ['@js', 'java.ajax'],
          '规则包含 Packages.java.security\n响应内容前缀采样: {"retCode":2,"retMsg":"接口鉴权不合法"}',
        ),
        'auth-or-signature',
      );
      expect(
        buildCompatHint(
          '搜索结果',
          const [],
          '搜索页响应内容前缀采样: \n解析得到的书籍数量: 0',
        ),
        'empty-response',
      );
    });

    test('treats unsupported Node JS fallback bridges as blocked', () {
      expect(
        buildCompatHint(
          '搜索 URL',
          const ['@js', 'java.ajax'],
          'Node JS fallback failed: ReferenceError: JavaImporter is not defined',
        ),
        'js-fallback-unsupported',
      );
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '搜索 URL',
          features: const ['@js', 'java.ajax'],
          message:
              'Node JS fallback failed: TypeError: java.desEncodeToBase64String is not a function',
        ),
        isTrue,
      );
    });

    test('does not auto-fail runtime-heavy toc context misses', () {
      expect(
        shouldTreatProbeFailureAsBlocked(
          failStep: '目录',
          features: const ['@js', 'java.get', 'jsonPath'],
          message: '没有解析出章节，请检查 ruleToc.chapterList/chapterName/chapterUrl',
        ),
        isTrue,
      );
    });
  });
}
