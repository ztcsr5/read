import sys, pathlib

target = pathlib.Path('lib/data/parsers/legado_parser.dart')
content = target.read_text(encoding='utf-8')

marker = 'JS 引擎诊断'
if marker in content:
    print('already patched, skipping')
    sys.exit(0)

anchor = "      if (searchUrl.trim().isEmpty) {\n        steps.add(\n"
n = content.count(anchor)
if n != 1:
    print('ERROR anchor count =', n)
    sys.exit(1)

replacement = (
    "      if (searchUrl.trim().isEmpty) {\n"
    "        urlLogs.add('—— JS 引擎诊断（排查真机为何返回空）——');\n"
    "        urlLogs.add('QuickJS 引擎可用(_runtime 已加载): ${LegadoJsEngine().isAvailable}');\n"
    "        urlLogs.add('是否落到 Node 兜底: ${LegadoJsEngine().isUsingNodeFallback}');\n"
    "        urlLogs.add('该 searchUrl 是否含 JS 规则: ${_containsJsRule(source.searchUrl)}');\n"
    "        steps.add(\n"
)

content = content.replace(anchor, replacement, 1)
target.write_text(content, encoding='utf-8')
print('patched ok')
