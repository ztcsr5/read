import 'package:read/data/parsers/legado/legado_rule_evaluator.dart';
import 'dart:convert';

void main() {
  final rule = '''\$.bid
<js>1100000000+parseInt(result)</js>
https://bookshelf.html5.qq.com/qbread/api/novel/intro-info?bookid=''';
  print("Rule: \$rule");
  print("Result: " + LegadoRuleEvaluator.extractJsonValue({"bid": "468914"}, rule));
}
