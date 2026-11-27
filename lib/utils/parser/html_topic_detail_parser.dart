import 'dart:convert';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/utils/json_cast.dart';

/// 「官方 HTML 通道」详情解析器。
///
/// `read.php?__output=17`（NGA 官方 App 详情页在用的输出格式）返回的是服务端
/// 渲染好的楼层骨架：
/// - 每层一行 `<tr id='post1strow{N}'>`，`N` 是**全局楼号**（翻页后继续往上
///   累加，page=2 直接从 20 起；「只看作者」时才从 0 重排），正文在
///   `id='postcontent{N}'` 里，内容是**原始 UBB**（和 `__output=8` 的
///   `content` 字段同源）；
/// - pid 在 `id='pid{pid}Anchor'` 锚点，作者 uid 在 `postauthor{N}` 的
///   `ucp&uid={uid}` 链接，发帖时间戳在楼层内联 JS 参数里；
/// - **楼主 uid** 取 `commonui.postArg.setDefault(fid, stid, tid, tid, {authorid})`
///   的第 4 个参数（翻页后恒定不变）。⚠️ 不能拿「本页第一楼」当楼主：
///   page>1 时第一楼只是普通回复者，那样会把回复者标成楼主、真正的楼主反而
///   没有标记；
/// - 楼中楼评论在 `id='comment_for_{N}'` 段内（`div.comment_c`），
///   热点回复在 `id='hightlight_for_{N}'` 段内，两者字段同构；
/// - 附件在同层的 `ubbcode.attach.load('postattach{N}', ...)` 脚本参数里，
///   与 `__output=8` 的 `attachs` 是同一批数据；
/// - `commonui.userInfo.setAll({...})` 携带本页全部用户资料（键为 uid）——
///   只有本页出现的用户，page>1 时通常**不含楼主**，所以作者名可能为空；
/// - `var __PAGE = {0:..., 1:总页数, 2:当前页, 3:每页行数}` 携带分页信息。
///
/// 当 `__output=8` 的 JSON 被服务端截断（重试+抢救都失败）时，用本通道回退
/// 拿完整数据。解析失败返回 null，调用方回落到原始错误。
TopicDetailData? parseHtmlTopicDetail(
  Map<String, dynamic> envelope, {
  required int tid,
  required int page,
}) {
  final html = envelope["html"];
  if (html is! String || html.isEmpty) return null;

  final rawUsers = _extractUserInfoBlock(html);
  final userList = <String, User>{};
  rawUsers.forEach((uidKey, value) {
    if (value is Map) {
      final user = User.fromJson(asJsonMap(value, 'HtmlTopicDetail.user'));
      final key = int.tryParse(uidKey);
      if (key != null && user.uid != key) {
        user.uid = key;
      }
      userList[uidKey] = user;
    }
  });

  final fid = int.tryParse(
    RegExp(r"__CURRENT_FID=parseInt\('(\d+)'\)").firstMatch(html)?.group(1) ??
        '',
  );

  final pageInfo = _extractPageInfo(html);
  final floors = _extractFloors(html, tid: tid, fid: fid);
  if (floors.isEmpty) return null;

  final perPage = pageInfo?.$2 ?? floors.length;
  final maxPage = pageInfo?.$1 ?? page;
  final rows = maxPage * perPage;

  // 楼主 uid 只能来自 `postArg.setDefault` 的专用参数：**本页第一楼在翻页后
  // 就是普通回复者**，拿它当楼主会把第一个回复者标成「楼主」，真正的楼主
  // 反倒没有标记（就是这一步引入的 bug）。
  //
  // page=1 时第一楼就是主楼，`setDefault` 缺失时仍可回落到它；page>1 时
  // 拿不到楼主 uid 就留空（宁可没有标记，也不能标错人）。
  final opUid =
      _extractTopicAuthorUid(html) ?? (page == 1 ? floors.first.uid : null);
  final opUser = opUid == null ? null : rawUsers['$opUid'];
  final topic = Topic.fromJson({
    "tid": tid,
    "fid": fid,
    "subject": envelope["htmlTitle"]?.toString() ?? '',
    // page>1 的 userInfo 块里没有楼主（服务端只下发本页出现的用户），
    // 拿不到就留空，别用第一楼的名字顶替。
    "author": opUser is Map ? opUser["username"]?.toString() ?? '' : '',
    "authorid": opUid,
    // 主楼发帖时间只有 page=1 能拿到，翻页后第一楼的时间是回复时间。
    "postdate": page == 1 ? floors.first.postDateTimestamp : null,
    "replies": rows,
    "page": page,
  });

  final replyList = <String, Reply>{};
  for (final floor in floors) {
    replyList[floor.indexKey] = Reply(
      content: floor.content ?? '',
      tid: tid,
      postDate: floor.postDate,
      postDateTimestamp: floor.postDateTimestamp,
      authorId: floor.uid,
      subject: floor.subject,
      fid: fid,
      pid: floor.pid,
      lou: floor.lou,
      commentList: floor.comments,
      attachmentList: floor.attachments,
    );
  }

  // 热点回复只挂在主楼段落里（`hightlight_for_0`），等价于 o8 的
  // `__R["0"]["hotreply"]`。HTML 侧不携带 lou，用同页楼层的 pid→lou
  // 反查补上——热评通常就是本页某层，补不到为 null（跳转回落到 pid）。
  final pidToLou = <int, int>{
    for (final floor in floors)
      if (floor.pid != null && floor.pid! > 0) floor.pid!: floor.lou,
  };
  final hotReplyList = <Reply>[];
  for (final floor in floors) {
    if (floor.hotReplies.isEmpty) continue;
    for (final hot in floor.hotReplies) {
      final lou = hot.pid == null ? null : pidToLou[hot.pid!];
      hotReplyList.add(
        lou == null || hot.lou == lou
            ? hot
            : (Reply(
                content: hot.content,
                alterInfo: hot.alterInfo,
                tid: hot.tid,
                score: hot.score,
                score2: hot.score2,
                postDate: hot.postDate,
                authorId: hot.authorId,
                subject: hot.subject,
                type: hot.type,
                fid: hot.fid,
                pid: hot.pid,
                recommend: hot.recommend,
                lou: lou,
                postDateTimestamp: hot.postDateTimestamp,
                commentList: hot.commentList,
                attachmentList: hot.attachmentList,
              )),
      );
    }
    break;
  }

  return TopicDetailData(
    userList: userList,
    replyList: replyList,
    groupList: const {},
    medalList: const {},
    reputationList: const {},
    global: null,
    rows: rows,
    currentRows: floors.length,
    replyPageRows: perPage,
    truncated: false,
    topic: topic,
    hotReplies: [
      for (final hot in hotReplyList)
        if (hot.pid != null) hot.pid!,
    ],
    hotReplyList: hotReplyList,
  );
}

