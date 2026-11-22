import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/utils/parser/html_topic_detail_parser.dart';

/// 与真实 `read.php?__output=17` 响应同构的最小信封（逆向自官方 App 的详情
/// 页用法）。楼层骨架 + 原始 UBB + userInfo 数据块 + __PAGE 分页。
const String fixtureHtml = '''
<!DOCTYPE html><html><head></head><body>
<script>
__CURRENT_FID=parseInt('414') __CURRENT_F_BIT=parseInt('33554664') __CURRENT_TID=47912491
</script>
<script type='text/javascript'>
//userinfostart
commonui.userInfo.setAll(  {"111":{"uid":111,"username":"作者甲","credit":169083431,"medal":null,"reputation":"39_21000","groupid":-1,"memberid":39,"avatar":"https://img.nga.cn/avatars/2002/a.jpg","yz":4,"site":null,"honor":null,"regdate":1617865798,"mute_time":null,"postnum":24706,"rvrc":7149,"money":10730703,"thisvisit":1795260282,"signature":"I miss my cat","nickname":null,"bit_data":169083431},"222":{"uid":222,"username":"回复乙","credit":135266304,"medal":null,"reputation":"61_145","groupid":-1,"memberid":39,"avatar":"https://img.nga.cn/avatars/2002/b.jpg","yz":4,"site":null,"honor":null,"regdate":1670585315,"mute_time":null,"postnum":41,"rvrc":10,"money":0,"thisvisit":1794988510,"signature":null,"nickname":null,"bit_data":135266304}} );
</script>
<table class='forumbox postbox' cellspacing='1px'>
<tr id='post1strow0' class='postrow row0'>
<td class='c1'><span id='posterinfo0' class='posterinfo'><a href='nuke.php?func=ucp&uid=111' id='postauthor0' class='author b'></a></span></td>
<td class='c2' id='postcontainer0'><a id='pid999001Anchor'></a><a name='l0'></a>
<div class='postBtnPos' id='postBtnPos0'></div>
<div class='postInfo' id='postInfo0'><span id='postdate0' title='reply time'>2026-11-13 18:09</span></div>
<span id='postcontentandsubject0'>
<h3 id='postsubject0'>[新游杂谈No.35]标题示例</h3><br/>
<span id='postcontent0' class='postcontent ubbcode'>放眼整个JRPG。[b]加粗[/b]<br/>[quote]引用内容[/quote][img]./mon_2026/xx.jpg[/img]</span>
</span></td>
<script>\$('posterinfo0'),\$('postInfo0'),\$('postBtnPos0'), null,null,0,33566720, null,'111',1794564555,'10,50,0','1472', '','','0 /','',null,0 )</script>
</tr>
<tr id='post1strow1' class='postrow row1'>
<td class='c1'><span id='posterinfo1' class='posterinfo'><a href='nuke.php?func=ucp&uid=222' id='postauthor1' class='author b'></a></span></td>
<td class='c2' id='postcontainer1'><a id='pid999002Anchor'></a>
<div class='postBtnPos' id='postBtnPos1'></div>
<div class='postInfo' id='postInfo1'><span id='postdate1' title='reply time'>2026-11-13 18:11</span></div>
<span id='postcontentandsubject1'>
<h3 id='postsubject1'></h3><br/>
<span id='postcontent1' class='postcontent ubbcode'>回复内容测试</span>
</span></td>
<script>\$('posterinfo1'),\$('postInfo1'),\$('postBtnPos1'), null,null,1,33566720, null,'222',1794564700,'10,0,0','1472', '','','0 /','',null,0 )</script>
</tr>
</table>
<div id='pagebtop'><a href='/read.php?tid=1&page=2' title='下一页' class='pager_spacer'>下一页(2)</a><script>var __PAGE = {0:'/read.php?tid=1',1:3,2:1,3:20};commonui.pageBtn(document.getElementById('pageBtnHere').parentNode,__PAGE,true)</script></div>
</body></html>
''';

Map<String, dynamic> envelope({String? html}) => {
  "code": 521,
  "msg": "",
  "htmlBaseUrl": "https://ngabbs.com/read.php?tid=1",
  "htmlTitle": "[新游杂谈No.35]标题示例",
  "template": "read",
  "html": html ?? fixtureHtml,
};

