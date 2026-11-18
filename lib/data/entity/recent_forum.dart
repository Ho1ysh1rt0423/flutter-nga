import 'package:flutter_nga/data/entity/forum.dart';

/// 最近访问过的版块。
///
/// 和浏览历史（`TopicHistory`）不同，这里只记版块，用于首页「最近访问」
/// 快捷入口，让首页不再只有收藏宫格。数据量小、无账号维度，存在
/// SharedPreferences（见 `PrefsKeys.visitedForums`），不占用 Sembast。
class RecentForum {
  const RecentForum({required this.forum, required this.visitedAt});

  final Forum forum;

  /// 最近一次访问的时间戳（毫秒），排序与去重都按它走。
  final int visitedAt;

  ForumIdentity get identity => forum.identity;

  Map<String, dynamic> toJson() {
    return {
      ...forum.toJson(),
      'fid': forum.fid,
      'name': forum.name,
      'type': forum.type,
      'visitedAt': visitedAt,
    };
  }

  /// 防御性解析：设置可能被旧版本/手工改写，缺字段或类型不对直接返回 null，
  /// 由调用方跳过这一条，而不是让整个列表解析失败。
  factory RecentForum.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid recent forum.');
    final fid = _asInt(value['fid']);
    final name = value['name']?.toString();
    if (fid == null || name == null || name.isEmpty) {
      throw const FormatException('Invalid recent forum identity.');
    }
    return RecentForum(
      forum: Forum(
        fid,
        name,
        type: _asInt(value['type']) ?? 0,
        iconId: _asInt(value['iconId']),
      ),
      visitedAt: _asInt(value['visitedAt']) ?? 0,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
