import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_nga/data/core/app_preferences.dart';
import 'package:flutter_nga/data/entity/forum.dart';
import 'package:flutter_nga/data/entity/recent_forum.dart';

/// 首页「最近访问」保留的条数。再多会把收藏宫格挤下去。
const int maxRecentForumCount = 8;

class RecentForumState {
  const RecentForumState({this.forums = const [], this.isLoaded = false});

  /// 最近访问的版块，最新的在前。
  final List<RecentForum> forums;
  final bool isLoaded;

  RecentForumState copyWith({List<RecentForum>? forums, bool? isLoaded}) {
    return RecentForumState(
      forums: forums ?? this.forums,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

/// 记录并读取「最近访问的版块」。
///
/// 写入路径刻意做成 fire-and-forget（[record] 不返回 Future）：打开版块页时
/// 只需要记一笔，不能因为读设置而拖慢页面跳转。
class RecentForumNotifier extends Notifier<RecentForumState> {
  bool _writeScheduled = false;

  @override
  RecentForumState build() {
    _load();
    return const RecentForumState();
  }

  Future<void> _load() async {
    try {
      final prefs = await AppPreferences.instance();
      final raw = prefs.getString(PrefsKeys.visitedForums);
      state = RecentForumState(forums: _decode(raw), isLoaded: true);
    } catch (_) {
      // 设置读取失败不该拖垮首页：退化为空列表即可。
      state = const RecentForumState(isLoaded: true);
    }
  }

  /// 解码持久化数据。单条解析失败只丢弃那一条：设置可能被旧版本或手工
  /// 改坏，不能因此让首页整块消失。
  static List<RecentForum> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final forums = <RecentForum>[];
    for (final entry in decoded) {
      try {
        forums.add(RecentForum.fromJson(entry));
      } catch (_) {
        continue;
      }
    }
    forums.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    return forums.take(maxRecentForumCount).toList();
  }

  /// 记一次访问。同一个版块只保留最新一条，超出上限的旧记录丢弃。
  void record(Forum forum) {
    final identity = forum.identity;
    final next = [
      RecentForum(
        forum: forum,
        visitedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      ...state.forums.where((item) => item.identity != identity),
    ].take(maxRecentForumCount).toList();
    state = state.copyWith(forums: next, isLoaded: true);
    _scheduleWrite(next);
  }

  /// 批量写盘时合并同一帧内的多次记录（连续点开几个版块不会连写多次）。
  void _scheduleWrite(List<RecentForum> forums) {
    if (_writeScheduled) return;
    _writeScheduled = true;
    Future.microtask(() async {
      _writeScheduled = false;
      try {
        final prefs = await AppPreferences.instance();
        await prefs.setString(
          PrefsKeys.visitedForums,
          jsonEncode(state.forums.map((item) => item.toJson()).toList()),
        );
      } catch (_) {
        // 写盘失败只丢这次记录，内存状态仍是最新的一次访问。
      }
    });
  }

  Future<void> remove(ForumIdentity identity) async {
    final next = state.forums
        .where((item) => item.identity != identity)
        .toList();
    state = state.copyWith(forums: next);
    final prefs = await AppPreferences.instance();
    await prefs.setString(
      PrefsKeys.visitedForums,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    state = const RecentForumState(isLoaded: true);
    final prefs = await AppPreferences.instance();
    await prefs.remove(PrefsKeys.visitedForums);
  }
}

final recentForumProvider =
    NotifierProvider<RecentForumNotifier, RecentForumState>(
      RecentForumNotifier.new,
    );
