import 'dart:convert';
import 'lib/data/parsers/legado/legado_rule_evaluator.dart';

void main() {
  final rule = "bbnnfgh/\$.bid\n1100000000+parseInt(result)\nhttps://bookshelf.html5.qq.com/qbread/api/novel/intro-info?bookid=";
  print(LegadoRuleEvaluator.extractJsonValue({"bid":"123"}, rule));
}
