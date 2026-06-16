import '../../../data/models/book_source.dart';

enum SourceCheckFailureClass { failed, blocked }

SourceCheckFailureClass classifySourceCheckFailure(
  BookSource source, {
  required String? failStep,
  required String? message,
}) {
  return sourceCheckFailureIsBlocked(
        source,
        failStep: failStep,
        message: message,
      )
      ? SourceCheckFailureClass.blocked
      : SourceCheckFailureClass.failed;
}

bool sourceCheckFailureIsBlocked(
  BookSource source, {
  required String? failStep,
  required String? message,
}) {
  final text = '${failStep ?? ''} ${message ?? ''} ${source.customConfig ?? ''}'
      .toLowerCase();

  if (failStep == 'JS 环境' || failStep == 'WebView 环境' || failStep == '站点验证') {
    return true;
  }

  // 异常类(TimeoutException/网络异常/解析崩溃):直接归入"失效",不进入待复测。
  // 因为这种源在当前规则下 100% 跑不通,等用户/作者改源才能复活,不是 runtime 临时问题。
  if (failStep == '异常') {
    return false;
  }

  if (_looksLikeNetworkOrRuntimeBlock(text)) return true;

  if ((failStep == '搜索 URL' ||
          failStep == '搜索结果' ||
          failStep == '请求搜索页' ||
          failStep == '目录' ||
          failStep == '正文') &&
      sourceNeedsRuntimeOrAccess(source)) {
    return true;
  }

  return false;
}

bool sourceNeedsRuntimeOrAccess(BookSource source) {
  final joined = [
    source.searchUrl,
    source.ruleSearch,
    source.ruleBookInfo,
    source.ruleToc,
    source.ruleContent,
    source.ruleExplore,
    source.customConfig,
  ].whereType<String>().join('\n').toLowerCase();

  return joined.contains('@js') ||
      joined.contains('<js') ||
      joined.contains('java.ajax') ||
      joined.contains('java.get') ||
      joined.contains('java.put') ||
      joined.contains('jslib') ||
      joined.contains('bodyjs') ||
      joined.contains('webview') ||
      joined.contains('loginurl') ||
      joined.contains('loginui') ||
      joined.contains('logincheckjs') ||
      joined.contains('cookie') ||
      joined.contains('headers') ||
      joined.contains('"header"') ||
      joined.contains('booksourceheader') ||
      joined.contains('httpuseragent') ||
      joined.contains('jsonpath') ||
      joined.contains('sourceRegex'.toLowerCase()) ||
      joined.contains('nextcontenturl') ||
      joined.contains('nexttocurl');
}

bool _looksLikeNetworkOrRuntimeBlock(String text) {
  return text.contains('quickjs') ||
      text.contains('node js fallback') ||
      text.contains('javaimporter') ||
      text.contains('packages.java') ||
      text.contains('packages.javax') ||
      text.contains('webview') ||
      text.contains('headless webview') ||
      text.contains('验证码') ||
      text.contains('安全验证') ||
      text.contains('需要跳验证') ||
      text.contains('接口鉴权不合法') ||
      text.contains('鉴权不合法') ||
      text.contains('签名错误') ||
      text.contains('签名失败') ||
      text.contains('invalid signature') ||
      text.contains('signature error') ||
      text.contains('"retcode":2') ||
      text.contains("'retcode':2") ||
      text.contains('响应体为空') ||
      text.contains('empty response') ||
      text.contains('response body empty') ||
      text.contains('cloudflare') ||
      text.contains('loginurl') ||
      text.contains('timeout') ||
      text.contains('timed out') ||
      text.contains('socketexception') ||
      text.contains('handshake') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection') ||
      text.contains('desencodetobase64string') ||
      text.contains('aesbase64') ||
      text.contains('is not a function') && text.contains('java.');
}
