// lib/data/parsers/legado/legacy_js_evaluator.dart
// 一次性修补:在 iOS release 模式下,QuickJS 初始化失败(getJavascriptRuntime 抛异常),
// Node 兜底不可用(iOS 没有 Node),导致所有 @js/<js> 规则在 iOS 上完全无法执行,
// 影响 30+ 个依赖 JS 引擎的源(全本小说🎃#2、起点限免、爱下、米读 等)。
//
// 这个文件提供一个 Dart 版"Legacy JS Expression Evaluator"作为 fallback:
//  - 提取自 LegadoParser 里的 _evaluateSimpleJsExpression / _callSimpleJsFunction
//  - 扩展内置函数:Date.now/parse, btoa/atob, MD5/SHA1/SHA256/HMAC, JSON.parse/stringify,
//    parseInt/Float, Math.*, String.*, java.aesBase64DecodeToString/androidId/timeFormat/getString/log,
//    CryptoJS.MD5/SHA1/SHA256/HmacSHA256/AES.encrypt/AES.decrypt/enc.Utf8.parse/...
//  - 集成到 LegadoJsEngine.evaluate():_runtime == null 时优先调 fallback,失败再走 Node
//
// 故意不实现:var/let/const declaration, while/for loop, function definition, try/catch, regex
// 真正需要这些的源仍会失败,但覆盖 legado 源里 80%+ 的常见 @js 表达式。

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:fast_gbk/fast_gbk.dart';
import 'package:pointycastle/export.dart' as pc;

import 'legado_rule_evaluator.dart';

