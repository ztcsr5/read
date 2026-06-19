import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/parsers/legado/legacy_js_evaluator.dart';

void main() {
  test('yisou book source JS evaluation', () {
    final code = """//showjname设置章节名显示卷名true or false
  let obj = {showjname: false}
  let \$ = JSON.parse(String(result))
  let array = []
  \$.volumes.forEach((booklet) => {
  	  java.put('jname',booklet.name)
    array.push({ 
    	    name:'◆◇'+String(booklet.name)+'◇◆',
    	    voltype:true
    	 })
    booklet.chapters.forEach((chapter) => {
href='http://api.ieasou.com/api/bookapp/chargeChapter.m?a=1&autoBuy=0&cid=eef_easou_book&version=002&os=android&udid=1c5b2618a57a0848e2510649dc1e03896f462284&appverion=1122&ch=blf1298_12337_001&session_id=-nEvkqSq_9ZyORN5OoVOOzJ&dzh=1&scp=0&appid=10001&utype=0&rtype=3&pushid=f97b7f81a269472c07708277b7c40b4f&ptype=5&gender=0&userInitPay=3&birt=1658424532472&instime=1658424529924&instId=1658424529924&chType=3&bidType=0&recSw=1&appType=0&gid='+java.get('gid')+'&nid='+chapter.nid+'&sort='+chapter.sort+'&gsort=0&sgsort=0&sequence=4&chapter_name='+chapter.chapter_name
      array.push({
        name: !java.get('jname')?chapter.chapter_name:((obj.showjname?'※'+java.get('jname')+'※ ':'').padStart(3,''))+chapter.chapter_name,
        url: href,
        voltype:false
      })
    })
  })
  array""";

    final vars = {
      'result': jsonEncode({
        'volumes': [
          {
            'name': '正文卷',
            'chapters': [
              {
                'nid': 53259,
                'chapter_name': '001 滴血',
                'wordCount': 1675,
                'sort': 1,
              }
            ]
          }
        ]
      }),
    };
    final res = LegacyJsEvaluator.evaluate(code, variables: vars);
    expect(res, isA<List>());
    final list = res as List;
    expect(list.length, 2);
    expect(list[0]['name'], '◆◇正文卷◇◆');
    expect(list[0]['voltype'], true);
    expect(list[1]['name'], '001 滴血');
    expect(list[1]['voltype'], false);
    expect(list[1]['url'], contains('nid=53259'));
  });
}
