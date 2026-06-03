import 'package:read/data/parsers/legado_parser.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/models/book.dart';
import 'dart:convert';

void main() async {
  final source = BookSource(
    id: 1,
    bookSourceName: 'Test',
    bookSourceGroup: 'Test',
    bookSourceUrl: 'http://test.com',
    ruleSearch: '{"bookUrl": "bbnnfgh/\$.bid\\n1100000000+parseInt(result)\\nhttps://bookshelf.html5.qq.com/qbread/api/novel/intro-info?bookid="}',
  );
  
  final jsonStr = '''{
    "bid": "468914",
    "title": "斗破苍穹"
  }''';
  
  final item = jsonDecode(jsonStr);
  final rule = jsonDecode(source.ruleSearch!);
  
  // Try to use reflection or just copy the logic
  // Since private methods are not accessible, let's copy the logic here:
  final ruleValue = rule['bookUrl'];
  print("Rule: \$ruleValue");
  
  // Wait, I can't call private methods directly. 
}
