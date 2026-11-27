import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/utils/parser/html_topic_detail_parser.dart';

/// 与真实 `read.php?__output=17` 响应同构的最小信封（逆向自官方 App 的详情
/// 页用法）。楼层骨架 + 原始 UBB + userInfo 数据块 + __PAGE 分页。
///
/// `postArg.setDefault(fid, stid, tid, {tid}, {authorid}, ...)` 的第 4 个参数
/// 是主题作者 uid（111），翻到第 2 页也不变——它是唯一权威的楼主标识。
const String fixtureHtml = '''
<!DOCTYPE html><html><head></head><body>
<script>
__CURRENT_FID=parseInt('414') __CURRENT_F_BIT=parseInt('33554664') __CURRENT_TID=47912491
</script>
<script type='text/javascript'>
//userinfostart
commonui.userInfo.setAll(  {"111":{"uid":111,"username":"作者甲","credit":169083431,"medal":null,"reputation":"39_21000","groupid":-1,"memberid":39,"avatar":"https://img.nga.cn/avatars/2002/a.jpg","yz":4,"site":null,"honor":null,"regdate":1617865798,"mute_time":null,"postnum":24706,"rvrc":7149,"money":10730703,"thisvisit":1795260282,"signature":"I miss my cat","nickname":null,"bit_data":169083431},"222":{"uid":222,"username":"回复乙","credit":135266304,"medal":null,"reputation":"61_145","groupid":-1,"memberid":39,"avatar":"https://img.nga.cn/avatars/2002/b.jpg","yz":4,"site":null,"honor":null,"regdate":1670585315,"mute_time":null,"postnum":41,"rvrc":10,"money":0,"thisvisit":1794988510,"signature":null,"nickname":null,"bit_data":135266304}} );
</script>
<script type='text/javascript'>
commonui.postArg.setDefault(414,0,47912491,111,2,"","",",222,","",null,8228,248,1795752900)
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

/// 带楼中楼评论、热点回复、附件、以及正文含嵌套标签的信封。
///
/// 结构照抄真实 `__output=17` 响应（`tid=47981481`）：主楼下方先是
/// `comment_for_0` 段（`div.comment_c`），再是 `hightlight_for_0` 段，
/// 附件在 `ubbcode.attach.load('postattach0', ...)` 的脚本参数里。
const String fixtureWithComments = '''
<table class='forumbox postbox' cellspacing='1px'>
<tr id='post1strow0' class='postrow row2'>
<td class='c1'><span id='posterinfo0' class='posterinfo'><a href='nuke.php?func=ucp&uid=111' id='postauthor0' class='author b'></a></span></td>
<td class='c2' id='postcontainer0'><a id='pid0Anchor'></a><a name='l0'></a>
<div class='postInfo' id='postInfo0'><span id='postdate0' title='reply time'>2026-11-25 14:34</span></div>
<span id='postcontentandsubject0'>
<h3 id='postsubject0'>主楼标题</h3><br/>
<p id='postcontent0' class='postcontent ubbcode'>[color=red]红字[/color]<br/>[collapse]折叠里还有[color=blue]蓝字[/color][/collapse]<br/>[img]./mon/a.jpg[/img]</p>
<br/>
</span><h4 class='silver subtitle postbodysubtitle'>附件</h4><span id='postattach0'></span><script>ubbcode.attach.load('postattach0','postcontent0',[ {aid:'',url:'mon_202611/25/7Q58-6mqnZdT1kShs-np.jpg',name:'7Q58-6mqnZdT1kShs-np.jpg',type:'img',thumb:'56',dscp:'',size:'127',url_utf8_org_name:'a%2ejpg'},{aid:'',url:'mon_202611/25/7Q59-1xi8.webp',name:'7Q59-1xi8.webp',type:'img',thumb:'120',dscp:'',size:'381',url_utf8_org_name:'image%2epng'}],'0','47981481','111','1795588487','0')</script><div class=clear></div>
<span id='comment_for_0'><h4 class='silver subtitle postbodysubtitle'>评论</h4>
<div class='comment_c left'>
<span id='commentposterinfo_889118304' class='posterinfo'><a href='nuke.php?func=ucp&uid=65101124' id='commentauthor_889118304'>UID:65101124</a></span>
<table class='comment_c_0'><tr><td class='comment_c_1'></td><td class='comment_c_2 c3'>
<span id='postcommentcontentandsubject_889118304' class='comment_c_3'>
<span class='c1 postInfo' id='commentInfo_889118304'><span title='reply time'>2026-11-26 18:53</span></span>
<span id='postcommentsubject_889118304'></span>
<span id='postcomment_889118304'>[b]Reply to [tid=47981481]Topic[/tid][/b]<br/><br/>爬完了楼，看明白了。</span>
</span></td></tr></table>
<script>commonui.postArg.proc( '_889118304',
\$('postcommentcontainer_889118304'),\$('postcommentsubject_889118304'),\$('postcomment_889118304'),null,\$('commentposterinfo_889118304'),\$('commentInfo_889118304'),null,
null,null,889118304,1,
null,'65101124',1795690433,'0,0,0',null,
'','',null,'',null,0,0 )
</script>
</div>
<br class='commentblkoffset'/></span><span id='hightlight_for_0'><h4 class='silver subtitle postbodysubtitle'>热点回复</h4>
<div class='comment_c left'>
<span id='commentposterinfo__888980001' class='posterinfo'><a href='nuke.php?func=ucp&uid=7837005' id='commentauthor__888980001'>UID:7837005</a></span>
<table class='comment_c_0'><tr><td class='comment_c_1'></td><td class='comment_c_2 c3'>
<span id='postcommentcontentandsubject__888980001' class='comment_c_3'>
<span class='c1 postInfo' id='commentInfo__888980001'><span title='reply time'>2026-11-25 14:58</span></span>
<span id='postcommentsubject__888980001'></span>
<span id='postcomment__888980001'>你说尼玛呢？正式服开荒灭团找原因搁你这成卷了？</span>
</span></td></tr></table>
<script>commonui.postArg.proc( '__888980001',
\$('postcommentcontainer__888980001'),\$('postcommentsubject__888980001'),\$('postcomment__888980001'),null,\$('commentposterinfo__888980001'),\$('commentInfo__888980001'),null,
null,null,888980001,0,
null,'7837005',1795589895,'0,159,0',null,
'','',null,'',null,0,1 )
</script>
</div>
<br class='commentblkoffset'/>
<div class='comment_c left'>
<span id='commentposterinfo__888981581' class='posterinfo'><a href='nuke.php?func=ucp&uid=65173893' id='commentauthor__888981581'>UID:65173893</a></span>
<table class='comment_c_0'><tr><td class='comment_c_1'></td><td class='comment_c_2 c3'>
<span id='postcommentcontentandsubject__888981581' class='comment_c_3'>
<span class='c1 postInfo' id='commentInfo__888981581'><span title='reply time'>2026-11-25 15:10</span></span>
<span id='postcommentsubject__888981581'></span>
<span id='postcomment__888981581'>高级战斗日志数据是暴雪自己的程序采集的信息。</span>
</span></td></tr></table>
<script>commonui.postArg.proc( '__888981581',
\$('postcommentcontainer__888981581'),\$('postcommentsubject__888981581'),\$('postcomment__888981581'),null,\$('commentposterinfo__888981581'),\$('commentInfo__888981581'),null,
null,null,888981581,64,
null,'65173893',1795590607,'0,100,0',null,
'','',null,'',null,0,1 )
</script>
</div>
</span><div class=clear></div>
</td>
<script>commonui.postArg.proc( 0,
\$('postcontainer0'),\$('postsubject0'),\$('postcontent0'),\$('postsign0'),\$('posterinfo0'),\$('postInfo0'),\$('postBtnPos0'),
null,null,0,33562660,
null,'111',1795588487,'0,24,0','148',
'','','0 /','',null,0 )
</script>
</tr>
<tr id='post1strow5' class='postrow row2'>
<td class='c1'><span id='posterinfo5' class='posterinfo'><a href='nuke.php?func=ucp&uid=41725817' id='postauthor5' class='author b'></a></span></td>
<td class='c2' id='postcontainer5'><a id='pid888979096Anchor'></a>
<div class='postInfo' id='postInfo5'><span id='postdate5' title='reply time'>2026-11-25 14:41</span></div>
<span id='postcontentandsubject5'>
<h3 id='postsubject5'></h3><br/>
<span id='postcontent5' class='postcontent ubbcode'>我也刚收到邮件。</span>
</span></td>
<script>\$('posterinfo5'),\$('postInfo5'),null, null,null,888979096,8192, null,'41725817',1795589457,'0,17,0','145', '','','0 /','',null,0 )</script>
</tr>
</table>
<script>var __PAGE = {0:'/read.php?tid=47981481',1:13,2:1,3:20};</script>
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

  // 实测（9 个帖子 × 3 页，27/27）：`post1strow{N}` 的 N 就是全局楼号，
  // page=2 的响应里直接是 20..39，不需要按页偏移。
  test('page=2 的 post1strow20 就是 20 楼（行号即全局楼号，不再叠加偏移）', () {
    final html = fixtureHtml
        .replaceAll("id='post1strow0'", "id='post1strow20'")
        .replaceAll("id='post1strow1'", "id='post1strow21'")
        .replaceAll('posterinfo0', 'posterinfo20')
        .replaceAll('postInfo0', 'postInfo20')
        .replaceAll('postBtnPos0', 'postBtnPos20')
        .replaceAll('postdate0', 'postdate20')
        .replaceAll('postsubject0', 'postsubject20')
        .replaceAll('postcontent0', 'postcontent20')
        .replaceAll('postcontent1', 'postcontent21')
        .replaceAll('postcontainer1', 'postcontainer21')
        .replaceAll('postInfo1', 'postInfo21')
        .replaceAll('postBtnPos1', 'postBtnPos21')
        .replaceAll('postdate1', 'postdate21')
        .replaceAll('postsubject1', 'postsubject21')
        .replaceAll('postcontentandsubject1', 'postcontentandsubject21');
    final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 2)!;
    expect(data.replyList.keys, ['20', '21']);
    expect(data.replyList['20']!.lou, 20);
    expect(data.replyList['21']!.lou, 21);
    expect(data.topic!.page, 2);
  });

  group('楼主标识（翻页后不能把第一楼当楼主）', () {
    test('楼主 uid 取自 postArg.setDefault，不取第一楼作者', () {
      final data = parseHtmlTopicDetail(envelope(), tid: 1, page: 2)!;
      expect(data.replyList['0']!.authorId, 111);
      expect(
        data.topic!.authorId,
        111,
        reason: 'fixture 第一楼恰好也是楼主；换掉第一楼作者后仍应得到 111',
      );

      // 第一楼换成别人（真实 page>1 的样子）：楼主标记不能跟着跑掉
      final flipped = fixtureHtml.replaceFirst(
        "<a href='nuke.php?func=ucp&uid=111' id='postauthor0'",
        "<a href='nuke.php?func=ucp&uid=222' id='postauthor0'",
      );
      final data2 = parseHtmlTopicDetail(
        envelope(html: flipped),
        tid: 1,
        page: 2,
      )!;
      expect(data2.replyList['0']!.authorId, 222, reason: '第一楼现在不是楼主');
      expect(data2.topic!.authorId, 111, reason: '楼主 uid 来自 setDefault，与第一楼无关');
    });

    test('setDefault 缺失 + page>1：不猜楼主（宁可无标记也不标错人）', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.postArg\.setDefault\([^)]*\)"),
        '// removed',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 2)!;
      expect(data.topic!.authorId, isNull, reason: 'page>1 的第一楼不是楼主，不能顶替');
      expect(data.topic!.author, '');
    });

    test('setDefault 缺失 + page=1：回落到第一楼（第一楼就是主楼）', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.postArg\.setDefault\([^)]*\)"),
        '// removed',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.topic!.authorId, 111);
      expect(data.topic!.author, '作者甲');
    });

    test('page>1 的 userInfo 缺楼主：author 留空，不冒充别人', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.userInfo\.setAll\(.*?\);", dotAll: true),
        '// removed',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 2)!;
      expect(
        data.topic!.authorId,
        111,
        reason: 'uid 来自 setDefault，不依赖 userInfo',
      );
      expect(data.topic!.author, '');
    });

    test('page>1 不把第一楼的回复时间当成主楼发帖时间', () {
      final data = parseHtmlTopicDetail(envelope(), tid: 1, page: 2)!;
      expect(data.topic!.postDate, isNull);
      final p1 = parseHtmlTopicDetail(envelope(), tid: 1, page: 1)!;
      expect(p1.topic!.postDate, 1794564555);
    });

    // 真实响应第 5 个参数是位掩码（如 tid=47985561 的 67108897）而不是
    // 引号包裹的空串——取值不能假设后面接什么。
    test('setDefault 第 5 参是位掩码时仍取到楼主 uid', () {
      final html = fixtureHtml.replaceFirst(
        'setDefault(414,0,47912491,111,2,',
        'setDefault(510587,0,47912491,111,67108897,',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 2)!;
      expect(data.topic!.authorId, 111);
    });

    test('setDefault 结构异常（参数不足）时不误取、不崩', () {
      final html = fixtureHtml.replaceFirst(
        RegExp(r"commonui\.postArg\.setDefault\([^)]*\)"),
        "commonui.postArg.setDefault(414,0,47912491)",
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 2)!;
      expect(data.topic!.authorId, isNull, reason: '解析不出就不猜，避免标错人');
      expect(data.replyList, hasLength(2), reason: '楼层照常解析');
    });
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

  group('楼中楼评论与热点回复', () {
    final data = parseHtmlTopicDetail(
      envelope(html: fixtureWithComments),
      tid: 47981481,
      page: 1,
    )!;

    test('主楼评论挂到楼层 0', () {
      final comments = data.replyList['0']!.commentList;
      expect(comments, hasLength(1));
      final c = comments.first;
      expect(c.pid, 889118304);
      expect(c.authorId, 65101124, reason: 'uid 来自 commentauthor 链接');
      expect(c.type, 1, reason: 'type 取自 postArg.proc 参数，不是按 suffix 猜');
      expect(c.score, 0);
      expect(c.postDateTimestamp, 1795690433);
      expect(c.postDate, '2026-11-26 18:53');
      expect(
        c.content,
        startsWith('[b]Reply to [tid=47981481]Topic[/tid][/b]'),
      );
      expect(c.content, contains('爬完了楼，看明白了。'));
      expect(c.subject, '');
      expect(c.tid, 47981481, reason: '评论要带 tid，否则引用展开/骰子会失效');
    });

    test('热点回复单独成表，且 type 用真值', () {
      expect(data.hotReplyList, hasLength(2));
      final first = data.hotReplyList.first;
      expect(first.pid, 888980001);
      expect(first.authorId, 7837005);
      expect(first.type, 0);
      expect(first.score, 159);
      expect(first.postDateTimestamp, 1795589895);
      expect(first.content, '你说尼玛呢？正式服开荒灭团找原因搁你这成卷了？');

      // 实测 `__888981581` 的 type 是 64，按「热评=0」猜会错
      expect(
        data.hotReplyList[1].type,
        64,
        reason: 'type 必须从 postArg.proc 取；按 suffix 猜会得到 0',
      );
      expect(data.hotReplyList[1].score, 100);
    });

    test('热评不进楼层评论列表（两段互不串味）', () {
      expect(data.replyList['0']!.commentList, hasLength(1));
      expect(
        data.replyList['0']!.commentList.first.pid,
        889118304,
        reason: 'comment_for_0 段之外的热评不能混进 commentList',
      );
    });

    test('hotReplies（pid 列表）与 hotReplyList 一致', () {
      expect(data.hotReplies, [888980001, 888981581]);
    });

    test('热评的 lou 用同页 pid→lou 反查补上', () {
      // fixture 里 888980001 不在本页楼层中 → 反查不到，lou 与 o8 一致为 0
      expect(
        data.hotReplyList[0].lou,
        0,
        reason: 'o8 的 hotreply 对不在本页的热评同样下发 lou:0',
      );
      // 楼层 5 的 pid 在本页 → 能反查到
      expect(data.replyList['5']!.pid, 888979096);
      expect(data.replyList['5']!.lou, 5);
    });

    test('无评论无热评时两个列表都为空，不报错', () {
      final plain = parseHtmlTopicDetail(envelope(), tid: 1, page: 1)!;
      expect(plain.hotReplyList, isEmpty);
      expect(plain.hotReplies, isEmpty);
      expect(plain.replyList['0']!.commentList, isEmpty);
    });
  });

  group('附件', () {
    final data = parseHtmlTopicDetail(
      envelope(html: fixtureWithComments),
      tid: 47981481,
      page: 1,
    )!;

    test('从 ubbcode.attach.load 解析出附件', () {
      final attachments = data.replyList['0']!.attachmentList;
      expect(attachments, hasLength(2));
      final first = attachments.first;
      expect(first.attachUrl, 'mon_202611/25/7Q58-6mqnZdT1kShs-np.jpg');
      expect(first.name, '7Q58-6mqnZdT1kShs-np.jpg');
      expect(first.type, 'img');
      expect(first.size, 127);
      expect(first.thumb, 56);
      expect(first.path, 'mon_202611/25');
      expect(first.ext, 'jpg');
      expect(first.urlUtf8OrgName, 'a%2ejpg');
      expect(
        first.realUrl,
        endsWith('/mon_202611/25/7Q58-6mqnZdT1kShs-np.jpg'),
        reason: 'realUrl 拼的是图床前缀 + attachurl',
      );
    });

    test('webp 附件的 ext 正确', () {
      final second = data.replyList['0']!.attachmentList[1];
      expect(second.ext, 'webp');
      expect(second.thumb, 120);
    });

    test('无附件楼层为空列表', () {
      expect(data.replyList['5']!.attachmentList, isEmpty);
    });

    test('附件脚本缺失时为空，不崩', () {
      final html = fixtureWithComments.replaceFirst(
        'ubbcode.attach.load(',
        'noop.attach.load(',
      );
      final parsed = parseHtmlTopicDetail(
        envelope(html: html),
        tid: 1,
        page: 1,
      );
      expect(parsed, isNotNull);
      expect(parsed!.replyList['0']!.attachmentList, isEmpty);
    });

    test('附件数组里含 `]` 的文件名不提前截断', () {
      final html = fixtureWithComments.replaceFirst(
        "name:'7Q58-6mqnZdT1kShs-np.jpg'",
        "name:'7Q58-6mqnZdT1kShs-np].jpg'",
      );
      final parsed = parseHtmlTopicDetail(
        envelope(html: html),
        tid: 1,
        page: 1,
      )!;
      expect(
        parsed.replyList['0']!.attachmentList,
        hasLength(2),
        reason: '按字符串状态扫描，`]` 在引号内不算数组结束',
      );
    });
  });

  group('正文配平扫描', () {
    test('正文含嵌套标签时完整取出，不在第一个闭合标签处截断', () {
      final data = parseHtmlTopicDetail(
        envelope(html: fixtureWithComments),
        tid: 1,
        page: 1,
      )!;
      expect(
        data.replyList['0']!.content,
        '[color=red]红字[/color]<br/>[collapse]折叠里还有[color=blue]蓝字[/color][/collapse]<br/>[img]./mon/a.jpg[/img]',
        reason: '老实现（非贪婪 + 遇第一个 </span>/</p>）只取到「[color=red]红字[/color]<br/>」',
      );
    });

    test('正文里出现 <span> 标签时也不提前截断', () {
      final html = fixtureWithComments.replaceFirst(
        '<p id=\'postcontent0\' class=\'postcontent ubbcode\'>[color=red]红字[/color]',
        '<p id=\'postcontent0\' class=\'postcontent ubbcode\'><span style=\'color:red\'>红字</span>',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(
        data.replyList['0']!.content,
        startsWith('<span style=\'color:red\'>红字</span>'),
      );
      expect(
        data.replyList['0']!.content,
        contains('[img]./mon/a.jpg[/img]'),
        reason: '嵌套 span 的闭合标签不能让匹配提前结束',
      );
    });

    test('正文未闭合（响应被截断）：保留剩余全部内容，宁多勿丢', () {
      final html = fixtureWithComments.replaceFirst('</p>\n<br/>', '');
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1);
      expect(data, isNotNull);
      expect(data!.replyList['0']!.content, contains('[img]./mon/a.jpg[/img]'));
    });

    test('评论正文同样走配平，嵌套标签不截断', () {
      final html = fixtureWithComments.replaceFirst(
        '爬完了楼，看明白了。',
        '<span>b</span>爬完了楼，看明白了。',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      final content = data.replyList['0']!.commentList.first.content;
      expect(content, contains('<span>b</span>爬完了楼'));
      expect(content, endsWith('看明白了。'));
    });
  });

  group('评论/热评字段缺失防御', () {
    test('proc 调用缺失：pid 回落到 suffix，其余字段仍能解析', () {
      final html = fixtureWithComments.replaceFirst(
        RegExp(r"commonui\.postArg\.proc\( '_889118304',[\s\S]*?\)\n</script>"),
        '</script>',
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      final comments = data.replyList['0']!.commentList;
      expect(comments, hasLength(1));
      expect(comments.first.pid, 889118304, reason: 'suffix 就是 pid');
      expect(
        comments.first.authorId,
        65101124,
        reason: 'proc 缺失时 uid 回落到 commentauthor 链接',
      );
      expect(comments.first.content, contains('爬完了楼'));
    });

    test('评论块无正文：内容为空串但楼层仍在', () {
      final html = fixtureWithComments.replaceFirst(
        "<span id='postcomment_889118304'>[b]Reply to [tid=47981481]Topic[/tid][/b]<br/><br/>爬完了楼，看明白了。</span>",
        "<span id='postcomment_889118304'></span>",
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      final comments = data.replyList['0']!.commentList;
      expect(comments, hasLength(1));
      expect(comments.first.content, '');
      expect(comments.first.pid, 889118304);
    });

    test('评论段标记缺失：commentList 为空，楼层照常', () {
      final html = fixtureWithComments.replaceFirst(
        "<span id='comment_for_0'>",
        "<span class='noop'>",
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.replyList['0']!.commentList, isEmpty);
      expect(data.replyList['0']!.content, isNotEmpty);
      expect(data.hotReplyList, hasLength(2), reason: '热评段独立，不受评论段影响');
    });

    test('热评段标记缺失时按评论段兜底（不丢数据）', () {
      final html = fixtureWithComments.replaceFirst(
        "<span id='hightlight_for_0'>",
        "<span class='noop'>",
      );
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      // 两段的分界全靠 hightlight_for_N 标记；标记没了就无法区分，
      // 此时宁可把热评当成评论一起展示，也不静默丢弃。
      expect(data.hotReplyList, isEmpty);
      expect(data.replyList['0']!.commentList, hasLength(3));
      expect(
        data.replyList['0']!.commentList.first.pid,
        889118304,
        reason: '真评论排在最前，顺序不乱',
      );
    });

    test('pid 解析不出（suffix 非数字且无 proc）：整块跳过不塞脏数据', () {
      final html = fixtureWithComments
          .replaceFirst(
            RegExp(
              r"commonui\.postArg\.proc\( '_889118304',[\s\S]*?\)\n</script>",
            ),
            '</script>',
          )
          .replaceFirst(
            "id='commentposterinfo_889118304'",
            "id='commentposterinfo_'",
          )
          .replaceFirst(
            "id='postcommentsubject_889118304'",
            "id='postcommentsubject_'",
          )
          .replaceFirst("id='postcomment_889118304'", "id='postcomment_'")
          .replaceFirst("id='commentInfo_889118304'", "id='commentInfo_'");
      final data = parseHtmlTopicDetail(envelope(html: html), tid: 1, page: 1)!;
      expect(data.replyList['0']!.commentList, isEmpty);
    });
  });
}
