import 'dart:convert';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/utils/json_cast.dart';

/// 「官方 HTML 通道」详情解析器。
///
/// `read.php?__output=17`（NGA 官方 App 详情页在用的输出格式）返回的是服务端
/// 渲染好的楼层骨架：
/// - 每层一行 `<tr id='post1strow{N}'>`，正文在 `id='postcontent{N}'` 里，
///   内容是**原始 UBB**（和 `__output=8` 的 `content` 字段同源）；
/// - pid 在 `id='pid{pid}Anchor'` 锚点，作者 uid 在 `postauthor{N}` 的
///   `ucp&uid={uid}` 链接，发帖时间戳在楼层内联 JS 参数里；
/// - `commonui.userInfo.setAll({...})` 携带本页全部用户资料（键为 uid）；
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

  final pageInfo = _extractPageInfo(html);
  final floors = _extractFloors(html, page: page, perPage: pageInfo?.$2);
  if (floors.isEmpty) return null;

  final perPage = pageInfo?.$2 ?? floors.length;
  final maxPage = pageInfo?.$1 ?? page;
  final rows = maxPage * perPage;

  final fid = int.tryParse(
    RegExp(r"__CURRENT_FID=parseInt\('(\d+)'\)").firstMatch(html)?.group(1) ??
        '',
  );

  final firstUid = floors.first.uid;
  final firstUser = firstUid == null ? null : rawUsers['$firstUid'];
  final topic = Topic.fromJson({
    "tid": tid,
    "fid": fid,
    "subject": envelope["htmlTitle"]?.toString() ?? '',
    "author": firstUser is Map ? firstUser["username"]?.toString() ?? '' : '',
    "authorid": firstUid,
    "postdate": floors.first.postDateTimestamp,
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
      commentList: const [],
      attachmentList: const [],
    );
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
    hotReplies: const [],
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

  const _HtmlFloor({
    required this.indexKey,
    required this.lou,
    this.pid,
    this.uid,
    this.subject = '',
    this.content,
    this.postDate,
    this.postDateTimestamp,
  });
}

/// 按楼层行标记 `id='post1strow{N}'` 切块，每块内再提取各字段。
///
/// 时间戳取自楼层内联 JS 参数（形如 `,'15403840',1794564555,`）。
/// [perPage] 来自 `__PAGE`，用于换算跨页楼号；缺失时按本页楼层数兜底。
List<_HtmlFloor> _extractFloors(
  String html, {
  required int page,
  int? perPage,
}) {
  final rowMarks = RegExp(r"id='post1strow(\d+)'").allMatches(html).toList();
  final louPerPage = perPage ?? rowMarks.length;
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
    final content = RegExp(
      "id='postcontent$n'[^>]*>([\\s\\S]*?)(?:</span>|</p>)",
    ).firstMatch(chunk)?.group(1);
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
        // 楼层行编号每页从 0 重新计，全局楼号 = 前面页的行数 + 本页编号
        lou: (page - 1) * (louPerPage <= 0 ? 1 : louPerPage) + n,
        pid: pid,
        uid: uid,
        subject: subject,
        content: content,
        postDate: postDate,
        postDateTimestamp: postDateTimestamp,
      ),
    );
  }
  return floors;
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
