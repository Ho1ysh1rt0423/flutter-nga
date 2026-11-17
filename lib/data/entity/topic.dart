import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/data/entity/child_forum.dart';
import 'package:flutter_nga/data/entity/topic_history.dart';
import 'package:flutter_nga/utils/constant.dart';
import 'package:flutter_nga/utils/json_cast.dart';

class TopicListData {
  const TopicListData({
    this.global,
    required this.forum,
    required this.rows,
    required this.topicList,
    required this.currentRows,
    required this.topicRows,
    required this.rRows,
  });

  final dynamic global;
  final ForumInfo forum;
  final int? rows;
  final Map<String, Topic> topicList;
  final int currentRows;
  final int topicRows;
  final int rRows;

  factory TopicListData.fromJson(Map<String, dynamic> map, int? page) {
    final topicMap = asJsonMap(map["__T"], 'TopicListData.__T');
    Map<String, Topic> tempMap = {};
    for (MapEntry<String, dynamic> entry in topicMap.entries) {
      final topicJson = asJsonMap(
        entry.value,
        'TopicListData.__T.${entry.key}',
      );
      topicJson["page"] = page;
      tempMap[entry.key] = Topic.fromJson(topicJson);
    }
    return TopicListData(
      global: map["__GLOBAL"],
      forum: ForumInfo.fromJson(asJsonMap(map["__F"], 'TopicListData.__F')),
      rows: map["__ROWS"] != "" ? map["__ROWS"] : null,
      topicList: tempMap,
      currentRows: map["__T__ROWS"],
      topicRows: map["__T__ROWS_PAGE"],
      rRows: map["__R__ROWS_PAGE"],
    );
  }

  int get maxPage => rows! ~/ rRows + (rows! % rRows != 0 ? 1 : 0);
}

class Topic {
  const Topic({
    this.tid,
    this.fid,
    this.tpcurl,
    this.quoteFrom,
    this.quoteTo,
    this.author,
    this.subject,
    this.icon,
    this.postDate,
    this.lastPoster,
    this.lastPost,
    this.lastModify,
    this.recommend,
    this.authorId,
    this.type,
    this.replies,
    this.topicMisc,
    this.page,
    this.parent,
    this.attachmentUrls = const [],
  });

  final int? tid;
  final int? fid;
  final String? tpcurl;
  final dynamic quoteFrom;
  final String? quoteTo;
  final String? author;
  final dynamic authorId; // 匿名时为 String，非匿名时为 Int
  final String? subject;
  final int? icon;
  final int? postDate;
  final dynamic lastPoster; // 也可能匿名
  final int? lastPost;
  final int? lastModify;
  final int? recommend;
  final int? type;
  final int? replies;
  final String? topicMisc;
  final int? page; // 用于记录是收藏的第几页

  /// 列表接口随帖子返回的附件图（NGA 在部分版块会带 `attachs` 字段，
  /// 每项形如 `{"0": {"attachurl": "mon_202611/17/xxx.jpg"}}`）。
  /// 已规范化成完整的 https 地址，最多保留 [maxListAttachmentCount] 张。
  final List<String> attachmentUrls;

  /// 列表最多展示的配图数量，对齐 NGA 原版
  static const int maxListAttachmentCount = 3;

  final TopicParent? parent;

  factory Topic.fromJson(Map<String, dynamic> map) {
    return Topic(
      tid: map["tid"],
      fid: map["fid"],
      tpcurl: map["tpcurl"],
      quoteFrom: map["quote_from"],
      quoteTo: map["quote_to"].toString(),
      // 有一些不正常数据是 int 类型
      author: map["author"].toString(),
      // 写 PHP 的都没有一点数据类型的意识么？
      authorId: map["authorid"],
      subject: map["subject"].toString(),
      icon: map["icon"],
      postDate: map["postdate"],
      lastPoster: map["lastposter"],
      lastPost: map["lastpost"],
      lastModify: map["lastmodify"],
      recommend: map["recommend"],
      type: map["type"],
      replies: map["replies"],
      topicMisc: map["topic_misc"],
      page: map["page"],
      parent: TopicParent.parse(map["parent"]),
      attachmentUrls: parseListAttachmentUrls(map["attachs"]),
    );
  }

  /// 解析列表接口的 `attachs`：只取图片类附件，规范化成完整地址。
  ///
  /// 服务端并非所有版块都下发该字段，缺失或结构异常时返回空列表。
  static List<String> parseListAttachmentUrls(dynamic value) {
    if (value is! Map) return const [];
    final urls = <String>[];
    for (final entry in value.entries) {
      final item = entry.value;
      if (item is! Map) continue;
      final type = item["type"]?.toString();
      if (type != null && type.isNotEmpty && type != "img") continue;
      final url = normalizeListAttachmentUrl(item["attachurl"]?.toString());
      if (url == null) continue;
      urls.add(url);
      if (urls.length >= maxListAttachmentCount) break;
    }
    return urls;
  }