class _HtmlFloor {
  final String indexKey;
  final int lou;
  final int? pid;
  final int? uid;
  final String subject;
  final String? content;
  final String? postDate;
  final int? postDateTimestamp;
  final List<Reply> comments;
  final List<Attachment> attachments;

  /// 本层下方「热点回复」段里的楼层（实测只出现在主楼）。
  final List<Reply> hotReplies;

  const _HtmlFloor({
    required this.indexKey,
    required this.lou,
    this.pid,
    this.uid,
    this.subject = '',
    this.content,
    this.postDate,
    this.postDateTimestamp,
    this.comments = const [],
    this.attachments = const [],
    this.hotReplies = const [],
  });
}

/// 按楼层行标记 `id='post1strow{N}'` 切块，每块内再提取各字段。
///
/// `N` 是**全局楼层号**（实测 9 个帖子 × 3 页、27/27 与 o8 的 `lou` 完全一致：
/// page=2 是 20..39，page=3 是 40..59），不是每页从 0 重排的页内序号——
/// 只有「只看作者」（带 `authorid`）时才从 0 重新计，那种模式下 o8 的 `lou`
/// 同样从 0 起算，两边一致。
///
/// 时间戳取自楼层内联 JS 参数（形如 `,'15403840',1794564555,`）。
List<_HtmlFloor> _extractFloors(String html, {required int tid, int? fid}) {
  final rowMarks = RegExp(r"id='post1strow(\d+)'").allMatches(html).toList();
  final floors = <_HtmlFloor>[];
  for (var i = 0; i < rowMarks.length; i++) {
    final mark = rowMarks[i];
    final n = int.tryParse(mark.group(1)!);
    if (n == null) continue;
    final chunkEnd = i + 1 < rowMarks.length ? rowMarks[i + 1].start : null;
    final chunk = chunkEnd == null
        ? html.substring(mark.start)
        : html.substring(mark.start, chunkEnd);

    final pid = int.tryParse(
      RegExp(r"id='pid(\d+)Anchor'").firstMatch(chunk)?.group(1) ?? '',
    );
    final uid = int.tryParse(
      RegExp(r"ucp&uid=(\d+)").firstMatch(chunk)?.group(1) ?? '',
    );
    final subject =
        RegExp("id='postsubject$n'[^>]*>([\\s\\S]*?)</h3>")
            .firstMatch(chunk)
            ?.group(1) ??
        '';
    final content = _balancedInner(chunk, 'postcontent$n');
    final postDate =
        RegExp("id='postdate$n'[^>]*>([^<]*)<").firstMatch(chunk)?.group(1) ??
        '';
    int? postDateTimestamp;
    if (uid != null) {
      postDateTimestamp = int.tryParse(
        RegExp(",'$uid',(\\d+),").firstMatch(chunk)?.group(1) ?? '',
      );
    }

    floors.add(
      _HtmlFloor(
        indexKey: '$n',
        // 行号本身就是全局楼号（见函数注释），不要按页数再偏移一次：
        // page=2 的 `post1strow20` 就是 20 楼，再乘 (page-1)*perPage 会翻倍。
        lou: n,
        pid: pid,
        uid: uid,
        subject: subject,
        content: content,
        postDate: postDate,
        postDateTimestamp: postDateTimestamp,
        comments: _extractCommentBlocks(
          _commentRegion(chunk, n),
          tid: tid,
          fid: fid,
        ),
        attachments: _extractAttachments(chunk, n),
        hotReplies: _extractCommentBlocks(
          _hotReplyRegion(chunk, n),
          tid: tid,
          fid: fid,
        ),
      ),
    );
  }
  return floors;
}