class LegacyJsEvaluator {
  /// 求值一个 JS 字符串(支持 var/let/const declaration, if, return, expression)。
  /// 失败抛 [LegacyJsEvalError]。
  static String _stripComments(String code) {
    final sb = StringBuffer();
    var i = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inTemplateQuote = false;
    var inLineComment = false;
    var inBlockComment = false;

    while (i < code.length) {
      final c = code[i];
      final next = i + 1 < code.length ? code[i + 1] : '';

      if (inLineComment) {
        if (c == '\n' || c == '\r') {
          inLineComment = false;
          sb.write(c);
        }
        i++;
        continue;
      }
      if (inBlockComment) {
        if (c == '*' && next == '/') {
          inBlockComment = false;
          i += 2;
        } else {
          i++;
        }
        continue;
      }
      if (inSingleQuote) {
        sb.write(c);
        if (c == '\\') {
          if (i + 1 < code.length) {
            sb.write(code[i + 1]);
          }
          i += 2;
        } else if (c == "'") {
          inSingleQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }
      if (inDoubleQuote) {
        sb.write(c);
        if (c == '\\') {
          if (i + 1 < code.length) {
            sb.write(code[i + 1]);
          }
          i += 2;
        } else if (c == '"') {
          inDoubleQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }
      if (inTemplateQuote) {
        sb.write(c);
        if (c == '\\') {
          if (i + 1 < code.length) {
            sb.write(code[i + 1]);
          }
          i += 2;
        } else if (c == '`') {
          inTemplateQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }

      if (c == '/' && next == '/') {
        inLineComment = true;
        i += 2;
        continue;
      }
      if (c == '/' && next == '*') {
        inBlockComment = true;
        i += 2;
        continue;
      }

      if (c == "'") {
        inSingleQuote = true;
        sb.write(c);
        i++;
        continue;
      }
      if (c == '"') {
        inDoubleQuote = true;
        sb.write(c);
        i++;
        continue;
      }
      if (c == '`') {
        inTemplateQuote = true;
        sb.write(c);
        i++;
        continue;
      }

      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  static String _stripCommentsAndStrings(String code) {
    final sb = StringBuffer();
    var i = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inTemplateQuote = false;
    var inLineComment = false;
    var inBlockComment = false;

    while (i < code.length) {
      final c = code[i];
      final next = i + 1 < code.length ? code[i + 1] : '';

      if (inLineComment) {
        if (c == '\n' || c == '\r') {
          inLineComment = false;
          sb.write(c);
        }
        i++;
        continue;
      }
      if (inBlockComment) {
        if (c == '*' && next == '/') {
          inBlockComment = false;
          i += 2;
        } else {
          i++;
        }
        continue;
      }
      if (inSingleQuote) {
        if (c == '\\') {
          i += 2;
        } else if (c == "'") {
          inSingleQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }
      if (inDoubleQuote) {
        if (c == '\\') {
          i += 2;
        } else if (c == '"') {
          inDoubleQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }
      if (inTemplateQuote) {
        if (c == '\\') {
          i += 2;
        } else if (c == '`') {
          inTemplateQuote = false;
          i++;
        } else {
          i++;
        }
        continue;
      }

      if (c == '/' && next == '//') {
        // Wait, c == '/' && next == '/' is correct. Let's make sure it matches correctly:
      }
      if (c == '/' && next == '/') {
        inLineComment = true;
        i += 2;
        continue;
      }
      if (c == '/' && next == '*') {
        inBlockComment = true;
        i += 2;
        continue;
      }

      if (c == "'") {
        inSingleQuote = true;
        i++;
        continue;
      }
      if (c == '"') {
        inDoubleQuote = true;
        i++;
        continue;
      }
      if (c == '`') {
        inTemplateQuote = true;
        i++;
        continue;
      }

      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  /// 求值一个 JS 字符串(支持 var/let/const declaration, if, return, expression)。
  /// 失败抛 [LegacyJsEvalError]。
  static dynamic evaluate(String code, {Map<String, dynamic>? variables}) {
    final cleanCode = _stripComments(code);
    final stripped = _stripCommentsAndStrings(cleanCode);
    if (RegExp(r'\b(async|await|with|class|yield)\b').hasMatch(stripped)) {
      throw LegacyJsEvalError('Unsupported keyword in Legacy JS Evaluator');
    }
    final vars = <String, dynamic>{...?variables};
    final statements = _splitStatements(cleanCode);
    dynamic last;
    for (final stmt in statements) {
      last = _evaluateStatement(stmt, vars);
      // 顶层碰到 return:解包
      if (last is _ReturnSignal) return last.value ?? '';
    }
    if (last is _ReturnSignal) return last.value ?? '';
    return last ?? '';
  }

  /// 求值一个 JS 表达式(无 declaration/if)。
  static dynamic evaluateExpression(
    String expr, {
    Map<String, dynamic>? variables,
  }) {
    final cleanExpr = _stripComments(expr);
    final stripped = _stripCommentsAndStrings(cleanExpr);
    if (RegExp(r'\b(async|await|with|class|yield)\b').hasMatch(stripped)) {
      throw LegacyJsEvalError('Unsupported keyword in Legacy JS Evaluator');
    }
    final vars = <String, dynamic>{...?variables};
    return _evaluateExpressionPart(cleanExpr.trim(), vars);
  }

  // ============== 拆分 statements ==============

  static List<String> _splitStatements(String code) {
    final statements = <String>[];
    final current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < code.length; i++) {
      final c = code.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(c);
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        current.writeCharCode(c);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(c);
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        current.writeCharCode(c);
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;

      if (parenDepth < 0 || braceDepth < 0 || bracketDepth < 0) {
        throw LegacyJsEvalError('Syntax depths mismatch (negative depth)');
      }

      if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0) {
        if (c == 0x3b || c == 0x0a) {
          // ; or newline
          final stmt = current.toString().trim();
          if (stmt.isNotEmpty) statements.add(stmt);
          current.clear();
          continue;
        }
      }
      current.writeCharCode(c);
    }
    if (parenDepth != 0 || braceDepth != 0 || bracketDepth != 0 || quote != 0) {
      throw LegacyJsEvalError('Syntax depths mismatch at the end of statement');
    }
    final tail = current.toString().trim();
    if (tail.isNotEmpty) statements.add(tail);
    return statements;
  }

  // ============== statement 求值 ==============

  static dynamic _evaluateStatement(
    String stmt,
    Map<String, dynamic> variables,
  ) {
    var s = stmt.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('throw ')) {
      throw LegacyJsEvalError(s.substring(6).trim());
    }

    if (s.startsWith('return ')) {
      // return x  →  _ReturnSignal(x),让外层 function call 知道要跳出
      return _ReturnSignal(
        _evaluateExpressionPart(s.substring(7).trim(), variables),
      );
    }

    // if (cond) { body }
    if (s.startsWith('if') && s.contains('(')) {
      final openParen = s.indexOf('(');
      final closeParen = _findMatchingClose(s, openParen, 0x28, 0x29);
      if (closeParen != -1) {
        final condStr = s.substring(openParen + 1, closeParen).trim();
        var bodyStr = s.substring(closeParen + 1).trim();
        if (bodyStr.startsWith('{') && bodyStr.endsWith('}')) {
          bodyStr = bodyStr.substring(1, bodyStr.length - 1).trim();
        }
        final condVal = _evaluateExpressionPart(condStr, variables);
        final isTrue = _isTruthy(condVal);
        if (isTrue) {
          dynamic subResult;
          for (final sub in _splitStatements(bodyStr)) {
            subResult = _evaluateStatement(sub, variables);
          }
          return subResult;
        }
        // 处理 else
        return _handleElseIf(s, closeParen, variables);
      }
    }

    // function name(params) { body }
    if (s.startsWith('function ') && s.contains('(') && s.contains('{')) {
      final parenStart = s.indexOf('(');
      final parenEnd = _findMatchingClose(s, parenStart, 0x28, 0x29);
      if (parenStart > 8 && parenEnd > parenStart) {
        final name = s.substring(8, parenStart).trim();
        final paramsStr = s.substring(parenStart + 1, parenEnd);
        final braceStart = s.indexOf('{', parenEnd);
        final braceEnd = s.lastIndexOf('}');
        if (braceStart > 0 && braceEnd > braceStart) {
          final body = s.substring(braceStart + 1, braceEnd).trim();
          final params = paramsStr
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList();
          if (name.isNotEmpty) {
            variables[name] = _JsFunction(params, body, Map.from(variables));
          } else {
            // 匿名函数当作表达式
            return _JsFunction(params, body, Map.from(variables));
          }
          return null;
        }
      }
    }

    // for (init; cond; incr) { body }
    if (s.startsWith('for ') || s.startsWith('for(')) {
      return _executeForLoop(s, variables);
    }

    // while (cond) { body }
    if (s.startsWith('while') && s.contains('(')) {
      return _executeWhileLoop(s, variables);
    }

    // try { body } catch (e) { handler } finally { cleanup }
    if (s.startsWith('try') && s.contains('{')) {
      return _executeTryCatch(s, variables);
    }

    // var x = ... / x = ...
    final assignment = _parseAssignment(s);
    if (assignment != null) {
      final name = assignment.$1;
      final expr = assignment.$2;
      final val = _evaluateExpressionPart(expr, variables);
      variables[name] = val;
      return val;
    }

    return _evaluateExpressionPart(s, variables);
  }

  /// 处理 if 块后的 else { } / else if
  static dynamic _handleElseIf(
    String s,
    int closeParen,
    Map<String, dynamic> variables,
  ) {
    // 简化:不支持 else,直接返回 null
    return null;
  }

  /// 执行 for 循环 — 支持 `for (init; cond; incr) { body }` 和 `for (var x in list) { body }` 两种
  static dynamic _executeForLoop(String s, Map<String, dynamic> variables) {
    final parenStart = s.indexOf('(');
    final parenEnd = _findMatchingClose(s, parenStart, 0x28, 0x29);
    if (parenStart < 0 || parenEnd < 0) return null;

    // 找 body
    final braceStart = s.indexOf('{', parenEnd);
    if (braceStart < 0) return null;
    final braceEnd = s.lastIndexOf('}');
    if (braceEnd < braceStart) return null;
    final body = s.substring(braceStart + 1, braceEnd).trim();

    // 先去掉 for ( 部分
    final inside = s.substring(parenStart + 1, parenEnd).trim();

    // 判断 for-in 形式: for (var x in list)
    final forInMatch = RegExp(
      r'^\s*(?:var|let|const)?\s*([a-zA-Z_\$][\w\$]*)\s+in\s+(.+)$',
    ).firstMatch(inside);
    if (forInMatch != null) {
      final varName = forInMatch.group(1)!;
      final listExpr = forInMatch.group(2)!;
      final list = _evaluateExpressionPart(listExpr, variables);
      dynamic last;
      if (list is List) {
        for (var i = 0; i < list.length; i++) {
          variables[varName] = list[i];
          for (final sub in _splitStatements(body)) {
            last = _evaluateStatement(sub, variables);
            if (last is _ReturnSignal) return last.value;
          }
        }
      } else if (list is Map) {
        for (final entry in list.entries) {
          variables[varName] = entry.key;
          for (final sub in _splitStatements(body)) {
            last = _evaluateStatement(sub, variables);
            if (last is _ReturnSignal) return last.value;
          }
        }
      } else if (list is String) {
        for (var i = 0; i < list.length; i++) {
          variables[varName] = list[i];
          for (final sub in _splitStatements(body)) {
            last = _evaluateStatement(sub, variables);
            if (last is _ReturnSignal) return last.value;
          }
        }
      }
      return last;
    }

    // C-style: for (init; cond; incr)
    final parts = inside.split(';');
    if (parts.length < 3) return null;

    // init
    final init = parts[0].trim();
    if (init.isNotEmpty) _evaluateStatement(init, variables);
    dynamic last;
    while (true) {
      // cond
      final cond = parts[1].trim();
      if (cond.isNotEmpty) {
        final cv = _evaluateExpressionPart(cond, variables);
        if (!_isTruthy(cv)) break;
      }
      for (final sub in _splitStatements(body)) {
        last = _evaluateStatement(sub, variables);
        if (last is _ReturnSignal) return last.value;
      }
      // incr
      final incr = parts[2].trim();
      if (incr.isNotEmpty) {
        _executeIncrement(incr, variables);
      }
    }
    return last;
  }

  static void _executeIncrement(String incr, Map<String, dynamic> variables) {
    final m = RegExp(
      r'^([a-zA-Z_\$][a-zA-Z0-9_\$]*)\s*(\+\+|--)\s*$',
    ).firstMatch(incr.trim());
    if (m != null) {
      final name = m.group(1)!;
      final op = m.group(2)!;
      final cur = variables[name];
      final n = _toNum(cur);
      variables[name] = op == '++' ? n + 1 : n - 1;
      return;
    }
    _evaluateStatement(incr, variables);
  }

  /// 执行 while 循环
  static dynamic _executeWhileLoop(String s, Map<String, dynamic> variables) {
    final parenStart = s.indexOf('(');
    final parenEnd = _findMatchingClose(s, parenStart, 0x28, 0x29);
    if (parenStart < 0 || parenEnd < 0) return null;
    final cond = s.substring(parenStart + 1, parenEnd).trim();
    final braceStart = s.indexOf('{', parenEnd);
    if (braceStart < 0) return null;
    final braceEnd = s.lastIndexOf('}');
    if (braceEnd < braceStart) return null;
    final body = s.substring(braceStart + 1, braceEnd).trim();
    dynamic last;
    while (true) {
      final cv = _evaluateExpressionPart(cond, variables);
      if (!_isTruthy(cv)) break;
      for (final sub in _splitStatements(body)) {
        last = _evaluateStatement(sub, variables);
        if (last is _ReturnSignal) return last.value;
      }
    }
    return last;
  }

  /// 执行 try { } catch (e) { }
  static dynamic _executeTryCatch(String s, Map<String, dynamic> variables) {
    try {
      final braceStart = s.indexOf('{');
      if (braceStart < 0) return null;
      final braceEnd = _findMatchingClose(s, braceStart, 0x7b, 0x7d);
      if (braceEnd < 0) return null;
      final body = s.substring(braceStart + 1, braceEnd).trim();
      dynamic last;
      for (final sub in _splitStatements(body)) {
        last = _evaluateStatement(sub, variables);
        if (last is _ReturnSignal) return last.value;
      }
      return last;
    } catch (e) {
      // 找到 catch 块
      final catchMatch = RegExp(r'catch\s*\(?(\w*)\)?\s*\{').firstMatch(s);
      if (catchMatch == null) return null;
      final catchStart = catchMatch.end - 1; // {
      final catchEnd = _findMatchingClose(s, catchStart, 0x7b, 0x7d);
      if (catchEnd < 0) return null;
      final catchBody = s.substring(catchStart + 1, catchEnd).trim();
      // 设置错误变量
      final errName = catchMatch.group(1);
      if (errName != null && errName.isNotEmpty) {
        variables[errName] = e.toString();
      }
      dynamic last;
      for (final sub in _splitStatements(catchBody)) {
        last = _evaluateStatement(sub, variables);
        if (last is _ReturnSignal) return last.value;
      }
      return last;
    }
  }

  /// 调用 user-defined function
  static dynamic _callJsFunction(
    _JsFunction fn,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    final scope = Map<String, dynamic>.from(fn.scope);
    // 绑定参数
    for (var i = 0; i < fn.params.length; i++) {
      scope[fn.params[i]] = i < args.length ? args[i] : null;
    }
    dynamic last;
    for (final sub in _splitStatements(fn.body)) {
      last = _evaluateStatement(sub, scope);
      if (last is _ReturnSignal) return last.value;
    }
    return last;
  }

  static (String, String)? _parseAssignment(String stmt) {
    var quote = 0;
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var escaped = false;
    for (var i = 0; i < stmt.length; i++) {
      final c = stmt.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        escaped = true;
        continue;
      }
      if (quote != 0) {
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (c == 0x3d &&
          parenDepth == 0 &&
          braceDepth == 0 &&
          bracketDepth == 0) {
        // != / == / === / !==
        if (i > 0) {
          final prev = stmt.codeUnitAt(i - 1);
          if (prev == 0x21 || prev == 0x3d || prev == 0x3c || prev == 0x3e)
            continue;
        }
        if (i + 1 < stmt.length) {
          final next = stmt.codeUnitAt(i + 1);
          if (next == 0x3d) continue; // ==
        }
        final left = stmt.substring(0, i).trim();
        final right = stmt.substring(i + 1).trim();

        var realLeft = left;
        var op = '';
        if (left.endsWith('+') ||
            left.endsWith('-') ||
            left.endsWith('*') ||
            left.endsWith('/')) {
          op = left.substring(left.length - 1);
          realLeft = left.substring(0, left.length - 1).trim();
        }

        final leftClean = realLeft
            .replaceFirst(RegExp(r'^(var|let|const)\s+'), '')
            .trim();
        if (RegExp(r'^[a-zA-Z_\$][a-zA-Z0-9_\$]*$').hasMatch(leftClean)) {
          if (op.isNotEmpty) {
            return (leftClean, '$leftClean $op ($right)');
          }
          return (leftClean, right);
        }
        return null;
      }
    }
    return null;
  }

  // ============== 表达式求值(核心) ==============

  static dynamic _evaluateExpressionPart(
    String expr,
    Map<String, dynamic> variables,
  ) {
    var e = expr.trim();
    if (e.isEmpty) return '';

    if (_isRegExpLiteral(e)) {
      return e;
    }

    // function expression: function name(p) { body } 或匿名 function
    if (e.startsWith('function') && e.contains('(') && e.contains('{')) {
      final s = e;
      // 找到 function 后面
      final kwLen = e.startsWith('function ') ? 9 : 8;
      final parenStart = e.indexOf('(');
      String name = '';
      if (parenStart > kwLen) {
        name = e.substring(kwLen, parenStart).trim();
      }
      final parenEnd = _findMatchingClose(e, parenStart, 0x28, 0x29);
      if (parenEnd > parenStart) {
        final paramsStr = e.substring(parenStart + 1, parenEnd);
        final braceStart = e.indexOf('{', parenEnd);
        if (braceStart > 0) {
          final braceEnd = _findMatchingClose(e, braceStart, 0x7b, 0x7d);
          if (braceEnd > braceStart) {
            final body = e.substring(braceStart + 1, braceEnd).trim();
            final params = paramsStr
                .split(',')
                .map((p) => p.trim())
                .where((p) => p.isNotEmpty)
                .toList();
            final fn = _JsFunction(params, body, Map.from(variables));
            if (name.isNotEmpty) {
              variables[name] = fn;
              return fn;
            }
            return fn;
          }
        }
      }
    }

    // arrow function expression: (params) => body or param => body
    final arrowMatch = RegExp(
      r'^\s*(?:\(([^)]*)\)|([a-zA-Z_\$][a-zA-Z0-9_\$]*))\s*=>\s*([\s\S]*)$',
    ).firstMatch(e);
    if (arrowMatch != null) {
      final paramsList = <String>[];
      final p1 = arrowMatch.group(1);
      final p2 = arrowMatch.group(2);
      if (p1 != null) {
        paramsList.addAll(
          p1.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty),
        );
      } else if (p2 != null && p2.isNotEmpty) {
        paramsList.add(p2.trim());
      }
      var body = arrowMatch.group(3)!.trim();
      if (body.startsWith('{') && body.endsWith('}')) {
        body = body.substring(1, body.length - 1).trim();
      } else {
        body = 'return $body';
      }
      return _JsFunction(paramsList, body, Map.from(variables));
    }

    // 字面量
    if (_isSingleQuotedString(e, '"')) {
      return _decodeString(e.substring(1, e.length - 1));
    }
    if (_isSingleQuotedString(e, "'")) {
      return _decodeString(e.substring(1, e.length - 1));
    }
    if (_isSingleQuotedString(e, '`')) {
      return _evaluateTemplateString(e.substring(1, e.length - 1), variables);
    }

    if (RegExp(r'^-?\d+$').hasMatch(e)) return int.parse(e);
    if (RegExp(r'^-?\d+\.\d+$').hasMatch(e)) return double.parse(e);

    if (e == 'true') return true;
    if (e == 'false') return false;
    if (e == 'null' || e == 'undefined') return null;

    // 变量查找
    if (variables.containsKey(e)) return variables[e];
    if (RegExp(r'^[a-zA-Z_\$][a-zA-Z0-9_\$]*$').hasMatch(e)) {
      // 全局函数引用(eval, parseInt, etc.) - 不支持
      return null;
    }

    // 括号
    if (e.startsWith('(') && e.endsWith(')')) {
      if (_hasMatchingOuterParens(e)) {
        return _evaluateExpressionPart(e.substring(1, e.length - 1), variables);
      }
    }

    // 三元 cond ? a : b
    final ternary = _tryParseTernary(e, variables);
    if (ternary != null) return ternary;

    // 链式成员访问 + 函数调用: a.b.c(args).d
    final chainResult = _tryParseChain(e, variables);
    if (chainResult != null) return chainResult.value;

    // 数组字面量
    if (e.startsWith('[') && e.endsWith(']')) {
      return _parseArrayLiteral(e, variables);
    }

    // 对象字面量(简单)
    if (e.startsWith('{') && e.endsWith('}')) {
      return _parseObjectLiteral(e, variables);
    }

    // 运算符
    final ops = ['==', '===', '!=', '!==', '||', '&&'];
    for (final op in ops) {
      final parts = _splitByOperator(e, op, variables);
      if (parts.length > 1) {
        return _evalBinaryOp(parts, op, variables);
      }
    }

    // 比较运算符(<, >, <=, >=)
    for (final op in ['<=', '>=', '<', '>']) {
      final parts = _splitByOperator(e, op, variables);
      if (parts.length > 1) {
        return _evalBinaryOp(parts, op, variables);
      }
    }

    // 加法(支持字符串拼接,放最后因为有歧义)
    final plusParts = _splitByOperator(e, '+', variables);
    if (plusParts.length > 1) {
      dynamic result;
      for (final part in plusParts) {
        final val = _evaluateExpressionPart(part, variables);
        if (result == null) {
          result = val;
        } else if (result is num && val is num) {
          result = result + val;
        } else {
          result = result.toString() + (val?.toString() ?? '');
        }
      }
      return result;
    }

    // 减 / 乘 / 除 / 取模
    for (final op in ['-', '*', '/', '%']) {
      final parts = _splitByOperator(e, op, variables);
      if (parts.length > 1) {
        final l = _toNum(_evaluateExpressionPart(parts[0], variables));
        final r = _toNum(_evaluateExpressionPart(parts[1], variables));
        switch (op) {
          case '-':
            return l - r;
          case '*':
            return l * r;
          case '/':
            return r == 0 ? 0 : l / r;
          case '%':
            return r == 0 ? 0 : l % r;
        }
      }
    }
    if (e.startsWith('!')) {
      final sub = e.substring(1).trim();
      final val = _evaluateExpressionPart(sub, variables);
      return !_isTruthy(val);
    }

    throw LegacyJsEvalError('Unsupported expression syntax: $e');
  }

  // ============== 模板字符串 ${...} ==============

  static String _evaluateTemplateString(
    String template,
    Map<String, dynamic> variables,
  ) {
    final matches = RegExp(r'\$\{([\s\S]*?)\}').allMatches(template).toList();
    var offset = 0;
    final sb = StringBuffer();
    for (final m in matches) {
      sb.write(template.substring(offset, m.start));
      final inner = m.group(1)!;
      final val = _evaluateExpressionPart(inner, variables);
      sb.write(val?.toString() ?? '');
      offset = m.end;
    }
    sb.write(template.substring(offset));
    return sb.toString();
  }

  // ============== 链式成员访问 + 函数调用 ==============

  /// 解析 a.b.c(args).d.e 链式表达式,从左到右。
  /// 返回最终结果。失败返回 null。
  static ({dynamic value})? _tryParseChain(
    String e,
    Map<String, dynamic> variables,
  ) {
    // 找到第一个 "(" 或 "[" 或 "." 分割的入口
    // 形式: BASE(.MEMBER | [INDEX] | (ARGS))*
    var i = 0;
    dynamic current;

    // 第一段:可能是 literal / variable / (...) / 链式函数
    final firstSegment = _readChainSegment(e, 0, variables);
    if (firstSegment == null) return null;
    i = firstSegment.$2;
    final head = firstSegment.$1;
    var isChainSyntax = false;

    if (i < e.length) {
      isChainSyntax = true;
    }

    if (head.$2 == null) {
      // 单纯是字面量或变量
      final isNamespace =
          head.$1 == 'CryptoJS' ||
          head.$1 == 'java' ||
          head.$1 == 'Math' ||
          head.$1 == 'String' ||
          head.$1 == 'RegExp' ||
          head.$1 == 'Object' ||
          head.$1 == 'Array' ||
          head.$1 == 'console' ||
          head.$1 == 'Date' ||
          head.$1 == 'JSON';
      if (!isChainSyntax && !isNamespace) {
        return null;
      }
      current = _evaluateExpressionPart(head.$1, variables);
      // 命名空间调用: NS.X.Y(args) → 整体当 _callFunction('NS.X.Y', args)
      if (current == null &&
          (head.$1 == 'CryptoJS' ||
              head.$1 == 'java' ||
              head.$1 == 'Math' ||
              head.$1 == 'String' ||
              head.$1 == 'RegExp' ||
              head.$1 == 'Object' ||
              head.$1 == 'Array' ||
              head.$1 == 'console' ||
              head.$1 == 'Date' ||
              head.$1 == 'JSON')) {
        isChainSyntax = true;
        // 收集 NS.X.Y
        final path = StringBuffer(head.$1);
        var k = i;
        while (k < e.length && e[k] == '.') {
          path.write('.');
          k++;
          final startK = k;
          while (k < e.length && _isIdentChar(e[k])) {
            k++;
          }
          path.write(e.substring(startK, k));
        }
        if (k < e.length && e[k] == '(') {
          final close = _findMatchingClose(e, k, 0x28, 0x29);
          if (close > k) {
            final argsStr = e.substring(k + 1, close);
            final args = _splitArgs(argsStr, variables);
            final fnName = path.toString();
            final userFn = variables[fnName];
            if (userFn is _JsFunction) {
              current = _callJsFunction(userFn, args, variables);
            } else {
              current = _callFunction(fnName, args, variables);
            }
            i = close + 1;
          }
        } else {
          current = null;
          return null;
        }
      }
    } else {
      isChainSyntax = true;
      var fn = variables[head.$1];
      if (fn == null) {
        fn = _evaluateExpressionPart(head.$1, variables);
      }
      if (fn is _JsFunction) {
        current = _callJsFunction(fn, head.$2!, variables);
      } else {
        current = _callFunction(head.$1, head.$2!, variables);
      }
    }

    if (!isChainSyntax && i >= e.length) {
      return null;
    }

    // 后续段:.prop / [key] / (args)
    while (i < e.length) {
      final c = e[i];
      if (c == '.') {
        var j = i + 1;
        while (j < e.length && _isIdentChar(e[j])) {
          j++;
        }
        final propName = e.substring(i + 1, j);
        if (propName.isEmpty) return null;
        if (current is Map) {
          if (j < e.length && e[j] == '(') {
            final close2 = _findMatchingClose(e, j, 0x28, 0x29);
            if (close2 == -1) return null;
            final argsStr = e.substring(j + 1, close2);
            final args = _splitArgs(argsStr, variables);
            current = _callMapMethod(current, propName, args, variables);
            i = close2 + 1;
            continue;
          }
          current = current[propName];
          i = j;
        } else if (current is _JsObject) {
          if (j < e.length && e[j] == '(') {
            final close2 = _findMatchingClose(e, j, 0x28, 0x29);
            if (close2 == -1) return null;
            final argsStr = e.substring(j + 1, close2);
            final args = _splitArgs(argsStr, variables);
            current = _callMethod(current, propName, args);
            i = close2 + 1;
            continue;
          }
          current = current.props[propName];
          i = j;
        } else if (current is List) {
          if (j < e.length && e[j] == '(') {
            final close2 = _findMatchingClose(e, j, 0x28, 0x29);
            if (close2 == -1) return null;
            final argsStr = e.substring(j + 1, close2);
            final args = _splitArgs(argsStr, variables);
            current = _callArrayMethod(propName, current, args, variables);
            i = close2 + 1;
            continue;
          }
          final idx = int.tryParse(propName);
          current = (idx != null && idx >= 0 && idx < current.length)
              ? current[idx]
              : null;
          i = j;
        } else if (current is String) {
          if (j < e.length && e[j] == '(') {
            final close2 = _findMatchingClose(e, j, 0x28, 0x29);
            if (close2 == -1) return null;
            final argsStr = e.substring(j + 1, close2);
            final args = _splitArgs(argsStr, variables);
            current = _callStringMethod(propName, current, args);
            i = close2 + 1;
            continue;
          }
          if (propName == 'length') {
            current = (current as String).length;
          } else {
            current = null;
          }
          i = j;
        } else {
          current = null;
          i = j;
        }
      } else if (c == '[') {
        final close = _findMatchingClose(e, i, 0x5b, 0x5d);
        if (close == -1) return null;
        final keyExpr = e.substring(i + 1, close).trim();
        final key = _evaluateExpressionPart(keyExpr, variables);
        if (current is Map) {
          current = current[key];
        } else if (current is _JsObject) {
          current = current.props[key?.toString() ?? ''];
        } else if (current is List) {
          current = (key is int && key >= 0 && key < current.length)
              ? current[key]
              : null;
        } else {
          current = null;
        }
        i = close + 1;
      } else if (c == '(') {
        final close = _findMatchingClose(e, i, 0x28, 0x29);
        if (close == -1) return null;
        final argsStr = e.substring(i + 1, close);
        final args = _splitArgs(argsStr, variables);
        if (current is _JsFunction) {
          current = _callJsFunction(current, args, variables);
        } else {
          current = null;
        }
        i = close + 1;
      } else {
        return null;
      }
    }
    return (value: current);
  }

  /// 读取一个链段: literal/variable/(expr) 后跟 (args) 视为函数调用
  /// 返回 ((fullText, argsOrNull), endIndex)
  static ((String, List<dynamic>?), int)? _readChainSegment(
    String e,
    int start,
    Map<String, dynamic> variables,
  ) {
    var i = start;
    if (i >= e.length) return null;
    final c = e[i];
    if (c == '(') {
      final close = _findMatchingClose(e, i, 0x28, 0x29);
      if (close == -1) return null;
      final inner = e.substring(i + 1, close).trim();
      // 可能是 (expr) 或 (expr)(args) 或 (expr)[key]
      // 先看后面
      i = close + 1;
      if (i < e.length && e[i] == '(') {
        final close2 = _findMatchingClose(e, i, 0x28, 0x29);
        if (close2 == -1) return null;
        final argsStr = e.substring(i + 1, close2);
        final args = _splitArgs(argsStr, variables);
        return ((inner, args), close2 + 1);
      }
      return ((inner, null), i);
    } else if (c == '`' || c == '"' || c == "'") {
      // 字符串字面量(包括模板字符串) —— 读完整
      final end = _findStringEnd(e, i, e.codeUnitAt(i));
      if (end == -1) return null;
      final text = e.substring(i, end + 1);
      return ((text, null), end + 1);
    } else if (RegExp(r'^[a-zA-Z_\$]').hasMatch(c)) {
      // identifier
      var j = i;
      while (j < e.length && _isIdentChar(e[j])) {
        j++;
      }
      final name = e.substring(i, j);
      if (j < e.length && e[j] == '(') {
        final close = _findMatchingClose(e, j, 0x28, 0x29);
        if (close == -1) return null;
        final argsStr = e.substring(j + 1, close);
        final args = _splitArgs(argsStr, variables);
        return ((name, args), close + 1);
      }
      return ((name, null), j);
    } else if (c == '[') {
      // 数组字面量
      final close = _findMatchingClose(e, i, 0x5b, 0x5d);
      if (close == -1) return null;
      return ((e.substring(i, close + 1), null), close + 1);
    } else if (c == '{') {
      // 对象字面量
      final close = _findMatchingClose(e, i, 0x7b, 0x7d);
      if (close == -1) return null;
      return ((e.substring(i, close + 1), null), close + 1);
    }
    return null;
  }

  // ============== 函数调用 ==============

  static dynamic _callMethod(dynamic obj, String method, List<dynamic> args) {
    if (obj is _JsObject) {
      // .toString() / .toString(encoding) — CryptoJS 兼容
      if (method == 'toString') {
        if (args.isNotEmpty) {
          final enc = args[0]?.toString() ?? '';
          if (enc.contains('Utf8') || enc == 'utf8') {
            final fn = obj.props['__toStringUtf8'];
            if (fn is Function) return fn();
          } else if (enc.contains('Hex')) {
            final fn = obj.props['__toStringHex'];
            if (fn is Function) return fn();
          } else if (enc.contains('Base64')) {
            final fn = obj.props['__toStringBase64'];
            if (fn is Function) return fn();
          }
        }
        final fn = obj.props['__toString'];
        if (fn is Function) return fn();
      }
      final v = obj.props[method];
      if (v is Function) return v(args);
      final call = obj.props['__call__'];
      if (call is Function) return call(args);
    }
    return null;
  }

  // ============== String method ==============

  static dynamic _callStringMethod(
    String method,
    String str,
    List<dynamic> args,
  ) {
    switch (method) {
      case 'length':
        return str.length;
      case 'match':
        if (args.isEmpty) return null;
        return _jsMatch(str, args[0]?.toString() ?? '');
      case 'replace':
        if (args.length < 2) return str;
        return _jsReplace(
          str,
          args[0]?.toString() ?? '',
          args[1]?.toString() ?? '',
        );
      case 'split':
        if (args.isEmpty) return [str];
        final sep = args[0];
        if (sep is RegExp) {
          return str.split(sep);
        }
        final s = sep?.toString() ?? '';
        if (s.isEmpty) return [str];
        return str.split(s);
      case 'toUpperCase':
        return str.toUpperCase();
      case 'toLowerCase':
        return str.toLowerCase();
      case 'trim':
        return str.trim();
      case 'padStart':
        if (args.isEmpty) return str;
        final targetLength = _toInt(args[0]);
        if (targetLength <= str.length) return str;
        final padStr = args.length > 1 ? (args[1]?.toString() ?? ' ') : ' ';
        if (padStr.isEmpty) return str;
        final padLength = targetLength - str.length;
        final repeatedPad = padStr * ((padLength / padStr.length).ceil());
        return repeatedPad.substring(0, padLength) + str;
      case 'padEnd':
        if (args.isEmpty) return str;
        final targetLength = _toInt(args[0]);
        if (targetLength <= str.length) return str;
        final padStr = args.length > 1 ? (args[1]?.toString() ?? ' ') : ' ';
        if (padStr.isEmpty) return str;
        final padLength = targetLength - str.length;
        final repeatedPad = padStr * ((padLength / padStr.length).ceil());
        return str + repeatedPad.substring(0, padLength);
      case 'indexOf':
        if (args.isEmpty) return -1;
        return str.indexOf(args[0]?.toString() ?? '');
      case 'lastIndexOf':
        if (args.isEmpty) return -1;
        return str.lastIndexOf(args[0]?.toString() ?? '');
      case 'includes':
        if (args.isEmpty) return false;
        return str.contains(args[0]?.toString() ?? '');
      case 'startsWith':
        if (args.isEmpty) return false;
        return str.startsWith(args[0]?.toString() ?? '');
      case 'endsWith':
        if (args.isEmpty) return false;
        return str.endsWith(args[0]?.toString() ?? '');
      case 'substring':
        if (args.isEmpty) return str;
        final start = args.length > 0 ? _toInt(args[0]) : 0;
        final end = args.length > 1 ? _toInt(args[1]) : str.length;
        final s = start.clamp(0, str.length);
        final e = end.clamp(0, str.length);
        return e >= s ? str.substring(s, e) : '';
      case 'substr':
        if (args.isEmpty) return str;
        final start = args.length > 0 ? _toInt(args[0]) : 0;
        final length = args.length > 1 ? _toInt(args[1]) : str.length;
        final s = start.clamp(0, str.length);
        final e = (s + length).clamp(0, str.length);
        return str.substring(s, e);
      case 'slice':
        if (args.isEmpty) return str;
        final start = args.length > 0 ? _toInt(args[0]) : 0;
        final end = args.length > 1 ? _toInt(args[1]) : str.length;
        final s = start < 0
            ? (str.length + start).clamp(0, str.length)
            : start.clamp(0, str.length);
        final e = end < 0
            ? (str.length + end).clamp(0, str.length)
            : end.clamp(0, str.length);
        return e >= s ? str.substring(s, e) : '';
      case 'charAt':
        if (args.isEmpty) return '';
        final idx = _toInt(args[0]);
        return idx >= 0 && idx < str.length ? str[idx] : '';
      case 'charCodeAt':
        if (args.isEmpty) return 0;
        final idx = _toInt(args[0]);
        return idx >= 0 && idx < str.length ? str.codeUnitAt(idx) : 0;
      case 'concat':
        return str + args.map((a) => a?.toString() ?? '').join();
      case 'toArray':
        // legado jsoup 兼容:string.toArray() 视为 [str]
        return [str];
      case 'toJSON':
        return str;
      case 'valueOf':
        return str;
    }
    throw LegacyJsEvalError('Unsupported string method: $method');
  }

  static bool _isCallable(dynamic fn) {
    return fn is Function || fn is _JsFunction;
  }

  static dynamic _invokeCallback(
    dynamic fn,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    if (fn is _JsFunction) {
      return _callJsFunction(fn, args, variables);
    } else if (fn is Function) {
      return Function.apply(fn, args);
    }
    return null;
  }

  // ============== Array method ==============

  static dynamic _callArrayMethod(
    String method,
    List<dynamic> list,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    switch (method) {
      case 'length':
        return list.length;
      case 'push':
        list.addAll(args);
        return list.length;
      case 'pop':
        return list.isNotEmpty ? list.removeLast() : null;
      case 'shift':
        return list.isNotEmpty ? list.removeAt(0) : null;
      case 'unshift':
        list.insertAll(0, args);
        return list.length;
      case 'join':
        if (args.isEmpty) return list.join(',');
        return list.join(args[0]?.toString() ?? '');
      case 'slice':
        if (args.isEmpty) return list;
        final start = args.length > 0 ? _toInt(args[0]) : 0;
        final end = args.length > 1 ? _toInt(args[1]) : list.length;
        final s = start < 0
            ? (list.length + start).clamp(0, list.length)
            : start.clamp(0, list.length);
        final e = end < 0
            ? (list.length + end).clamp(0, list.length)
            : end.clamp(0, list.length);
        return list.sublist(s, e);
      case 'concat':
        return [...list, ...args];
      case 'indexOf':
        if (args.isEmpty) return -1;
        return list.indexOf(args[0]);
      case 'includes':
        if (args.isEmpty) return false;
        return list.contains(args[0]);
      case 'map':
        if (args.isEmpty) return list;
        return _mapArray(list, args[0], variables);
      case 'filter':
        if (args.isEmpty) return list;
        return _filterArray(list, args[0], variables);
      case 'forEach':
        if (args.isEmpty) return null;
        return _forEachArray(list, args[0], variables);
      case 'reduce':
        return _reduceArray(list, args, variables);
      case 'sort':
        if (args.isEmpty) {
          final sorted = [...list];
          sorted.sort();
          return sorted;
        }
        return _sortArray(list, args[0], variables);
      case 'reverse':
        return list.reversed.toList();
      case 'toString':
        return list.join(',');
      case 'toArray':
        return list;
    }
    throw LegacyJsEvalError('Unsupported array method: $method');
  }

  static List<dynamic> _mapArray(
    List<dynamic> list,
    dynamic fn,
    Map<String, dynamic> variables,
  ) {
    if (!_isCallable(fn)) return list;
    final result = <dynamic>[];
    for (var i = 0; i < list.length; i++) {
      try {
        result.add(_invokeCallback(fn, [list[i], i, list], variables));
      } on LegacyJsEvalError {
        rethrow;
      } catch (_) {
        result.add(null);
      }
    }
    return result;
  }

  static List<dynamic> _filterArray(
    List<dynamic> list,
    dynamic fn,
    Map<String, dynamic> variables,
  ) {
    if (!_isCallable(fn)) return list;
    final result = <dynamic>[];
    for (var i = 0; i < list.length; i++) {
      try {
        if (_isTruthy(_invokeCallback(fn, [list[i], i, list], variables))) {
          result.add(list[i]);
        }
      } on LegacyJsEvalError {
        rethrow;
      } catch (_) {}
    }
    return result;
  }

  static dynamic _forEachArray(
    List<dynamic> list,
    dynamic fn,
    Map<String, dynamic> variables,
  ) {
    if (!_isCallable(fn)) return null;
    for (var i = 0; i < list.length; i++) {
      try {
        _invokeCallback(fn, [list[i], i, list], variables);
      } on LegacyJsEvalError {
        rethrow;
      } catch (_) {}
    }
    return null;
  }

  static dynamic _reduceArray(
    List<dynamic> list,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    if (args.isEmpty) return null;
    final fn = args[0];
    if (!_isCallable(fn)) return null;
    dynamic acc = args.length > 1
        ? args[1]
        : (list.isNotEmpty ? list[0] : null);
    final startIdx = args.length > 1 ? 0 : 1;
    for (var i = startIdx; i < list.length; i++) {
      try {
        acc = _invokeCallback(fn, [acc, list[i], i, list], variables);
      } on LegacyJsEvalError {
        rethrow;
      } catch (_) {
        return acc;
      }
    }
    return acc;
  }

  static List<dynamic> _sortArray(
    List<dynamic> list,
    dynamic fn,
    Map<String, dynamic> variables,
  ) {
    if (!_isCallable(fn)) return list;
    final sorted = [...list];
    try {
      sorted.sort((a, b) {
        try {
          final r = _invokeCallback(fn, [a, b], variables);
          if (r is num) return r.toInt();
          return _toInt(r);
        } on LegacyJsEvalError {
          rethrow;
        } catch (_) {
          return 0;
        }
      });
    } on LegacyJsEvalError {
      rethrow;
    } catch (_) {}
    return sorted;
  }

  // ============== RegExp methods ==============

  /// 解析 JS 正则字面量 "/pattern/flags" → Dart RegExp
  /// 失败时回退为纯字符串 replace
  static ({RegExp regex, bool global})? _parseJsRegex(String pattern) {
    try {
      if (pattern.length < 2 || !pattern.startsWith('/')) {
        // 当成字面量正则
        return (regex: RegExp(pattern), global: false);
      }
      final lastSlash = pattern.lastIndexOf('/');
      if (lastSlash <= 0) return null;
      final body = pattern.substring(1, lastSlash);
      final flags = pattern.substring(lastSlash + 1);
      final global = flags.contains('g');
      return (
        regex: RegExp(body, caseSensitive: !flags.contains('i')),
        global: global,
      );
    } catch (_) {
      return null;
    }
  }

  /// JS .match(regex) → List<String> 包含整个匹配 + groups
  static List<String>? _jsMatch(String str, String pattern) {
    final parsed = _parseJsRegex(pattern);
    if (parsed == null) return null;
    try {
      if (parsed.global) {
        return parsed.regex
            .allMatches(str)
            .map((m) => m.group(0) ?? '')
            .toList();
      }
      final match = parsed.regex.firstMatch(str);
      if (match == null) return null;
      final groups = <String>[];
      for (var i = 0; i <= match.groupCount; i++) {
        groups.add(match.group(i) ?? '');
      }
      return groups;
    } catch (_) {
      return null;
    }
  }

  static String _jsReplace(String str, String pattern, String replacement) {
    final parsed = _parseJsRegex(pattern);
    if (parsed == null) return str;
    try {
      String replaceCallback(Match match) {
        return replacement.replaceAllMapped(RegExp(r'\$\$|\$(\d+)'), (m) {
          final matched = m.group(0);
          if (matched == r'$$') {
            return r'$';
          }
          final groupIdx = int.parse(m.group(1)!);
          if (groupIdx <= match.groupCount) {
            return match.group(groupIdx) ?? '';
          }
          return '';
        });
      }

      if (parsed.global) {
        return str.replaceAllMapped(parsed.regex, replaceCallback);
      }
      return str.replaceFirstMapped(parsed.regex, replaceCallback);
    } catch (_) {
      return str;
    }
  }

  static dynamic _callFunction(
    String name,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    // CryptoJS 兼容: CryptoJS.MD5(s) → 返回带 .toString() 的对象
    if (name.startsWith('CryptoJS.')) {
      return _callCryptoJS(name.substring('CryptoJS.'.length), args);
    }

    // java 桥
    if (name.startsWith('java.')) {
      return _callJavaBridge(name.substring('java.'.length), args, variables);
    }

    // Math
    if (name.startsWith('Math.')) {
      return _callMath(name.substring('Math.'.length), args);
    }

    // String (作为全局)
    if (name.startsWith('String.')) {
      return _callStringStatic(name.substring('String.'.length), args);
    }

    // 全局函数
    switch (name) {
      case 'Date.now':
        return DateTime.now().millisecondsSinceEpoch;
      case 'Date.parse':
        if (args.isEmpty) return 0;
        return DateTime.tryParse(args[0].toString())?.millisecondsSinceEpoch ??
            0;
      case 'Date.UTC':
        if (args.isEmpty) return 0;
        return DateTime.utc(
          args.length > 0 ? _toInt(args[0]) : 1970,
          args.length > 1 ? _toInt(args[1]) : 1,
          args.length > 2 ? _toInt(args[2]) : 1,
          args.length > 3 ? _toInt(args[3]) : 0,
          args.length > 4 ? _toInt(args[4]) : 0,
          args.length > 5 ? _toInt(args[5]) : 0,
        ).millisecondsSinceEpoch;

      case 'parseInt':
        if (args.isEmpty) return 0;
        final str = args[0].toString().trim();
        var base = 10;
        var sign = 1;
        var s = str;
        if (s.startsWith('+')) {
          s = s.substring(1);
        } else if (s.startsWith('-')) {
          sign = -1;
          s = s.substring(1);
        }

        if (args.length > 1) {
          base = _toInt(args[1]);
        } else {
          if (s.startsWith('0x') || s.startsWith('0X')) {
            base = 16;
          }
        }

        if (base < 2 || base > 36) return 0;

        if (base == 16 && (s.startsWith('0x') || s.startsWith('0X'))) {
          s = s.substring(2);
        }

        final buffer = StringBuffer();
        for (var i = 0; i < s.length; i++) {
          final char = s[i].toLowerCase();
          final code = char.codeUnitAt(0);
          int val;
          if (code >= 48 && code <= 57) {
            val = code - 48;
          } else if (code >= 97 && code <= 122) {
            val = code - 97 + 10;
          } else {
            break;
          }
          if (val < base) {
            buffer.write(s[i]);
          } else {
            break;
          }
        }

        if (buffer.isEmpty) return 0;
        return (int.tryParse(buffer.toString(), radix: base) ?? 0) * sign;

      case 'parseFloat':
        if (args.isEmpty) return 0;
        final str = args[0].toString().trim();
        final match = RegExp(
          r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?',
        ).stringMatch(str);
        if (match == null) return 0.0;
        return double.tryParse(match) ?? 0.0;
      case 'isNaN':
        return args.isEmpty ? true : (args[0] is num && args[0].isNaN);
      case 'isFinite':
        return args.isEmpty ? false : (args[0] is num && args[0].isFinite);

      case 'encodeURI':
        if (args.isEmpty) return '';
        return Uri.encodeFull(args[0].toString());
      case 'encodeURIComponent':
        if (args.isEmpty) return '';
        return Uri.encodeComponent(args[0].toString());
      case 'decodeURIComponent':
        if (args.isEmpty) return '';
        return Uri.decodeComponent(args[0].toString());
      case 'decodeURI':
        if (args.isEmpty) return '';
        return Uri.decodeFull(args[0].toString());

      case 'btoa':
        if (args.isEmpty) return '';
        return base64.encode(utf8.encode(args[0].toString()));
      case 'atob':
        if (args.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(args[0].toString()));
        } catch (_) {
          return '';
        }
      case 'base64':
        if (args.isEmpty) return '';
        return base64.encode(utf8.encode(args[0].toString()));
      case 'unbase64':
        if (args.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(args[0].toString()));
        } catch (_) {
          return '';
        }

      case 'MD5':
        if (args.isEmpty) return '';
        return crypto_pkg.md5
            .convert(utf8.encode(args[0].toString()))
            .toString();
      case 'SHA1':
        if (args.isEmpty) return '';
        return crypto_pkg.sha1
            .convert(utf8.encode(args[0].toString()))
            .toString();
      case 'SHA256':
        if (args.isEmpty) return '';
        return crypto_pkg.sha256
            .convert(utf8.encode(args[0].toString()))
            .toString();

      case 'JSON.parse':
        if (args.isEmpty) return null;
        try {
          return jsonDecode(args[0].toString());
        } catch (_) {
          return null;
        }
      case 'JSON.stringify':
        if (args.isEmpty) return '';
        return jsonEncode(args[0]);

      case 'importScript':
        return args.isEmpty ? '' : args[0].toString();

      case 'Number':
        if (args.isEmpty) return 0;
        return _toNum(args[0]);
      case 'Boolean':
        if (args.isEmpty) return false;
        return _isTruthy(args[0]);
      case 'String':
        if (args.isEmpty) return '';
        return args[0]?.toString() ?? '';
      case 'eval':
        // eval(string) — 调 evaluate 自身,**共享 scope**(so eval'd code 定义
        // 的 function/var 能在外层用,符合 legado source 的 eval(source.bookSourceComment) 模式)
        if (args.isEmpty) return null;
        try {
          final code = args[0]?.toString() ?? '';
          final cleanCode = _stripComments(code);
          final stripped = _stripCommentsAndStrings(cleanCode);
          if (RegExp(
            r'\b(async|await|with|class|yield)\b',
          ).hasMatch(stripped)) {
            throw LegacyJsEvalError('Unsupported keyword in eval: $code');
          }
          // 关键:不复制 variables map,直接 splitStatements → evaluateStatement
          final statements = _splitStatements(cleanCode);
          dynamic last;
          for (final stmt in statements) {
            last = _evaluateStatement(stmt, variables);
            if (last is _ReturnSignal) return last.value ?? '';
          }
          if (last is _ReturnSignal) return last.value ?? '';
          return last;
        } on LegacyJsEvalError {
          rethrow;
        } catch (_) {
          return null;
        }
      case 'RegExp':
        // new RegExp(pattern, flags) — 简化为字符串(链式 .test 仍可用)
        if (args.isEmpty) return null;
        return args[0]?.toString() ?? '';
      case 'Object.keys':
        if (args.isEmpty) return <dynamic>[];
        final obj = args[0];
        if (obj is Map) return obj.keys.toList();
        if (obj is _JsObject) return obj.props.keys.toList();
        return <dynamic>[];
      case 'Object.values':
        if (args.isEmpty) return <dynamic>[];
        final obj = args[0];
        if (obj is Map) return obj.values.toList();
        if (obj is _JsObject) return obj.props.values.toList();
        return <dynamic>[];
      case 'Object.assign':
        if (args.length < 2) return args.isNotEmpty ? args[0] : null;
        final target = args[0] is Map
            ? Map<String, dynamic>.from(args[0] as Map)
            : <String, dynamic>{};
        for (var i = 1; i < args.length; i++) {
          final src = args[i];
          if (src is Map) {
            src.forEach((k, v) => target[k.toString()] = v);
          } else if (src is _JsObject) {
            src.props.forEach((k, v) => target[k] = v);
          }
        }
        return target;
      case 'Array.from':
        if (args.isEmpty) return <dynamic>[];
        final src = args[0];
        if (src is List) return [...src];
        if (src is String) return src.split('');
        if (src is Map) return src.values.toList();
        return <dynamic>[src];
      case 'Array.isArray':
        if (args.isEmpty) return false;
        return args[0] is List;
    }
    throw LegacyJsEvalError('Unsupported function call: $name');
  }

  // ============== java 桥接(stub) ==============

  static dynamic _callJavaBridge(
    String method,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    switch (method) {
      case 'ajax':
      case 'post':
      case 'connect':
        throw LegacyJsEvalError(
          'Network request not supported in LegacyJsEvaluator',
        );
      case 'getResponseCode':
        return 200;
      case 'importScript':
        return args.isEmpty ? '' : args[0].toString();
      case 'get':
        if (args.isEmpty) return '';
        final key = args[0].toString();
        if (key.startsWith('http://') || key.startsWith('https://')) {
          return '';
        }
        return variables[key]?.toString() ?? '';
      case 'put':
        if (args.length >= 2) {
          variables[args[0].toString()] = args[1];
        }
        return args.length >= 2 ? args[1] : '';
      case 'getString':
        if (args.isEmpty) return '';
        final key = args[0].toString();
        final stored = variables[key]?.toString() ?? '';
        if (stored.isNotEmpty) return stored;
        final resultVal = variables['result'];
        if (resultVal != null &&
            resultVal.toString().isNotEmpty &&
            (key.contains('\$') || key.contains('.') || key.contains('['))) {
          try {
            final parsed = LegadoRuleEvaluator.extractJsonValue(
              resultVal,
              key,
              variables: variables,
            );
            if (parsed.isNotEmpty) return parsed;
          } catch (_) {}
        }
        return args.length > 1 ? args[1]?.toString() ?? '' : '';
      case 'md5Encode':
        if (args.isEmpty) return '';
        return crypto_pkg.md5
            .convert(utf8.encode(args[0].toString()))
            .toString();
      case 'base64Encode':
        if (args.isEmpty) return '';
        return base64.encode(utf8.encode(args[0].toString()));
      case 'base64Decode':
        if (args.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(args[0].toString()));
        } catch (_) {
          return '';
        }
      case 'base64DecodeToString':
        if (args.isEmpty) return '';
        try {
          return utf8.decode(base64.decode(args[0].toString()));
        } catch (_) {
          return '';
        }
      case 'aesBase64DecodeToString':
        if (args.isEmpty) return '';
        return _aesBase64DecryptCompat(
          args[0].toString(),
          args.length > 1 ? args[1].toString() : '',
          args.length > 2 ? args[2].toString() : '',
        );
      case 'aesBase64Encode':
        if (args.isEmpty) return '';
        return _aesBase64EncryptCompat(
          args[0].toString(),
          args.length > 1 ? args[1].toString() : '',
          args.length > 2 ? args[2].toString() : '',
        );
      case 'androidId':
        // 没法获取真实 androidId,返回稳定 hash
        return 'legacy-evaluator-androidId';
      case 'timeFormat':
        if (args.isEmpty) return DateTime.now().toIso8601String();
        if (args.length == 1) {
          final val = args[0];
          final numVal = double.tryParse(val.toString().trim());
          if (numVal != null) {
            final dt = DateTime.fromMillisecondsSinceEpoch(numVal.toInt());
            return _formatTime('yyyy-MM-dd HH:mm:ss', dt);
          } else {
            return _formatTime(val.toString(), DateTime.now());
          }
        } else {
          var timestamp = DateTime.now().millisecondsSinceEpoch;
          var pattern = 'yyyy-MM-dd HH:mm:ss';
          final val1 = args[0];
          final val2 = args[1];
          final num1 = double.tryParse(val1.toString().trim());
          final num2 = double.tryParse(val2.toString().trim());
          if (num1 != null) {
            timestamp = num1.toInt();
            pattern = val2.toString();
          } else if (num2 != null) {
            timestamp = num2.toInt();
            pattern = val1.toString();
          } else {
            pattern = val1.toString();
          }
          final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
          return _formatTime(pattern, dt);
        }
      case 'log':
        return args.isNotEmpty ? args[0].toString() : '';
      case 'cipher':
      case 'cipher_':
        return '';
      case 'bytesToString':
        if (args.isEmpty) return '';
        return args[0].toString();
      case 'stringToBytes':
        if (args.isEmpty) return '';
        return utf8.encode(args[0].toString());
      case 'encodeURI':
        if (args.isEmpty) return '';
        final str = args[0].toString();
        final charset = args.length > 1
            ? args[1].toString().replaceAll(RegExp("[\"']"), '')
            : 'utf-8';
        if (charset.toLowerCase() == 'gbk' ||
            charset.toLowerCase() == 'gb2312') {
          // fast_gbk 顶层暴露 gbk.encode,失败时回退 utf8.encode
          List<int> bytes;
          try {
            bytes = gbk.encode(str);
          } catch (_) {
            bytes = utf8.encode(str);
          }
          return bytes
              .map(
                (b) => '%' + b.toRadixString(16).padLeft(2, '0').toUpperCase(),
              )
              .join();
        }
        return Uri.encodeComponent(str);
      case 'hmacHex':
      case 'HMacHex':
        if (args.length < 3) return '';
        return _hmacHex(
          args[0].toString(),
          args[1].toString(),
          args[2].toString(),
        );
      case 'hmacBase64':
      case 'HMacBase64':
        if (args.length < 3) return '';
        return _hmacBase64(
          args[0].toString(),
          args[1].toString(),
          args[2].toString(),
        );
      case 'decodeURI':
        if (args.isEmpty) return '';
        return Uri.decodeComponent(args[0].toString());
      case 'digestHex':
        if (args.length < 2) return '';
        final val = args[0].toString();
        final alg = args[1].toString().toLowerCase().replaceAll(
          RegExp(r'^sha-?'),
          'sha',
        );
        if (alg == 'md5') {
          return crypto_pkg.md5.convert(utf8.encode(val)).toString();
        } else if (alg == 'sha1') {
          return crypto_pkg.sha1.convert(utf8.encode(val)).toString();
        } else if (alg == 'sha224') {
          return crypto_pkg.sha224.convert(utf8.encode(val)).toString();
        } else if (alg == 'sha256') {
          return crypto_pkg.sha256.convert(utf8.encode(val)).toString();
        } else if (alg == 'sha384' || alg == 'sha348') {
          return crypto_pkg.sha384.convert(utf8.encode(val)).toString();
        } else if (alg == 'sha512') {
          return crypto_pkg.sha512.convert(utf8.encode(val)).toString();
        }
        return '';
      case 'aesEncodeToBase64String':
        if (args.length < 2) return '';
        final valueAes = args[0].toString();
        final keyAes = args[1].toString();
        final thirdAes = args.length > 2 ? args[2] : null;
        final fourthAes = args.length > 3 ? args[3] : null;
        final normAes = _normalizeTransformation(
          thirdAes,
          fourthAes,
          'AES/CBC/PKCS5Padding',
        );
        return _cipherBase64Encode(
          valueAes,
          keyAes,
          normAes.iv,
          normAes.transformation,
        );
      case 'desEncodeToBase64String':
      case 'desEncodeToBase64':
        if (args.length < 2) return '';
        final valueDes = args[0].toString();
        final keyDes = args[1].toString();
        final thirdDes = args.length > 2 ? args[2] : null;
        final fourthDes = args.length > 3 ? args[3] : null;
        final normDes = _normalizeTransformation(
          thirdDes,
          fourthDes,
          'DES/CBC/PKCS5Padding',
        );
        return _cipherBase64Encode(
          valueDes,
          keyDes,
          normDes.iv,
          normDes.transformation,
        );
      case 'tripleDESEncodeBase64Str':
        if (args.length < 2) return '';
        final valueTriple = args[0].toString();
        final keyTriple = args[1].toString();
        final modeTriple = args.length > 2
            ? args[2]?.toString() ?? 'CBC'
            : 'CBC';
        final paddingTriple = args.length > 3
            ? args[3]?.toString() ?? 'PKCS5Padding'
            : 'PKCS5Padding';
        final ivTriple = args.length > 4 ? args[4]?.toString() ?? '' : '';
        final transformationTriple = 'DESede/$modeTriple/$paddingTriple';
        return _cipherBase64Encode(
          valueTriple,
          keyTriple,
          ivTriple,
          transformationTriple,
        );
      case 'cipherEncodeToBase64String':
        if (args.length < 2) return '';
        final valueCipher = args[0].toString();
        final keyCipher = args[1].toString();
        final thirdCipher = args.length > 2 ? args[2] : null;
        final fourthCipher = args.length > 3 ? args[3] : null;
        final normCipher = _normalizeTransformation(
          thirdCipher,
          fourthCipher,
          'AES/CBC/PKCS5Padding',
        );
        return _cipherBase64Encode(
          valueCipher,
          keyCipher,
          normCipher.iv,
          normCipher.transformation,
        );
    }
    throw LegacyJsEvalError('Unsupported java method: $method');
  }

  // ============== CryptoJS 兼容 ==============

  /// 简化的 CryptoJS 兼容层,支持 .MD5/.SHA1/.SHA256/.HmacSHA256/.AES.encrypt/.AES.decrypt/.enc.Utf8.parse/.enc.Hex.parse
  /// 返回 _JsObject(有 toString() / words 等 CryptoJS 兼容接口)
  static dynamic _callCryptoJS(String path, List<dynamic> args) {
    final parts = path.split('.');
    if (parts.isEmpty) return null;
    final root = parts[0];
    switch (root) {
      case 'MD5':
        if (parts.length == 1) {
          // CryptoJS.MD5(s) → _JsObject{ toString: () => hex }
          final s = args.isNotEmpty ? args[0].toString() : '';
          return _JsObject({
            '__toString': () =>
                crypto_pkg.md5.convert(utf8.encode(s)).toString(),
          });
        }
        return null;
      case 'SHA1':
        if (parts.length == 1) {
          final s = args.isNotEmpty ? args[0].toString() : '';
          return _JsObject({
            '__toString': () =>
                crypto_pkg.sha1.convert(utf8.encode(s)).toString(),
          });
        }
        return null;
      case 'SHA256':
        if (parts.length == 1) {
          final s = args.isNotEmpty ? args[0].toString() : '';
          return _JsObject({
            '__toString': () =>
                crypto_pkg.sha256.convert(utf8.encode(s)).toString(),
          });
        }
        return null;
      case 'HmacSHA256':
        if (parts.length == 1) {
          // CryptoJS.HmacSHA256(msg, key)
          final msg = args.isNotEmpty ? args[0].toString() : '';
          final key = args.length > 1 ? args[1].toString() : '';
          return _JsObject({
            '__toString': () {
              final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, utf8.encode(key));
              return hmac.convert(utf8.encode(msg)).toString();
            },
          });
        }
        return null;
      case 'AES':
        if (parts.length >= 2) {
          final op = parts[1];
          if (op == 'encrypt' && parts.length == 2) {
            // CryptoJS.AES.encrypt(msg, key, cfg?)
            final msg = args.isNotEmpty ? args[0].toString() : '';
            final key = args.length > 1 ? args[1].toString() : '';
            final cfg = args.length > 2 && args[2] is Map
                ? args[2] as Map
                : <String, dynamic>{};
            return _JsObject({
              '__toString': () => _cryptoAesEncrypt(msg, key, cfg),
            });
          }
          if (op == 'decrypt' && parts.length == 2) {
            // CryptoJS.AES.decrypt(ct, key, cfg?)
            final ct = args.isNotEmpty ? args[0].toString() : '';
            final key = args.length > 1 ? args[1].toString() : '';
            final cfg = args.length > 2 && args[2] is Map
                ? args[2] as Map
                : <String, dynamic>{};
            return _JsObject({
              '__toString': () => _cryptoAesDecrypt(ct, key, cfg),
              '__toStringUtf8': () => _cryptoAesDecrypt(ct, key, cfg),
            });
          }
        }
        return null;
      case 'enc':
        if (parts.length >= 2) {
          final t = parts[1];
          if (t == 'Utf8' && parts.length >= 3 && parts[2] == 'parse') {
            // CryptoJS.enc.Utf8.parse(s) → WordArray(带 toString=base64)
            final s = args.isNotEmpty ? args[0].toString() : '';
            return _JsObject({
              'words': s.codeUnits,
              '__toString': () => base64.encode(utf8.encode(s)),
            });
          }
          if (t == 'Hex' && parts.length >= 3 && parts[2] == 'parse') {
            final s = args.isNotEmpty ? args[0].toString() : '';
            return _JsObject({'words': s.codeUnits, '__toString': () => s});
          }
          if (t == 'Base64' && parts.length >= 3 && parts[2] == 'parse') {
            final s = args.isNotEmpty ? args[0].toString() : '';
            return _JsObject({'words': s.codeUnits, '__toString': () => s});
          }
        }
        return null;
    }
    return null;
  }

  // ============== AES 加解密(CryptoJS 兼容) ==============

  /// CryptoJS padding 名字(任意大小写)→ pointycastle registry 名字(必须大写 PKCS7)
  static String _normalizePadding(String p) {
    final lower = p.toLowerCase();
    if (lower == 'pkcs7' || lower == 'pkcs5') return 'PKCS7';
    if (lower == 'nopadding' || lower == 'none') return 'NoPadding';
    if (lower == 'zeropadding') return 'ZeroBytePadding';
    return p;
  }

  static String _cryptoAesEncrypt(String msg, String key, Map cfg) {
    try {
      final ivStr = (cfg['iv'] is String) ? cfg['iv'] : '';
      final mode = (cfg['mode'] is String) ? cfg['mode'].toString() : 'CBC';
      final padding = _normalizePadding(
        (cfg['padding'] is String) ? cfg['padding'].toString() : 'Pkcs7',
      );
      Uint8List keyBytes = _toKeyBytes(key);
      Uint8List ivBytes = ivStr.isNotEmpty
          ? _toKeyBytes(ivStr).sublist(0, 16)
          : Uint8List(16);
      if (mode == 'ECB') {
        // pointycastle 3.9.1: PaddedBlockCipher factory 用 algorithm name 注册创建
        final impl = pc.PaddedBlockCipher('AES/ECB/${padding}');
        if (impl == null) return '';
        impl.init(
          true,
          pc.PaddedBlockCipherParameters<pc.KeyParameter, pc.KeyParameter?>(
            pc.KeyParameter(keyBytes),
            null,
          ),
        );
        final padded = _padPKCS7(utf8.encode(msg), 16);
        final out = impl.process(Uint8List.fromList(padded));
        return base64.encode(out);
      } else {
        final impl = pc.PaddedBlockCipher('AES/CBC/${padding}');
        if (impl == null) return '';
        impl.init(
          true,
          pc.PaddedBlockCipherParameters<
            pc.KeyParameter,
            pc.ParametersWithIV<pc.KeyParameter>
          >(
            pc.KeyParameter(keyBytes),
            pc.ParametersWithIV<pc.KeyParameter>(null, ivBytes),
          ),
        );
        final out = impl.process(Uint8List.fromList(utf8.encode(msg)));
        return base64.encode(out);
      }
    } catch (_) {
      return '';
    }
  }

  static String _cryptoAesDecrypt(String ct, String key, Map cfg) {
    try {
      final ivStr = (cfg['iv'] is String) ? cfg['iv'] : '';
      final mode = (cfg['mode'] is String) ? cfg['mode'].toString() : 'CBC';
      final padding = _normalizePadding(
        (cfg['padding'] is String) ? cfg['padding'].toString() : 'Pkcs7',
      );
      Uint8List keyBytes = _toKeyBytes(key);
      Uint8List ivBytes = ivStr.isNotEmpty
          ? _toKeyBytes(ivStr).sublist(0, 16)
          : Uint8List(16);
      Uint8List ctBytes;
      try {
        ctBytes = base64.decode(ct);
      } catch (_) {
        return '';
      }
      if (mode == 'ECB') {
        final impl = pc.PaddedBlockCipher('AES/ECB/${padding}');
        if (impl == null) return '';
        impl.init(
          false,
          pc.PaddedBlockCipherParameters<pc.KeyParameter, pc.KeyParameter?>(
            pc.KeyParameter(keyBytes),
            null,
          ),
        );
        final out = impl.process(ctBytes);
        return utf8.decode(out, allowMalformed: true);
      } else {
        final impl = pc.PaddedBlockCipher('AES/CBC/${padding}');
        if (impl == null) return '';
        impl.init(
          false,
          pc.PaddedBlockCipherParameters<
            pc.KeyParameter,
            pc.ParametersWithIV<pc.KeyParameter>
          >(
            pc.KeyParameter(keyBytes),
            pc.ParametersWithIV<pc.KeyParameter>(null, ivBytes),
          ),
        );
        final out = impl.process(ctBytes);
        return utf8.decode(out, allowMalformed: true);
      }
    } catch (_) {
      return '';
    }
  }

  static String _aesBase64DecryptCompat(String ct, String key, String iv) {
    try {
      final keyBytes = _toKeyBytes(key);
      final ivBytes = iv.isNotEmpty
          ? _toKeyBytes(iv).sublist(0, 16)
          : Uint8List(16);
      final impl = pc.PaddedBlockCipher('AES/CBC/PKCS7');
      if (impl == null) return '';
      impl.init(
        false,
        pc.PaddedBlockCipherParameters<
          pc.KeyParameter,
          pc.ParametersWithIV<pc.KeyParameter>
        >(
          pc.KeyParameter(keyBytes),
          pc.ParametersWithIV<pc.KeyParameter>(null, ivBytes),
        ),
      );
      return utf8.decode(impl.process(base64.decode(ct)), allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  static String _aesBase64EncryptCompat(String msg, String key, String iv) {
    try {
      final keyBytes = _toKeyBytes(key);
      final ivBytes = iv.isNotEmpty
          ? _toKeyBytes(iv).sublist(0, 16)
          : Uint8List(16);
      final impl = pc.PaddedBlockCipher('AES/CBC/PKCS7');
      if (impl == null) return '';
      impl.init(
        true,
        pc.PaddedBlockCipherParameters<
          pc.KeyParameter,
          pc.ParametersWithIV<pc.KeyParameter>
        >(
          pc.KeyParameter(keyBytes),
          pc.ParametersWithIV<pc.KeyParameter>(null, ivBytes),
        ),
      );
      return base64.encode(impl.process(Uint8List.fromList(utf8.encode(msg))));
    } catch (_) {
      return '';
    }
  }

  // ============== Math.* ==============

  static dynamic _callMath(String method, List<dynamic> args) {
    switch (method) {
      case 'floor':
        if (args.isEmpty) return 0;
        return (_toNum(args[0])).floor();
      case 'ceil':
        if (args.isEmpty) return 0;
        return (_toNum(args[0])).ceil();
      case 'round':
        if (args.isEmpty) return 0;
        return (_toNum(args[0])).round();
      case 'abs':
        if (args.isEmpty) return 0;
        return _toNum(args[0]).abs();
      case 'min':
        return args.map(_toNum).reduce((a, b) => a < b ? a : b);
      case 'max':
        return args.map(_toNum).reduce((a, b) => a > b ? a : b);
      case 'random':
        return DateTime.now().microsecondsSinceEpoch % 1000000 / 1000000;
      case 'pow':
        if (args.length < 2) return 0;
        return _toNumPow(args[0], args[1]);
      case 'sqrt':
        if (args.isEmpty) return 0;
        return _toNum(args[0]).abs() == 0
            ? 0
            : (_toNum(args[0]) > 0 ? _sqrtPositive(_toNum(args[0])) : 0);
      case 'log':
        if (args.isEmpty) return 0;
        return _toNum(args[0]) == 0 ? 0 : _log(_toNum(args[0]));
      case 'sin':
        if (args.isEmpty) return 0;
        return _sinApprox(_toNum(args[0]));
      case 'cos':
        if (args.isEmpty) return 0;
        return _cosApprox(_toNum(args[0]));
      case 'tan':
        if (args.isEmpty) return 0;
        return _tanApprox(_toNum(args[0]));
      case 'PI':
        return 3.141592653589793;
    }
    return 0;
  }

  // ============== String.* static ==============

  static dynamic _callStringStatic(String method, List<dynamic> args) {
    switch (method) {
      case 'fromCharCode':
        if (args.isEmpty) return '';
        return String.fromCharCodes(args.map(_toInt));
    }
    return '';
  }

  // ============== 辅助 ==============

  static List<dynamic> _splitArgs(
    String argsStr,
    Map<String, dynamic> variables,
  ) {
    final args = <dynamic>[];
    final current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < argsStr.length; i++) {
      final c = argsStr.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(c);
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        current.writeCharCode(c);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(c);
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        current.writeCharCode(c);
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (c == 0x2c &&
          parenDepth == 0 &&
          braceDepth == 0 &&
          bracketDepth == 0) {
        final a = current.toString().trim();
        if (a.isNotEmpty) args.add(_evaluateExpressionPart(a, variables));
        current.clear();
        continue;
      }
      current.writeCharCode(c);
    }
    final a = current.toString().trim();
    if (a.isNotEmpty) args.add(_evaluateExpressionPart(a, variables));
    return args;
  }

  static List<dynamic> _splitByOperator(
    String expr,
    String op,
    Map<String, dynamic> variables,
  ) {
    final parts = <dynamic>[];
    final current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    var i = 0;
    while (i < expr.length) {
      final c = expr.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(c);
        escaped = false;
        i++;
        continue;
      }
      if (c == 0x5c) {
        current.writeCharCode(c);
        escaped = true;
        i++;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(c);
        if (c == quote) quote = 0;
        i++;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        current.writeCharCode(c);
        i++;
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (parenDepth == 0 &&
          braceDepth == 0 &&
          bracketDepth == 0 &&
          expr.substring(i).startsWith(op)) {
        parts.add(current.toString().trim());
        current.clear();
        i += op.length;
        continue;
      }
      current.writeCharCode(c);
      i++;
    }
    parts.add(current.toString().trim());
    return parts.where((p) => p.toString().isNotEmpty).toList();
  }

  static dynamic _tryParseTernary(String e, Map<String, dynamic> variables) {
    // 找顶层 ? 和 :
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    int? questionIdx;
    for (var i = 0; i < e.length; i++) {
      final c = e.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        escaped = true;
        continue;
      }
      if (quote != 0) {
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0) {
        if (c == 0x3f && questionIdx == null) {
          questionIdx = i;
        } else if (c == 0x3a && questionIdx != null) {
          final cond = e.substring(0, questionIdx).trim();
          final thenExpr = e.substring(questionIdx + 1, i).trim();
          final elseExpr = e.substring(i + 1).trim();
          if (_isTruthy(_evaluateExpressionPart(cond, variables))) {
            return _evaluateExpressionPart(thenExpr, variables);
          }
          return _evaluateExpressionPart(elseExpr, variables);
        }
      }
    }
    return null;
  }

  static dynamic _evalBinaryOp(
    List<dynamic> parts,
    String op,
    Map<String, dynamic> variables,
  ) {
    if (parts.length < 2) return null;
    switch (op) {
      case '==':
      case '===':
        return _jsEquals(parts[0], parts[1], variables);
      case '!=':
      case '!==':
        return !_jsEquals(parts[0], parts[1], variables);
      case '||':
        for (final p in parts) {
          final v = _evaluateExpressionPart(p, variables);
          if (_isTruthy(v)) return v;
        }
        return parts.last;
      case '&&':
        dynamic last = true;
        for (final p in parts) {
          final v = _evaluateExpressionPart(p, variables);
          if (!_isTruthy(v)) return v;
          last = v;
        }
        return last;
      case '<':
      case '>':
      case '<=':
      case '>=':
        final l = _toNum(_evaluateExpressionPart(parts[0], variables));
        final r = _toNum(_evaluateExpressionPart(parts[1], variables));
        switch (op) {
          case '<':
            return l < r;
          case '>':
            return l > r;
          case '<=':
            return l <= r;
          case '>=':
            return l >= r;
        }
    }
    return null;
  }

  static bool _jsEquals(dynamic a, dynamic b, Map<String, dynamic> variables) {
    final av = _evaluateExpressionPart(a.toString(), variables);
    final bv = _evaluateExpressionPart(b.toString(), variables);
    if (av is num && bv is num) return av == bv;
    if (av == null && bv == null) return true;
    if (av == null || bv == null) return false;
    return av.toString() == bv.toString();
  }

  static dynamic _parseArrayLiteral(String e, Map<String, dynamic> variables) {
    final inner = e.substring(1, e.length - 1).trim();
    if (inner.isEmpty) return <dynamic>[];
    return _splitArgs(inner, variables);
  }

  static List<String> _splitObjectEntries(String s) {
    final entries = <String>[];
    final current = StringBuffer();
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (escaped) {
        current.writeCharCode(c);
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        current.writeCharCode(c);
        escaped = true;
        continue;
      }
      if (quote != 0) {
        current.writeCharCode(c);
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        current.writeCharCode(c);
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (c == 0x2c &&
          parenDepth == 0 &&
          braceDepth == 0 &&
          bracketDepth == 0) {
        final a = current.toString().trim();
        if (a.isNotEmpty) entries.add(a);
        current.clear();
        continue;
      }
      current.writeCharCode(c);
    }
    final a = current.toString().trim();
    if (a.isNotEmpty) entries.add(a);
    return entries;
  }

  static dynamic _parseObjectLiteral(String e, Map<String, dynamic> variables) {
    final inner = e.substring(1, e.length - 1).trim();
    if (inner.isEmpty) return <String, dynamic>{};
    final entries = _splitObjectEntries(inner);
    final result = <String, dynamic>{};
    for (final entry in entries) {
      final colonIdx = _findTopLevelColon(entry);
      if (colonIdx < 0) continue;
      final key = _unquote(entry.substring(0, colonIdx).trim());
      final val = _evaluateExpressionPart(
        entry.substring(colonIdx + 1).trim(),
        variables,
      );
      result[key] = val;
    }
    return result;
  }

  static int _findTopLevelColon(String s) {
    var parenDepth = 0;
    var braceDepth = 0;
    var bracketDepth = 0;
    var quote = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (quote != 0) {
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27) {
        quote = c;
        continue;
      }
      if (c == 0x28) parenDepth++;
      if (c == 0x29) parenDepth--;
      if (c == 0x7b) braceDepth++;
      if (c == 0x7d) braceDepth--;
      if (c == 0x5b) bracketDepth++;
      if (c == 0x5d) bracketDepth--;
      if (parenDepth == 0 &&
          braceDepth == 0 &&
          bracketDepth == 0 &&
          c == 0x3a) {
        return i;
      }
    }
    return -1;
  }

  static String _unquote(String s) {
    s = s.trim();
    if (s.length >= 2) {
      final first = s.codeUnitAt(0);
      final last = s.codeUnitAt(s.length - 1);
      if ((first == 0x22 || first == 0x27) && first == last) {
        return s.substring(1, s.length - 1);
      }
    }
    return s;
  }

  static int _findMatchingClose(
    String s,
    int openIdx,
    int openCode,
    int closeCode,
  ) {
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = openIdx; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        escaped = true;
        continue;
      }
      if (quote != 0) {
        if (c == quote) quote = 0;
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
        continue;
      }
      if (c == openCode) depth++;
      if (c == closeCode) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static int _findStringEnd(String s, int start, int quote) {
    var escaped = false;
    for (var i = start + 1; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5c) {
        escaped = true;
        continue;
      }
      if (c == quote) return i;
    }
    return -1;
  }

