import '../../../data/models/book_source.dart';

enum SourceCheckFailureClass { failed, blocked, needsLogin, needsVerify }

SourceCheckFailureClass classifySourceCheckFailure(
  BookSource source, {
  required String? failStep,
  required String? message,
}) {
  final text = '${failStep ?? ''} ${message ?? ''} ${source.customConfig ?? ''}'
      .toLowerCase();

  // 优先识别"需登录"和"需验证"状态,避免被误判为 blocked 或 failed
  if (_looksLikeNeedsLogin(text)) {
    return SourceCheckFailureClass.needsLogin;
  }
  if (_looksLikeNeedsVerify(text)) {
    return SourceCheckFailureClass.needsVerify;
  }

  return sourceCheckFailureIsBlocked(
        source,
        failStep: failStep,
        message: message,
      )
      ? SourceCheckFailureClass.blocked
      : SourceCheckFailureClass.failed;
}

bool _looksLikeNeedsLogin(String text) {
  return text.contains('登录页') ||
      text.contains('需登录') ||
      text.contains('login') ||
      text.contains('unauthorized') ||
      text.contains('请先登录') ||
      text.contains('未登录');
}

bool _looksLikeNeedsVerify(String text) {
  return text.contains('验证页') ||
      text.contains('需验证') ||
      text.contains('cloudflare') ||
      text.contains('challenge') ||
      text.contains('安全验证') ||
      text.contains('人机验证') ||
      text.contains('验证码');
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

  // 优先识别网络超时、连接重置等临时性或环境阻断异常为 blocked，避免误判为失效源
  if (_looksLikeNetworkOrRuntimeBlock(text)) return true;

  // 其余真正的运行期崩溃、空指针等未知异常归入"失效"
  if (failStep == '异常') {
    return false;
  }

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
      text.contains('future not completed') ||
      text.contains('future not complete') ||
      text.contains('desencodetobase64string') ||
      text.contains('aesbase64') ||
      text.contains('is not a function') && text.contains('java.');
}