/// `id='comment_for_{N}'` 到 `id='hightlight_for_{N}'`（或楼层末尾）之间是
/// 楼中楼评论。两段标记缺失时返回空串。
String _commentRegion(String chunk, int n) {
  final open = RegExp("id='comment_for_$n'").firstMatch(chunk);
  if (open == null) return '';
  final hot = RegExp("id='hightlight_for_$n'").firstMatch(chunk);
  final end = hot == null || hot.start < open.start ? chunk.length : hot.start;
  if (open.start >= end) return '';
  return chunk.substring(open.start, end);
}

/// `id='hightlight_for_{N}'` 之后到楼层末尾是「热点回复」段。
String _hotReplyRegion(String chunk, int n) {
  final hot = RegExp("id='hightlight_for_$n'").firstMatch(chunk);
  if (hot == null) return '';
  return chunk.substring(hot.start);
}

/// 解析 `div.comment_c` 块列表（评论与热评结构同构）。
///
/// 每块以 `id='commentposterinfo{suffix}'` 开头，块内字段：
/// - `id='commentauthor{suffix}'` 链接里的 `ucp&uid=` → 作者；
/// - `id='postcommentsubject{suffix}'` / `id='postcomment{suffix}'` → 标题 / 正文；
/// - `id='commentInfo{suffix}'` 里的 `title='reply time'` → 发帖时间；
/// - 块尾 `commonui.postArg.proc('<suffix>', ...)` 是**权威来源**：
///   `...,null,null,{pid},{type},null,'{uid}',{ts},'{recommend,score,score2}',...`。
///
/// 热评的 suffix 形如 `__888980001`（双下划线），普通评论是 `_889118304`。
/// 但**不能用 suffix 猜 type**：实测 `__888981581` 的 type 是 64，按
/// 「热评=0/评论=1」猜会错，type 一律从 proc 参数取。
List<Reply> _extractCommentBlocks(String region, {required int tid, int? fid}) {
  if (region.isEmpty) return const [];
  final marks = RegExp(r"id='commentposterinfo(_+\d+)'")
      .allMatches(region)
      .toList();
  final result = <Reply>[];
  for (var i = 0; i < marks.length; i++) {
    final start = marks[i].start;
    final end = i + 1 < marks.length ? marks[i + 1].start : region.length;
    if (start >= end) continue;
    final block = region.substring(start, end);
    final suffix = marks[i].group(1)!;

    // `postArg.proc( '<suffix>', ... )` 的参数体
    final proc = RegExp(r"postArg\.proc\(\s*'_*\d+',([\s\S]*?)\)\s*</script>")
        .firstMatch(block)
        ?.group(1);
    // `null,null,{pid},{type},`
    final pidType = proc == null
        ? null
        : RegExp(r"null,null,(\d+),(-?\d+),").firstMatch(proc);
    final pid =
        int.tryParse(pidType?.group(1) ?? '') ??
        int.tryParse(suffix.replaceAll('_', ''));
    // pid 解析不出就没法跳转/去重，整块丢掉比塞进无 pid 的评论更安全
    if (pid == null || pid <= 0) continue;

    // `'{uid}',{ts},'{recommend,score,score2}'`（proc 缺失时逐项回落）
    final identity = proc == null
        ? null
        : RegExp(r"'(\d+)',(\d{9,}),'(-?\d+),(-?\d+),(-?\d+)'")
              .firstMatch(proc);
    final uid =
        int.tryParse(identity?.group(1) ?? '') ??
        int.tryParse(
          RegExp(r"ucp&uid=(\d+)").firstMatch(block)?.group(1) ?? '',
        );
    final postDateTimestamp =
        int.tryParse(identity?.group(2) ?? '') ??
        int.tryParse(
          RegExp(r",'(\d{5,})',(\d{9,}),").firstMatch(block)?.group(2) ?? '',
        );
    final score =
        int.tryParse(identity?.group(4) ?? '') ??
        int.tryParse(
          RegExp(r"'(-?\d+),(-?\d+),(-?\d+)'").firstMatch(block)?.group(2) ??
              '',
        );

    final subject = _balancedInner(block, 'postcommentsubject$suffix') ?? '';
    final content = _balancedInner(block, 'postcomment$suffix') ?? '';
    final postDate =
        RegExp(
          "id='commentInfo${RegExp.escape(suffix)}'[\\s\\S]*?<span[^>]*>([^<]*)<",
        ).firstMatch(block)?.group(1) ??
        '';

    result.add(
      Reply(
        content: content,
        tid: tid,
        fid: fid,
        pid: pid,
        authorId: uid,
        subject: subject,
        postDate: postDate,
        postDateTimestamp: postDateTimestamp,
        score: score ?? 0,
        type: int.tryParse(pidType?.group(2) ?? ''),
        lou: 0,
        commentList: const [],
        attachmentList: const [],
      ),
    );
  }
  return result;
}