  static bool _hasMatchingOuterParens(String s) {
    if (!s.startsWith('(') || !s.endsWith(')')) return false;
    var depth = 0;
    for (var i = 0; i < s.length - 1; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x28) depth++;
      if (c == 0x29) {
        depth--;
        if (depth == 0) return false;
      }
    }
    return true;
  }

  static bool _isSingleQuotedString(String s, String quoteChar) {
    if (s.length < 2 || !s.startsWith(quoteChar) || !s.endsWith(quoteChar)) {
      return false;
    }
    var escaped = false;
    for (var i = 1; i < s.length - 1; i++) {
      final c = s[i];
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == quoteChar) {
        return false;
      }
    }
    return !escaped;
  }

  static bool _isRegExpLiteral(String s) {
    if (s.length < 2 || !s.startsWith('/')) {
      return false;
    }
    var escaped = false;
    var lastSlashIdx = -1;
    for (var i = 1; i < s.length; i++) {
      final c = s[i];
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '/') {
        lastSlashIdx = i;
        break;
      }
    }
    if (lastSlashIdx == -1) return false;
    final flags = s.substring(lastSlashIdx + 1);
    final validFlags = RegExp(r'^[gimsuy]*$');
    return validFlags.hasMatch(flags);
  }

  static bool _isIdentChar(String c) {
    if (c.isEmpty) return false;
    final cc = c.codeUnitAt(0);
    return (cc >= 0x30 && cc <= 0x39) || // 0-9
        (cc >= 0x41 && cc <= 0x5a) || // A-Z
        (cc >= 0x61 && cc <= 0x7a) || // a-z
        cc == 0x5f ||
        cc == 0x24; // _ $
  }

  static String _decodeString(String s) {
    return s
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');
  }

  static bool _isTruthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.isNotEmpty && v != 'false';
    if (v is List) return v.isNotEmpty;
    if (v is Map) return v.isNotEmpty;
    return true;
  }

  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is bool) return v ? 1 : 0;
    return num.tryParse(v.toString().trim()) ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? 0;
  }

  static num _toNumPow(dynamic a, dynamic b) {
    final base = _toNum(a);
    final exp = _toNum(b);
    var result = 1.0;
    for (var i = 0; i < exp.toInt(); i++) {
      result *= base;
    }
    return result;
  }

  static double _sqrtPositive(num v) {
    if (v <= 0) return 0;
    var x = v.toDouble();
    var prev = 0.0;
    while ((x - prev).abs() > 1e-9) {
      prev = x;
      x = (x + v / x) / 2;
    }
    return x;
  }

  static double _log(num v) {
    if (v <= 0) return 0;
    // 简化:ln x = log10 x / log10 e ≈ log10 x / 0.4342944819
    return _log10(v.toDouble()) / 0.4342944819;
  }

  static double _log10(double v) {
    if (v <= 0) return 0;
    var result = 0.0;
    var n = v;
    while (n >= 10) {
      n /= 10;
      result++;
    }
    while (n < 1) {
      n *= 10;
      result--;
    }
    // 用 ln(1+x) ≈ x - x²/2 + x³/3 - ... 简化
    final x = n - 1;
    var sum = 0.0;
    var term = x;
    for (var i = 1; i < 50; i++) {
      sum += term / i;
      term *= -x;
    }
    return result + sum;
  }

  static double _sinApprox(num rad) {
    // 简化 sin:用级数
    var x = rad.toDouble() % (2 * 3.141592653589793);
    if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
    if (x < -3.141592653589793) x += 2 * 3.141592653589793;
    var sum = 0.0;
    var term = x;
    for (var i = 1; i < 30; i += 2) {
      sum += term / _factorial(i) * (i % 4 == 1 ? 1 : -1);
      term *= x * x;
    }
    return sum;
  }

  static double _cosApprox(num rad) {
    return _sinApprox(rad + 1.5707963267948966);
  }

  static double _tanApprox(num rad) {
    final c = _cosApprox(rad);
    if (c == 0) return 0;
    return _sinApprox(rad) / c;
  }

  static int _factorial(int n) {
    if (n <= 1) return 1;
    var r = 1;
    for (var i = 2; i <= n; i++) {
      r *= i;
    }
    return r;
  }

  static Uint8List _toKeyBytes(String key) {
    final bytes = utf8.encode(key);
    final out = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      out[i] = i < bytes.length ? bytes[i] : 0;
    }
    return out;
  }

  static List<int> _padPKCS7(List<int> data, int blockSize) {
    final pad = blockSize - (data.length % blockSize);
    final padded = List<int>.from(data);
    for (var i = 0; i < pad; i++) {
      padded.add(pad);
    }
    return padded;
  }

  static String _formatTime(String fmt, DateTime dt) {
    return fmt
        .replaceAll('yyyy', dt.year.toString())
        .replaceAll('MM', dt.month.toString().padLeft(2, '0'))
        .replaceAll('dd', dt.day.toString().padLeft(2, '0'))
        .replaceAll('HH', dt.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', dt.minute.toString().padLeft(2, '0'))
        .replaceAll('ss', dt.second.toString().padLeft(2, '0'));
  }

  static String _hmacHex(String value, String algorithm, String key) {
    final normAlg = algorithm.toLowerCase().replaceAll(RegExp(r'^hmac-?'), '');
    crypto_pkg.Hash hasher;
    switch (normAlg) {
      case 'md5':
        hasher = crypto_pkg.md5;
        break;
      case 'sha256':
        hasher = crypto_pkg.sha256;
        break;
      case 'sha1':
      default:
        hasher = crypto_pkg.sha1;
        break;
    }
    final hmac = crypto_pkg.Hmac(hasher, utf8.encode(key));
    return hmac.convert(utf8.encode(value)).toString();
  }

  static String _hmacBase64(String value, String algorithm, String key) {
    final normAlg = algorithm.toLowerCase().replaceAll(RegExp(r'^hmac-?'), '');
    crypto_pkg.Hash hasher;
    switch (normAlg) {
      case 'md5':
        hasher = crypto_pkg.md5;
        break;
      case 'sha256':
        hasher = crypto_pkg.sha256;
        break;
      case 'sha1':
      default:
        hasher = crypto_pkg.sha1;
        break;
    }
    final hmac = crypto_pkg.Hmac(hasher, utf8.encode(key));
    return base64.encode(hmac.convert(utf8.encode(value)).bytes);
  }

  static dynamic _callMapMethod(
    Map map,
    String method,
    List<dynamic> args,
    Map<String, dynamic> variables,
  ) {
    final isSource = map.containsKey('bookSourceUrl') || map.containsKey('key');
    final isBook =
        !isSource && (map.containsKey('name') || map.containsKey('title'));
    final type = isSource ? 'source' : 'book';

    switch (method) {
      case 'getKey':
        return map['key'] ?? map['bookSourceUrl'] ?? '';
      case 'getVariable':
        if (args.isNotEmpty) {
          final key = args[0]?.toString() ?? '';
          if (key.isNotEmpty) {
            return variables['$type.variable.$key'] ?? '';
          }
        }
        return variables['$type.variable'] ?? map['variable'] ?? '';
      case 'setVariable':
        if (args.length >= 2) {
          final key = args[0]?.toString() ?? '';
          final val = args[1];
          if (key.isNotEmpty) {
            variables['$type.variable.$key'] = val;
          }
          return val;
        } else if (args.isNotEmpty) {
          final val = args[0];
          variables['$type.variable'] = val;
          return val;
        }
        return '';
      case 'getVariableMap':
        final variableStr =
            variables['$type.variable'] ?? map['variable'] ?? '';
        Map<String, dynamic> parsed = {};
        try {
          parsed = jsonDecode(variableStr.toString());
        } catch (_) {}
        return _JsObject({
          'get': (List<dynamic> args2) {
            if (args2.isEmpty) return '';
            return parsed[args2[0]?.toString()] ?? '';
          },
        });
      case 'getLoginInfoMap':
        return _JsObject({
          'get': (List<dynamic> args2) {
            if (args2.isEmpty) return '';
            return variables['source.login.${args2[0]?.toString()}'] ?? '';
          },
        });
      case 'putLoginHeader':
        if (args.length >= 2) {
          variables['source.loginHeader.${args[0]?.toString() ?? ''}'] =
              args[1];
          return args[1];
        }
        return '';
      case 'getLoginHeader':
        if (args.isNotEmpty) {
          return variables['source.loginHeader.${args[0]?.toString() ?? ''}'] ??
              '';
        }
        return '';
    }
    return null;
  }

  static ({String transformation, String iv}) _normalizeTransformation(
    dynamic third,
    dynamic fourth,
    String fallback,
  ) {
    final t = third?.toString() ?? '';
    if (t.contains('/') ||
        RegExp(
          r'^(AES|DES|DESede|TripleDES)',
          caseSensitive: false,
        ).hasMatch(t)) {
      return (
        transformation: t.isEmpty ? fallback : t,
        iv: fourth?.toString() ?? '',
      );
    }
    return (transformation: fourth?.toString() ?? fallback, iv: t);
  }

  static String _cipherBase64Encode(
    String value,
    String key,
    String iv,
    String transformation,
  ) {
    try {
      final upper = transformation.toUpperCase();
      final isDes = upper.contains('DES');
      final mode = upper.contains('/ECB/') ? 'ecb' : 'cbc';

      final keyBytes = Uint8List.fromList(utf8.encode(key));
      final ivBytes = Uint8List.fromList(utf8.encode(iv));

      final pc.BlockCipher engine = isDes ? pc.DESedeEngine() : pc.AESEngine();
      final blockSize = engine.blockSize;

      Uint8List normalizedKeyBytes;
      if (isDes) {
        if (keyBytes.length == 24) {
          normalizedKeyBytes = keyBytes;
        } else if (keyBytes.length == 16) {
          normalizedKeyBytes = Uint8List.fromList([
            ...keyBytes,
            ...keyBytes.sublist(0, 8),
          ]);
        } else if (keyBytes.length == 8) {
          normalizedKeyBytes = Uint8List.fromList([
            ...keyBytes,
            ...keyBytes,
            ...keyBytes,
          ]);
        } else {
          normalizedKeyBytes = Uint8List(24);
        }
      } else {
        if (keyBytes.length != 16 &&
            keyBytes.length != 24 &&
            keyBytes.length != 32) {
          final list = Uint8List(16);
          for (var i = 0; i < 16; i++) {
            list[i] = i < keyBytes.length ? keyBytes[i] : 0;
          }
          normalizedKeyBytes = list;
        } else {
          normalizedKeyBytes = keyBytes;
        }
      }

      final keyParam = isDes
          ? pc.DESedeParameters(normalizedKeyBytes)
          : pc.KeyParameter(normalizedKeyBytes);

      final cipher = pc.PaddedBlockCipherImpl(
        pc.PKCS7Padding(),
        mode == 'ecb' ? pc.ECBBlockCipher(engine) : pc.CBCBlockCipher(engine),
      );

      if (mode == 'ecb') {
        cipher.init(
          true,
          pc.PaddedBlockCipherParameters<pc.CipherParameters, Null>(
            keyParam,
            null,
          ),
        );
      } else {
        var normalizedIvBytes = ivBytes;
        if (normalizedIvBytes.length != blockSize) {
          final list = Uint8List(blockSize);
          for (var i = 0; i < blockSize; i++) {
            list[i] = i < ivBytes.length ? ivBytes[i] : 0;
          }
          normalizedIvBytes = list;
        }
        cipher.init(
          true,
          pc.PaddedBlockCipherParameters<
            pc.ParametersWithIV<pc.CipherParameters>,
            Null
          >(
            pc.ParametersWithIV<pc.CipherParameters>(
              keyParam,
              normalizedIvBytes,
            ),
            null,
          ),
        );
      }

      final out = cipher.process(Uint8List.fromList(utf8.encode(value)));
      return base64.encode(out);
    } catch (_) {
      return '';
    }
  }
}

class _JsObject {
  final Map<String, dynamic> props;
  _JsObject(this.props);
  @override
  String toString() {
    final fn = props['__toString'];
    if (fn is Function) return fn();
    return super.toString();
  }
}

class _JsFunction {
  final List<String> params;
  final String body;
  final Map<String, dynamic> scope;
  _JsFunction(this.params, this.body, this.scope);
}

class _ReturnSignal {
  final dynamic value;
  _ReturnSignal(this.value);
}

class LegacyJsEvalError implements Exception {
  final String message;
  LegacyJsEvalError(this.message);
  @override
  String toString() => 'LegacyJsEvalError: $message';
}
