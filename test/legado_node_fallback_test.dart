import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado/legado_js_engine.dart';
import 'package:read/data/parsers/legado_parser.dart';
import 'package:read/data/parsers/legado/legado_request_builder.dart';

void main() {
  group('LegadoJsEngine Node fallback', () {
    late LegadoJsEngine engine;

    setUp(() {
      engine = LegadoJsEngine();
    });

    bool shouldSkip() => engine.isAvailable || !engine.canEvaluate;

    test('evaluates pure JS and java storage helpers', () {
      if (shouldSkip()) return;

      final value = engine.evaluate(r'''
        @js:
        java.put("probe.key", "v1");
        java.get("probe.key") + ":" + java.md5Encode("abc")
      ''');

      expect(value, 'v1:900150983cd24fb0d6963f7d28e17f72');
    });

    test('evaluates ajax rules with Node fetch for Windows probe', () async {
      if (shouldSkip()) return;

      final value = await engine.evaluateWithAjax(
        '@js:java.ajax("data:text/plain,hello-node")',
        ajax: (_) async => '',
      );

      expect(value, 'hello-node');
    });

    test('extracts json paths through java.getString', () {
      if (shouldSkip()) return;

      final value = engine.evaluate(
        r'@js:java.getString("$.data..content", result)',
        variables: const {
          'result': '{"data":{"items":[{"content":"chapter text"}]}}',
        },
      );

      expect(value, 'chapter text');
    });

    test('evaluates common signing and cipher helpers', () {
      if (shouldSkip()) return;

      expect(
        engine.evaluate(r'@js:java.HMacHex("abc", "HmacMD5", "key")'),
        'd2fe98063f876b03193afb49b4979591',
      );
      expect(
        engine.evaluate(r'@js:java.digestHex("abc", "sha256")'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        engine.evaluate(
          r'@js:java.desEncodeToBase64String("abc", "12345678", "DES/ECB/PKCS5Padding", "")',
        ),
        'wkuY+tXAWA4=',
      );
      expect(
        engine.evaluate(
          r'@js:java.tripleDESEncodeBase64Str("abc", "12345678", "ECB", "PKCS5Padding", "")',
        ),
        'wkuY+tXAWA4=',
      );
      expect(
        engine.evaluate(r'''
          @js:
          var javaImport = new JavaImporter();
          javaImport.importPackage(Packages.javax.crypto, Packages.javax.crypto.spec);
          with (javaImport) {
            var mac = Mac.getInstance("HmacMD5");
            mac.init(SecretKeySpec(String("key").getBytes("UTF-8"), "HmacMD5"));
            mac.doFinal(String("abc").getBytes("UTF-8"))
              .map(v => (v & 255).toString(16).padStart(2, "0"))
              .join("")
          }
        '''),
        'd2fe98063f876b03193afb49b4979591',
      );
    });

    test('tolerates legado tag fragments and repeated let declarations', () {
      if (shouldSkip()) return;

      final value = engine.evaluate(r'''
        <js>
        let key = "a";
        let key = key + "b";
        result = key;
        </js>
      ''');

      expect(value, 'ab');
    });

    test('evaluates @js header objects instead of leaking code to Dio', () {
      final headers = LegadoRequestBuilder.parseHeaderString(r'''
        @js:
        (()=>{
          ua = "com.goreadnovel/1.7.5/test";
          var headers = {"User-Agent": ua};
          return JSON.stringify(headers);
        })()
      ''');

      expect(headers['User-Agent'], 'com.goreadnovel/1.7.5/test');
    });

    test('awaits loginUrl java.ajax helpers loaded through eval', () async {
      if (shouldSkip()) return;

      final loginUrl = JsCompatibilityTransformer.transform(r'''
          function login() {
            var resp = JSON.parse(java.ajax("data:text/plain,%7B%22token%22%3A%22abc%22%7D"));
            source.setVariable(resp.token);
          }
        ''', wrapScript: false);

      final value = await engine.evaluateWithAjax(
        r'''
          @js:
          eval(String(source.loginUrl));
          login();
          "token=" + source.getVariable();
        ''',
        variables: {
          'source': {
            'key': 'https://example.com',
            'bookSourceUrl': 'https://example.com',
            'loginUrl': loginUrl,
          },
        },
        ajax: (_) async => '',
      );

      expect(value, 'token=abc');
    });

    test(
      'imports empty java security packages used by JavaImporter scripts',
      () {
        if (shouldSkip()) return;

        final value = engine.evaluate(r'''
        <js>
        var javaImport = new JavaImporter();
        javaImport.importPackage(
          Packages.java.security,
          Packages.java.security.interfaces,
          Packages.java.security.spec,
          Packages.java.io,
          Packages.java.util
        );
        "ok";
        </js>
      ''');

        expect(value, 'ok');
      },
    );

    test('wraps newline separated raw js search url expressions', () async {
      if (shouldSkip()) return;

      final source = BookSource()
        ..bookSourceName = 'Line JS'
        ..bookSourceUrl = 'http://a.lc1001.com'
        ..searchUrl = r'''
@js:
/* comment */
isGet=false
if(isGet){
java.ajax('https://example.com/login')
}
time=1700000000000
url="POSThttp://a.lc1001.com/app/query/keybooksconsumerKey=LCREAD_ANDROIDpn="+(page-1)*20+"timestamp="+time+"uID=token"
"http://a.lc1001.com/app/query/keybooks?consumerKey=LCREAD_ANDROID&timestamp="+time+"&sign="+java.md5Encode(encodeURIComponent(url))+"&kw="+key+"&pn="+(page-1)*20
'''
        ..ruleSearch = r'{"bookList":"$.data"}';

      final url = await LegadoParser.buildSearchUrl(source, 'abc');

      expect(url, startsWith('http://a.lc1001.com/app/query/keybooks?'));
      expect(url, contains('kw=abc'));
    });
  });
}