  /// 附件相对路径 → 完整 URL。与正文解析（content_parser）保持同一套规则。
  static String? normalizeListAttachmentUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('http://')) {
      return value.replaceFirst('http://', 'https://');
    }
    if (value.startsWith('https://')) return value;
    if (value.startsWith('./mon_')) {
      return '$_attachmentBase${value.substring(1)}';
    }
    if (value.startsWith('mon_')) return '$_attachmentBase/$value';
    if (value.startsWith('/attachments/')) return 'https://img.nga.cn$value';
    if (value.startsWith('/')) return value;
    return '$_attachmentBase/$value';
  }

  static const String _attachmentBase = 'https://img.nga.cn/attachments';

  bool hasAttachment() {
    return type! & TOPIC_MASK_TYPE_ATTACHMENT == TOPIC_MASK_TYPE_ATTACHMENT;
  }

  bool isAssemble() {
    return type! & TOPIC_MASK_TYPE_ASSEMBLE == TOPIC_MASK_TYPE_ASSEMBLE;
  }

  bool locked() {
    return type! & TOPIC_MASK_TYPE_LOCK == TOPIC_MASK_TYPE_LOCK;
  }

  bool isBold() {
    return _getLastMiscByte() & TOPIC_MASK_FONT_STYLE_BOLD ==
        TOPIC_MASK_FONT_STYLE_BOLD;
  }

  bool isItalic() {
    return _getLastMiscByte() & TOPIC_MASK_FONT_STYLE_ITALIC ==
        TOPIC_MASK_FONT_STYLE_ITALIC;
  }

  bool isUnderline() {
    return _getLastMiscByte() & TOPIC_MASK_FONT_STYLE_UNDERLINE ==
        TOPIC_MASK_FONT_STYLE_UNDERLINE;
  }

  Color? getSubjectColor() {
    var byte = _getLastMiscByte();
    if (byte & TOPIC_MASK_FONT_COLOR_RED == TOPIC_MASK_FONT_COLOR_RED) {
      return Colors.red;
    } else if (byte & TOPIC_MASK_FONT_COLOR_BLUE ==
        TOPIC_MASK_FONT_COLOR_BLUE) {
      return Colors.blue;
    } else if (byte & TOPIC_MASK_FONT_COLOR_GREEN ==
        TOPIC_MASK_FONT_COLOR_GREEN) {
      return Colors.green;
    } else if (byte & TOPIC_MASK_FONT_COLOR_ORANGE ==
        TOPIC_MASK_FONT_COLOR_ORANGE) {
      return Colors.orange;
    } else if (byte & TOPIC_MASK_FONT_COLOR_SILVER ==
        TOPIC_MASK_FONT_COLOR_SILVER) {
      return Color(0xFFC0C0C0);
    } else {
      return null;
    }
  }

  int _getLastMiscByte() {
    if (topicMisc != null && topicMisc!.isNotEmpty) {
      var misc = topicMisc!;
      while (misc.length * 6 % 8 != 0) {
        misc += "A";
      }
      var bytes = base64.decode(misc);
      if (bytes.isNotEmpty && bytes[0].toInt() == 1) {
        return bytes[4].toInt();
      }
    }
    return 0;
  }

  /// 点击时生成浏览历史
  TopicHistory createHistory() {
    return TopicHistory(
      tid: tid!,
      fid: fid!,
      subject: subject!,
      author: author,
      type: type,
      topicMisc: topicMisc,
      topicParentName: parent?.name,
      time: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class TopicParent {
  const TopicParent(this.name);

  final String? name;

  factory TopicParent.fromJson(Map<String, dynamic> map) {
    return TopicParent(map["2"]);
  }

  /// NGA 的 parent 可能是 `{"2": "名称"}`，也可能是空字符串或名称本身。
  static TopicParent? parse(dynamic value) {
    if (value == null || value == '') return null;
    if (value is String) return TopicParent(value);
    if (value is Map) {
      return TopicParent.fromJson(asJsonMap(value, 'Topic.parent'));
    }
    logJsonTypeMismatch('Topic.parent', value);
    return null;
  }
}

class ForumInfo {
  const ForumInfo({this.topForumId, this.fid, this.subForums});

  final int? topForumId;
  final int? fid;
  final List<ChildForum>? subForums;

  factory ForumInfo.fromJson(Map map) {
    List<ChildForum> subForums = [];
    if (map['sub_forums'] != null && map['sub_forums'] is Map) {
      asJsonMap(map['sub_forums'], 'ForumInfo.sub_forums').forEach((k, v) {
        final forum = asJsonMap(v, 'ForumInfo.sub_forums.$k');
        dynamic selectedForum = map['__SELECTED_FORUM'];
        List<int> selectedIds = [];
        if (selectedForum is String) {
          if (selectedForum.isNotEmpty) {
            selectedIds.addAll(
              selectedForum.split(",").map((s) => int.parse(s)),
            );
          }
        }
        String? desc = forum['2'];
        int id = forum['0'];
        subForums.add(
          ChildForum(
            id,
            forum['1'],
            forum['3'],
            parentId: map['fid'],
            desc: desc != null && desc.isNotEmpty ? desc : null,
            type: k.startsWith("t") ? 1 : 0,
            selected: selectedIds.contains(id),
          ),
        );
      });
    }
    dynamic toppedTopic = map['topped_topic'];
    if (toppedTopic is! int && toppedTopic != "") {
      toppedTopic = int.tryParse(toppedTopic);
    } else {
      toppedTopic = null;
    }
    return ForumInfo(
      topForumId: toppedTopic,
      fid: map['fid'],
      subForums: subForums,
    );
  }
}

class TopicReply {
  final int tid;
  final int pid;
  final dynamic authorid;
  final int type;
  final dynamic postdate;
  final String subject;
  final String content;

  TopicReply(
    this.tid,
    this.pid,
    this.authorid,
    this.type,
    this.postdate,
    this.subject,
    this.content,
  );

  factory TopicReply.fromJson(Map<String, dynamic> map) {
    return TopicReply(
      map['tid'],
      map['pid'],
      map['authorid'],
      map['type'],
      map['postdate'],
      map['subject'],
      map['content'],
    );
  }
}
