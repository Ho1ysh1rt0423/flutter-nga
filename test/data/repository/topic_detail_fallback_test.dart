import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_nga/data/repository/topic_repository.dart';

/// 与 `test/utils/parser/html_topic_detail_parser_test.dart` 同构的最小 o17
/// 信封：楼层骨架 + 原始 UBB + userInfo 数据块 + __PAGE 分页。
const String _fixtureHtml = '''
<!DOCTYPE html><html><head></head><body>
<script>
__CURRENT_FID=parseInt('7') __CURRENT_TID=47981481
</script>
<script type='text/javascript'>
//userinfostart
commonui.userInfo.setAll(  {"111":{"uid":111,"username":"作者甲","credit":169083431,"medal":null,"reputation":"39_21000","groupid":-1,"memberid":39,"avatar":"","yz":4,"site":null,"honor":null,"regdate":1617865798,"mute_time":null,"postnum":24706,"rvrc":7149,"money":10730703,"thisvisit":1795260282,"signature":"","nickname":null,"bit_data":169083431}} );
</script>
<table class='forumbox postbox' cellspacing='1px'>
<tr id='post1strow0' class='postrow row0'>
<td class='c1'><span id='posterinfo0' class='posterinfo'><a href='nuke.php?func=ucp&uid=111' id='postauthor0' class='author b'></a></span></td>
<td class='c2' id='postcontainer0'><a id='pid888001Anchor'></a><a name='l0'></a>
<div class='postBtnPos' id='postBtnPos0'></div>
<div class='postInfo' id='postInfo0'><span id='postdate0' title='reply time'>2026-11-26 00:40</span></div>
<span id='postcontentandsubject0'>
<h3 id='postsubject0'>被截断的帖子</h3><br/>
<span id='postcontent0' class='postcontent ubbcode'>主楼正文</span>
</span></td>
<script>\$('posterinfo0'),\$('postInfo0'),\$('postBtnPos0'), null,null,0,33554432, null,'111',1795624830,'0,0,0','210', '','','0 /','',null,0 )</script>
</tr>
<tr id='post1strow1' class='postrow row1'>
<td class='c1'><span id='posterinfo1' class='posterinfo'><a href='nuke.php?func=ucp&uid=111' id='postauthor1' class='author b'></a></span></td>
<td class='c2' id='postcontainer1'><a id='pid888002Anchor'></a>
<div class='postBtnPos' id='postBtnPos1'></div>
<div class='postInfo' id='postInfo1'><span id='postdate1' title='reply time'>2026-11-26 00:47</span></div>
<span id='postcontentandsubject1'>
<h3 id='postsubject1'></h3><br/>
<span id='postcontent1' class='postcontent ubbcode'>1 楼正文</span>
</span></td>
<script>\$('posterinfo1'),\$('postInfo1'),\$('postBtnPos1'), null,null,1,0, null,'111',1795625228,'0,0,0','84', '','','0 /','',null,0 )</script>
</tr>
</table>
<div id='pagebtop'><script>var __PAGE = {0:'/read.php?tid=47981481',1:1,2:1,3:20};</script></div>
</body></html>
''';

/// 记录每次请求的地址；o8 恒返回被截断的 JSON，o17 返回完整信封。
///
/// 复刻实测到的服务端行为：同一 tid 反复请求拿回的坏对象字节数完全一致，
/// 所以这里的截断体是固定的。
class _TruncatingThenHtmlAdapter implements HttpClientAdapter {
  final List<String> requests = [];

