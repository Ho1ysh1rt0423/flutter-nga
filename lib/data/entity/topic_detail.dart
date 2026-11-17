import 'dart:core';

import 'package:flutter_nga/data/core/nga_domains.dart';
import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/utils/json_cast.dart';

class TopicDetailData {
  final Map<String, Reply> replyList;
  final Map<String, User> userList;

  final Map<String, Group> groupList;
  final Map<String, Medal> medalList;
  final Map<String, Reputation> reputationList;

  final dynamic global;
  final int rows;
  final int currentRows;
  final int replyPageRows;

  /// 响应被服务端截断、经「补闭合」抢救出来的部分数据。此时 [rows] /
  /// [replyPageRows] 等总览字段不可信（截断点常在它们之前），[maxPage]
  /// 会回退为 1，界面必须提示「内容不完整」。
  final bool truncated;

  /// 主题信息（`__T`）。NGA 的响应里 `__T` 排在楼层 `__R` 之后，截断抢救
  /// 的数据经常只有楼层没有它 —— 此时为 null，界面标题回落到路由参数，
  /// 热评列表为空。
  final Topic? topic;
  final List<int> hotReplies;

  const TopicDetailData({
    this.global,
    this.truncated = false,
    required this.userList,
    required this.replyList,
    required this.groupList,
    required this.medalList,
    required this.reputationList,
    required this.rows,
    required this.currentRows,
    required this.replyPageRows,
    this.topic,
    required this.hotReplies,
  });

  factory TopicDetailData.fromJson(
    Map<String, dynamic> map, {
    bool truncated = false,
  }) {
    // 抢救数据按「保留到截断点前最后一个完整对象」裁剪，__U / __T / 总览
    // 字段都可能缺失（__T 排在 __R 之后，缺得最勤），全部容错为空。
    final userMap = asJsonMapOrNull(map["__U"], 'TopicDetailData.__U') ?? {};
    final replyMap = asJsonMapOrNull(map["__R"], 'TopicDetailData.__R') ?? {};
    final topicInfoMap =
        asJsonMapOrNull(map["__T"], 'TopicDetailData.__T') ?? {};
    Map<String, User> tempUserMap = {};
    Map<String, Group> tempGroupMap = {};
    Map<String, Medal> tempMedalMap = {};
    Map<String, Reputation> tempReputationMap = {};
    for (MapEntry<String, dynamic> entry in userMap.entries) {
      int? key = int.tryParse(entry.key);
      if (key == null) {
        // __GROUPS 用户等级
        if ("__GROUPS" == entry.key) {
          final groups = asJsonMap(entry.value, 'TopicDetailData.__U.__GROUPS');
          for (final m in groups.entries) {
            tempGroupMap[m.key] = Group.fromJson(
              asJsonMap(m.value, 'TopicDetailData.__U.__GROUPS.${m.key}'),
            );
          }
        } else if ("__MEDALS" == entry.key) {
          // __MEDALS 奖牌
          final medals = asJsonMap(entry.value, 'TopicDetailData.__U.__MEDALS');
          for (final m in medals.entries) {
            tempMedalMap[m.key] = Medal.fromJson(
              asJsonMap(m.value, 'TopicDetailData.__U.__MEDALS.${m.key}'),
            );
          }
        } else if ("__REPUTATIONS" == entry.key) {
          // __REPUTATIONS 威望
          final reputations = asJsonMap(
            entry.value,
            'TopicDetailData.__U.__REPUTATIONS',
          );
          for (final m in reputations.entries) {
            tempReputationMap[m.key] = Reputation.fromJson(
              asJsonMap(m.value, 'TopicDetailData.__U.__REPUTATIONS.${m.key}'),
            );
          }
        }
      } else {
        tempUserMap[entry.key] = User.fromJson(
          asJsonMap(entry.value, 'TopicDetailData.__U.${entry.key}'),
        );
        if (key != tempUserMap[entry.key]!.uid) {
          tempUserMap[entry.key]!.uid = key;
        }
      }
    }
    Map<String, Reply> tempReplyMap = {};
    for (MapEntry<String, dynamic> entry in replyMap.entries) {
      tempReplyMap[entry.key] = Reply.fromJson(
        asJsonMap(entry.value, 'TopicDetailData.__R.${entry.key}'),
      );
    }
    final topicMisc =
        asJsonMapOrNull(
          topicInfoMap["post_misc_var"],
          'TopicDetailData.__T.post_misc_var',
        ) ??
        {};
    List<int> hotReplies = [];
    if (topicMisc.containsKey("17")) {
      String hots = topicMisc["17"];
      hotReplies.addAll(
        hots
            .split(",")
            .where((e) => e.isNotEmpty)
            .map((e) => int.tryParse(e))
            .where((e) => e != null)
            .cast(),
      );
    }
    return TopicDetailData(
      global: map["__GLOBAL"],
      userList: tempUserMap,
      replyList: tempReplyMap,
      groupList: tempGroupMap,
      medalList: tempMedalMap,
      reputationList: tempReputationMap,
      currentRows: _asInt(map["__R__ROWS"]),
      replyPageRows: _asInt(map["__R__ROWS_PAGE"]),
      rows: _asInt(map["__ROWS"]),
      truncated: truncated,
      topic: topicInfoMap.isEmpty
          ? null
          : Topic.fromJson(topicInfoMap),
      hotReplies: hotReplies,
    );
  }