/// 解析同层 `ubbcode.attach.load('postattach{N}','postcontent{N}',[ {...} ], ...)`。
///
/// 数组元素是 JS 对象字面量（键无引号、值单引号），不是合法 JSON，
/// 逐对象抓 `键:'值'` 即可；字段与 o8 的 `attachs` 一一对应。
List<Attachment> _extractAttachments(String chunk, int n) {
  final marker = RegExp("ubbcode\\.attach\\.load\\('postattach$n'")
      .firstMatch(chunk);
  if (marker == null) return const [];
  final arrayStart = chunk.indexOf('[', marker.end);
  if (arrayStart < 0) return const [];
  final arrayBody = _jsArrayBody(chunk, arrayStart);
  if (arrayBody == null) return const [];

  final result = <Attachment>[];
  for (final object in _jsObjects(arrayBody)) {
    final fields = <String, String>{};
    for (final m in RegExp(r"(\w+)\s*:\s*'([^']*)'").allMatches(object)) {
      fields[m.group(1)!] = m.group(2)!;
    }
    final url = fields['url'];
    if (url == null || url.isEmpty) continue;
    final slash = url.lastIndexOf('/');
    final dot = url.lastIndexOf('.');
    result.add(
      Attachment(
        attachUrl: url,
        size: int.tryParse(fields['size'] ?? ''),
        type: fields['type'],
        urlUtf8OrgName: fields['url_utf8_org_name'],
        dscp: fields['dscp'],
        path: slash > 0 ? url.substring(0, slash) : null,
        name: fields['name'],
        ext: dot > slash && dot >= 0 ? url.substring(dot + 1) : null,
        thumb: int.tryParse(fields['thumb'] ?? ''),
      ),
    );
  }
  return result;
}

/// 从 [start]（指向 `[`）起扫描到配平的 `]`，返回中间内容。
/// 跳过单引号字符串内的括号，避免文件名里的 `]` 提前结束。
String? _jsArrayBody(String source, int start) {
  var depth = 0;
  var inString = false;
  for (var i = start; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (ch == "'") inString = false;
      continue;
    }
    if (ch == "'") {
      inString = true;
    } else if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) return source.substring(start + 1, i);
    }
  }
  return null;
}