  static const _truncatedO8 =
      '{"data":{"__GLOBAL":{},"__R":{"0":{"pid":0,"lou":0,"content":"主楼正';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    final isHtmlChannel = url.contains('__output=17');
    final body = isHtmlChannel
        ? '{"code":521,"msg":"","htmlTitle":"被截断的帖子","template":"read",'
              '"html":${_jsonEncode(_fixtureHtml)}}'
        : _truncatedO8;
    return ResponseBody.fromBytes(
      Uint8List.fromList(_gbkBytes(body)),
      200,
      headers: {
        Headers.contentTypeHeader: [
          isHtmlChannel
              ? 'text/javascript; charset=UTF-8'
              : 'text/javascript; charset=GBK',
        ],
      },
    );
  }

  /// 简单转义：只处理会破坏 JSON 的三类字符，HTML fixture 里没有别的特殊符号。
  static String _jsonEncode(String s) {
    final b = StringBuffer('"');
    for (final c in s.split('')) {
      switch (c) {
        case '"':
          b.write(r'\"');
        case '\\':
          b.write(r'\\');
        case '\n':
          b.write(r'\n');
        case '\r':
          b.write(r'\r');
        case '\t':
          b.write(r'\t');
        default:
          b.write(c);
      }
    }
    b.write('"');
    return b.toString();
  }

  /// fixture 含中文，必须按 GBK 编码 —— 拦截器统一用 GbkCodec 解码，
  /// 直接用 codeUnits（UTF-16）会得到乱码并破坏 JSON。
  static List<int> _gbkBytes(String s) => const GbkCodec().encode(s);

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Dio dio;
  late _TruncatingThenHtmlAdapter adapter;
  late TopicDataRepository repository;

  setUp(() async {
    db = await databaseFactoryMemory.openDatabase('topic-fallback-test.db');
    dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    adapter = _TruncatingThenHtmlAdapter();
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);
    repository = TopicDataRepository(db, dio);
  });

  tearDown(() async {
    await db.close();
  });

  test('o8 截断时不再重试，直接回退 o17 并拿到完整数据', () async {
    final data = await repository.getTopicDetail(47981481, 1, null);

    // 1 次 o8（重试上限 0，不再白等 0.9s + 2.5s）+ 1 次 o17。
    expect(adapter.requests, hasLength(2), reason: '重试上限为 0，不应出现第三次请求');
    expect(adapter.requests[0], contains('__output=8'));
    expect(adapter.requests[1], contains('__output=17'));
    expect(adapter.requests[1], contains('__localres=1'));

    // 回退拿到的是 o17 的完整楼层，且不再标记 truncated。
    expect(data.truncated, isFalse, reason: 'o17 通道数据完整');
    expect(data.replyList.length, 2);
    expect(data.replyList['0']!.pid, 888001);
    expect(data.replyList['1']!.content, '1 楼正文');
    expect(data.topic?.subject, '被截断的帖子');
    expect(data.maxPage, 1);
  });

  test('o17 也拿不到楼层时回落到抢救数据，且只请求一次 o17（不死循环）', () async {
    final alwaysFail = _HtmlWithoutFloorsAdapter();
    dio.httpClientAdapter = alwaysFail;
    final repo = TopicDataRepository(db, dio);

    final data = await repo.getTopicDetail(47981481, 1, null);

    // 设计如此：回退失败就用抢救出的部分数据，并明确标记不完整。
    expect(data.truncated, isTrue, reason: '抢护出的数据不完整，必须标记');

    // o17 必须只请求一次：带 htmlChannelKey 的请求失败后不能再触发回退。
    final htmlRequests = alwaysFail.requests.where(
      (u) => u.contains('__output=17'),
    );
    expect(htmlRequests, hasLength(1), reason: '回退失败后不得再次回退');
  });

  test('o8 完整时不发 o17 请求', () async {
    dio.httpClientAdapter = _CompleteO8Adapter();
    final repo = TopicDataRepository(db, dio);

    final data = await repo.getTopicDetail(1, 1, null);

    expect(_CompleteO8Adapter.requests, hasLength(1));
    expect(_CompleteO8Adapter.requests.single, contains('__output=8'));
    expect(data.truncated, isFalse);
  });
}

/// o8 恒截断、o17 拿不出楼层：验证「回退失败回落到抢救数据」且不死循环。
class _HtmlWithoutFloorsAdapter implements HttpClientAdapter {
  final List<String> requests = [];

  static const _truncatedO8 =
      '{"data":{"__GLOBAL":{},"__R":{"0":{"pid":0,"lou":0,"content":"主楼正';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requests.add(url);
    final isHtmlChannel = url.contains('__output=17');
    final body = isHtmlChannel
        ? '{"code":521,"msg":"","html":"<html><body>no floors</body></html>"}'
        : _truncatedO8;
    return ResponseBody.fromBytes(
      Uint8List.fromList(body.codeUnits),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/javascript; charset=GBK'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 完整 o8 响应。
class _CompleteO8Adapter implements HttpClientAdapter {
  static final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    return ResponseBody.fromBytes(
      Uint8List.fromList(
        '{"data":{"__GLOBAL":{},"__R":{"0":{"pid":0,"lou":0,"content":"主楼"}},'
                '"__U":{},"__T":{"tid":1,"subject":"正常帖"},'
                '"__ROWS":20,"__R__ROWS":20,"__R__ROWS_PAGE":20}}'
            .codeUnits,
      ),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/javascript; charset=GBK'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