  /// 服务端字段类型不稳定（截断抢救后的数据常缺总览字段），统一兜成 0，
  /// 避免 null / 非法值直接把 `int` 字段赋值炸掉。
  static int _asInt(dynamic value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  int get maxPage {
    // 截断抢救的数据缺 `__ROWS` / `__R__ROWS_PAGE`（截断点常落在它们之前），
    // 算出来的页数不可信；总览字段缺失（0）时同样无页可算，都回退为当前页。
    if (truncated || replyPageRows <= 0 || rows <= 0) return 1;
    return (rows / replyPageRows.toDouble()).ceil();
  }
}

class Reply {
  String content;
  String? alterInfo;
  int? tid;
  int score;
  int? score2;
  String? postDate;
  int? authorId;
  String? subject;
  int? type;
  int? fid;
  int? pid;
  int? recommend;
  int? lou;
  int? contentLength;
  int? postDateTimestamp;
  List<Reply> commentList;
  List<Attachment> attachmentList;

  Reply({
    required this.content,
    this.alterInfo,
    this.tid,
    this.score = 0,
    this.score2,
    this.postDate,
    this.authorId,
    this.subject,
    this.type,
    this.fid,
    this.pid,
    this.recommend,
    this.lou,
    this.contentLength,
    this.postDateTimestamp,
    required this.commentList,
    required this.attachmentList,
  });

  factory Reply.fromJson(Map<String, dynamic> map) {
    dynamic commentData = map["comment"];
    List<Reply> commentList = [];
    if (commentData is Map) {
      final comments = asJsonMap(commentData, 'Reply.comment');
      comments.forEach(
        (k, v) =>
            commentList.add(Reply.fromJson(asJsonMap(v, 'Reply.comment.$k'))),
      );
    }
    dynamic attachmentData = map["attachs"];
    List<Attachment> attachmentList = [];
    if (attachmentData is Map) {
      final attachments = asJsonMap(attachmentData, 'Reply.attachs');
      attachments.forEach(
        (k, v) => attachmentList.add(
          Attachment.fromJson(asJsonMap(v, 'Reply.attachs.$k')),
        ),
      );
    }
    return Reply(
      content: map["content"] == null ? "" : map["content"].toString(),
      // 这都可能会是 int 我也是服气
      alterInfo: map["alterinfo"],
      tid: map["tid"],
      score: map["score"] ?? 0,
      score2: map["score_2"],
      postDate: map["postdate"],
      authorId: map["authorid"],
      subject: map["subject"] == null ? "" : map["subject"].toString(),
      type: map["type"],
      fid: map["fid"],
      pid: map["pid"],
      recommend: map["recommend"],
      lou: map["lou"],
      // 实际上无用属性，还可能是字符串，干脆不要了
      //      contentLength: int.tryParse(map["content_length"]) ?? 0,
      postDateTimestamp: map["postdatetimestamp"],
      commentList: commentList,
      attachmentList: attachmentList,
    );
  }

  String get quoteContent {
    var c = content;
    if (c.length > 250) {
      c = c.substring(0, 250);
    }
    return c;
  }

  void merge(Reply comment) {
    content = comment.content;
    alterInfo = comment.alterInfo;
    tid = comment.tid;
    score = comment.score;
    score2 = comment.score2;
    type = comment.type;
    fid = comment.fid;
    recommend = comment.recommend;
    contentLength = comment.contentLength;
    postDateTimestamp = comment.postDateTimestamp;
    commentList = comment.commentList;
  }
}

class Group {
  final int? id;
  final String? name;

  const Group(this.id, this.name);

  factory Group.fromJson(Map<String, dynamic> map) {
    return Group(map["2"], map["0"]);
  }
}

class Medal {
  final int? id;
  final String? name;
  final String? description;
  final String? image;

  const Medal(this.id, this.name, this.description, this.image);

  factory Medal.fromJson(Map<String, dynamic> map) {
    return Medal(map["3"], map["1"], map["2"], map["0"]);
  }
}

class Reputation {
  const Reputation();

  factory Reputation.fromJson(Map<String, dynamic> map) {
    return Reputation();
  }
}

class Attachment {
  const Attachment({
    this.attachUrl,
    this.size,
    this.type,
    this.urlUtf8OrgName,
    this.dscp,
    this.path,
    this.name,
    this.ext,
    this.thumb,
  });

  factory Attachment.fromJson(Map<String, dynamic> map) {
    return Attachment(
      attachUrl: map['attachurl'],
      size: map['size'],
      type: map['type'],
      urlUtf8OrgName: map['url_utf8_org_name'],
      dscp: map['dscp'],
      path: map['path'],
      name: map['name'],
      ext: map['ext'],
      thumb: map['thumb'],
    );
  }

  final String? attachUrl;
  final int? size;
  final String? type;
  final String? urlUtf8OrgName;
  final String? dscp;
  final String? path;
  final String? name;
  final String? ext;
  final dynamic thumb;

  String get realUrl => "$ngaAttachmentBase/$attachUrl";
}