void main() {
  group('完整信封', () {
    final data = parseHtmlTopicDetail(envelope(), tid: 1, page: 1)!;

    test('楼层全部解析', () {
      expect(data.replyList.keys, ['0', '1']);
      expect(data.replyList['0']!.pid, 999001);
      expect(data.replyList['1']!.pid, 999002);
      expect(data.replyList['0']!.authorId, 111);
      expect(data.replyList['1']!.authorId, 222);
      expect(data.replyList['0']!.lou, 0);
      expect(data.replyList['1']!.lou, 1);
      expect(data.replyList['0']!.postDateTimestamp, 1794564555);
      expect(data.replyList['1']!.postDateTimestamp, 1794564700);
      expect(data.replyList['0']!.postDate, '2026-11-13 18:09');
    });

    test('UBB 正文原样保留（不做解析改写）', () {
      expect(
        data.replyList['0']!.content,
        '放眼整个JRPG。[b]加粗[/b]<br/>[quote]引用内容[/quote][img]./mon_2026/xx.jpg[/img]',
      );
      expect(data.replyList['1']!.content, '回复内容测试');
    });

    test('subject：主楼带标题，回复为空', () {
      expect(data.replyList['0']!.subject, '[新游杂谈No.35]标题示例');
      expect(data.replyList['1']!.subject, '');
    });

    test('用户数据块', () {
      expect(data.userList.keys, ['111', '222']);
      expect(data.userList['111']!.username, '作者甲');
      expect(data.userList['222']!.username, '回复乙');
    });

    test('分页与主题', () {
      expect(data.rows, 60, reason: '总页数 3 × 每页 20');
      expect(data.replyPageRows, 20);
      expect(data.currentRows, 2);
      expect(data.maxPage, 3);
      expect(data.truncated, isFalse);
      expect(data.topic!.subject, '[新游杂谈No.35]标题示例');
      expect(data.topic!.author, '作者甲', reason: '作者名来自 userInfo 块');
      expect(data.topic!.authorId, 111);
      expect(data.topic!.fid, 414);
      expect(data.topic!.postDate, 1794564555);
    });
  });

  test('page=2 时楼号偏移按每页行数换算', () {
    final data = parseHtmlTopicDetail(envelope(), tid: 1, page: 2)!;
    expect(data.replyList['0']!.lou, 20);
    expect(data.replyList['1']!.lou, 21);
    expect(data.topic!.page, 2);
  });

  group('字段缺失防御', () {
    test('challenge 信封（html 为空）返回 null', () {
      expect(parseHtmlTopicDetail(envelope(html: ''), tid: 1, page: 1), isNull);
    });

    test('信封缺 html 键返回 null', () {
      expect(
        parseHtmlTopicDetail({"code": 15, "msg": "访客不能直接访问"}, tid: 1, page: 1),
        isNull,
      );
    });

    test('缺 userInfo 块：楼层仍解析，作者回落空串', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.userInfo\.setAll\(.*?\);", dotAll: true),
        '// removed',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.userList, isEmpty);
      expect(data.replyList.keys, ['0', '1']);
      expect(
        data.replyList['0']!.authorId,
        111,
        reason: 'uid 来自楼层锚点，不依赖 userInfo',
      );
      expect(data.topic!.author, '');
    });

    test('楼层缺 pid 锚点：楼层保留，pid 为 null', () {
      final html = fixtureHtml.replaceAll("id='pid999002Anchor'></a>", '');
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.replyList['1']!.pid, isNull);
      expect(data.replyList['1']!.content, '回复内容测试');
    });

    test('缺 __PAGE：按本页楼层数兜底，页数回落当前页', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"var __PAGE = \{[^}]+\}"),
        'var __PAGE = {}',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.replyPageRows, 2, reason: '楼层数兜底');
      expect(data.maxPage, 1, reason: '总页数不可信时回落当前页');
      expect(data.rows, 2);
    });

    test('userInfo 块括号不配平（被截断）：用户为空不崩', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.userInfo\.setAll\(.*?\);", dotAll: true),
        'commonui.userInfo.setAll(  {"111":{"uid":111,"username":"截',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.userList, isEmpty);
      expect(data.replyList.keys, ['0', '1']);
    });

    test('签名含裸控制字符：清洗后仍能解析', () {
      final html = fixtureHtml.replaceFirst('I miss my cat', '第一行\n第二行\t制表');
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.userList['111']!.signature, contains('第二行'));
    });

    test('html 无楼层标记返回 null', () {
      final html = fixtureHtml.replaceAll(
        RegExp(r"id='post1strow\d+'"),
        "id='row'",
      );
      expect(
        parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1),
        isNull,
      );
    });
  });
}