/// 切出数组里的每个 `{...}` 对象（同样跳过字符串内的花括号）。
Iterable<String> _jsObjects(String source) sync* {
  var depth = 0;
  var inString = false;
  var objectStart = -1;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inString) {
      if (ch == "'") inString = false;
      continue;
    }
    if (ch == "'") {
      inString = true;
    } else if (ch == '{') {
      if (depth == 0) objectStart = i;
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0 && objectStart >= 0) {
        yield source.substring(objectStart, i + 1);
        objectStart = -1;
      }
    }
  }
}

/// 取出 `id='{id}'` 标签的完整内容（按同名标签配平扫描）。
///
/// 不能用「非贪婪 + 遇到第一个 `</span>`/`</p>`」：正文里一旦出现嵌套
/// `<span>`（`[color]`、折叠、引用被服务端渲染成标签时就会），非贪婪匹配
/// 会在**第一个**闭合标签处截断——表现和服务端截断一模一样，极难排查。
/// 未配平（响应本身被截断）时返回剩余全部内容，宁多勿丢。
String? _balancedInner(String source, String id) {
  final open = RegExp("<(span|p|h3|div) id='${RegExp.escape(id)}'[^>]*>")
      .firstMatch(source);
  if (open == null) return null;
  final tag = open.group(1)!;
  final start = open.end;
  final tagPattern = RegExp('</?$tag\\b[^>]*>');
  var depth = 1;
  for (final m in tagPattern.allMatches(source, start)) {
    if (m.group(0)!.startsWith('</')) {
      depth--;
      if (depth == 0) return source.substring(start, m.start);
    } else {
      depth++;
    }
  }
  return source.substring(start);
}

/// 提取 `commonui.userInfo.setAll( {...} )` 里的用户数据块。
///
/// 块里是合法 JSON（键带引号），但签名等字符串可能含裸控制字符，解析前清洗。
/// 括号配平失败（响应异常）返回空表。
Map<String, dynamic> _extractUserInfoBlock(String html) {
  const key = 'commonui.userInfo.setAll(';
  final start = html.indexOf(key);
  if (start < 0) return {};
  final objStart = start + key.length;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = objStart; i < html.length; i++) {
    final ch = html[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        final block = html
            .substring(objStart, i + 1)
            .replaceAllMapped(RegExp('[\\x00-\\x1F]'), (_) => ' ');
        try {
          final decoded = json.decode(block);
          return decoded is Map<String, dynamic> ? decoded : {};
        } catch (_) {
          return {};
        }
      }
    }
  }
  return {};
}

/// 主题作者（楼主）的 uid。
///
/// `commonui.postArg.setDefault(fid, stid, tid, {tid}, {authorid}, ...)` 的
/// 第 4 个参数是**主题作者 uid**，实测在 page 1/2/3 上都恒定不变
/// （9 个帖子 × 3 页，27/27 与 o8 的 `__T.authorid` 一致）。
/// 这是 HTML 里唯一权威的楼主标识，别拿第一楼作者顶替（翻页后就是另一个人）。
///
/// 解析失败返回 null（老版本页面 / 结构变化），调用方按页面位置兜底。
int? _extractTopicAuthorUid(String html) {
  final match = RegExp(
    r"commonui\.postArg\.setDefault\(\s*-?\d+\s*,\s*-?\d+\s*,\s*-?\d+\s*,\s*(\d+)",
  ).firstMatch(html);
  if (match == null) return null;
  final uid = int.tryParse(match.group(1)!);
  if (uid == null || uid <= 0) return null;
  return uid;
}

/// `var __PAGE = {0:..., 1:总页数, 2:当前页, 3:每页行数}`。
/// 缺失或字段异常返回 null，调用方按当前页兜底。
(int, int)? _extractPageInfo(String html) {
  final match = RegExp(r"var __PAGE = (\{[^}]+\})").firstMatch(html);
  if (match == null) return null;
  final body = match.group(1)!;
  final maxPage = int.tryParse(
    RegExp(r"1:(\d+)").firstMatch(body)?.group(1) ?? '',
  );
  final perPage = int.tryParse(
    RegExp(r"3:(\d+)").firstMatch(body)?.group(1) ?? '',
  );
  if (maxPage == null || perPage == null || maxPage <= 0 || perPage <= 0) {
    return null;
  }
  return (maxPage, perPage);
}
