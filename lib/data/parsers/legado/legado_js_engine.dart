import 'dart:convert';
import 'package:quickjs_engine/quickjs_engine.dart';

class LegadoJsEngine {
  static final LegadoJsEngine _instance = LegadoJsEngine._internal();
  factory LegadoJsEngine() => _instance;

  JavascriptRuntime? _runtime;

  LegadoJsEngine._internal() {
    try {
      _runtime = getJavascriptRuntime();
      _initJavaObject();
    } catch (e) {
      print('JS Engine Initialization Error: \$e');
    }
  }

  void _initJavaObject() {
    // 注入 Legado 依赖的 JS 桥接对象和 Polyfill
    final jsCode = '''
      var __java_store = {};
      
      var java = {
        put: function(key, value) {
          __java_store[key] = value;
          return value;
        },
        get: function(key) {
          return __java_store[key] || "";
        },
        getString: function(key) {
          return this.get(key);
        },
        ajax: function(urlStr) {
          try {
            var url = urlStr;
            var options = {};
            if (urlStr.indexOf(",") > 0) {
              var parts = urlStr.split(",");
              url = parts[0];
              try {
                options = JSON.parse(parts.slice(1).join(","));
              } catch(e) {}
            }
            var xhr = new XMLHttpRequest();
            var method = options.method ? options.method.toUpperCase() : "GET";
            // 第三个参数为 false 表示同步请求
            xhr.open(method, url, false); 
            if (options.headers) {
              for (var k in options.headers) {
                xhr.setRequestHeader(k, options.headers[k]);
              }
            }
            xhr.send(options.body || null);
            return xhr.responseText;
          } catch(e) {
            return e.toString();
          }
        },
        base64Encode: function(str) {
          return btoa(unescape(encodeURIComponent(str)));
        },
        base64Decode: function(str) {
          return decodeURIComponent(escape(atob(str)));
        },
        md5Encode: function(string) {
          // 极简 JS MD5 实现
          function md5cycle(x, k) {
            var a = x[0], b = x[1], c = x[2], d = x[3];
            a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586); c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
            a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426); c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
            a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417); c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
            a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101); c = ff(c, d, a, b, k[14], 17, -1502002290); b = ff(b, c, d, a, k[15], 22, 1236535329);
            a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632); c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
            a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083); c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
            a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690); c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
            a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784); c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
            a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463); c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
            a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353); c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
            a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222); c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
            a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835); c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
            a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415); c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
            a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606); c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
            a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744); c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
            a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379); c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
            x[0] = add32(a, x[0]); x[1] = add32(b, x[1]); x[2] = add32(c, x[2]); x[3] = add32(d, x[3]);
          }
          function cmn(q, a, b, x, s, t) { a = add32(add32(a, q), add32(x, t)); return add32((a << s) | (a >>> (32 - s)), b); }
          function ff(a, b, c, d, x, s, t) { return cmn((b & c) | ((~b) & d), a, b, x, s, t); }
          function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & (~d)), a, b, x, s, t); }
          function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
          function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | (~d)), a, b, x, s, t); }
          function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
          function md51(s) {
            var n = s.length, state = [1732584193, -271733879, -1732584194, 271733878], i;
            for (i = 64; i <= s.length; i += 64) { md5cycle(state, md5blk(s.substring(i - 64, i))); }
            s = s.substring(i - 64);
            var tail = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
            for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
            tail[i >> 2] |= 0x80 << ((i % 4) << 3);
            if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
            tail[14] = n * 8; md5cycle(state, tail); return state;
          }
          function md5blk(s) {
            var md5blks = [], i;
            for (i = 0; i < 64; i += 4) { md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24); }
            return md5blks;
          }
          function hex(x) {
            var hex_chr = '0123456789abcdef', str = '', i;
            for (i = 0; i < 4; i++) str += hex_chr.charAt((x >> (i * 8 + 4)) & 0x0F) + hex_chr.charAt((x >> (i * 8)) & 0x0F);
            return str;
          }
          function md5(s) {
            var state = md51(unescape(encodeURIComponent(s))), str = '', i;
            for (i = 0; i < 4; i++) str += hex(state[i]);
            return str;
          }
          return md5(string);
        },
        timeFormat: function(timestamp) {
          return new Date(timestamp).toLocaleString();
        }
      };

      var cookie = {
        getCookie: function(url) { return ""; },
        setCookie: function(url, c) { }
      };
      
      var cache = {
        getFromCache: function(key) { return ""; },
        putInCache: function(key, value, time) { }
      };
    ''';

    if (_runtime == null) return;
    try {
      final result = _runtime!.evaluate(jsCode);
      if (result.isError) {
        print('JS Engine Initialization Error: \${result.stringResult}');
      }
    } catch (e) {
      print('JS Engine init failed: \$e');
    }
  }

  /// 执行一段 JS 代码
  /// [jsCode] 可以带有 @js: 或 <js> 包裹
  /// [variables] 会作为全局变量注入到上下文中，例如 baseUrl, result 等
  String evaluate(String jsCode, {Map<String, dynamic>? variables}) {
    if (_runtime == null) return '';

    if (variables != null) {
      try {
        variables.forEach((key, value) {
          final encodedValue = jsonEncode(value);
          _runtime!.evaluate('var \$key = \$encodedValue;');
        });
      } catch (e) {
        print('JS variables injection failed: \$e');
      }
    }

    String codeToRun = jsCode.trim();
    if (codeToRun.startsWith('@js:')) {
      codeToRun = codeToRun.substring(4);
    } else if (codeToRun.startsWith('<js>') && codeToRun.endsWith('</js>')) {
      codeToRun = codeToRun.substring(4, codeToRun.length - 5);
    }

    // 处理包含 return 但没有包在函数里的情况
    if (codeToRun.contains('return ') && !codeToRun.contains('function')) {
      codeToRun = '(function() { \$codeToRun })()';
    }

    try {
      final result = _runtime!.evaluate(codeToRun);
      if (result.isError) {
        throw Exception(result.stringResult);
      }
      return result.stringResult;
    } catch (e) {
      print('JS Eval failed: \$e');
      throw Exception('JS执行异常: \$e');
    }
  }

  void dispose() {
    _runtime?.dispose();
  }
}
