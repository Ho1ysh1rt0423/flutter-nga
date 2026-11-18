import 'dart:async';
import 'dart:collection';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/data/repository/topic_repository.dart';
import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopicSinglePageState {
  final int page;
  final int maxPage;
  final int maxFloor;
  final bool enablePullUp;

  /// 本页数据来自「截断抢救」（服务端把响应在中途砍断，客户端保留了已写
  /// 完整的楼层）。此时页数/总楼数不可信（已回退为当前页），界面必须
  /// 明确提示内容不完整，用户刷新可尝试拿全量。
  final bool truncated;
  final Topic? topic;
  final List<Reply> replyList;
  final List<Reply> hotReplyList;
  final List<User> userList;
  final Set<Group> groupSet;
  final Set<Medal> medalSet;

  const TopicSinglePageState({
    this.page = 1,
    this.maxPage = 1,
    this.maxFloor = 1,
    this.enablePullUp = false,
    this.truncated = false,
    this.topic,
    this.replyList = const [],
    this.hotReplyList = const [],
    this.userList = const [],
    this.groupSet = const {},
    this.medalSet = const {},
  });

  factory TopicSinglePageState.initial() => TopicSinglePageState(
    page: 1,
    maxPage: 1,
    maxFloor: 1,
    enablePullUp: false,
    topic: null,
    replyList: [],
    hotReplyList: [],
    userList: [],
    groupSet: HashSet(),
    medalSet: HashSet(),
  );

  TopicSinglePageState copyWith({
    int? page,
    int? maxPage,
    int? maxFloor,
    bool? enablePullUp,
    bool? truncated,
    Topic? topic,
    List<Reply>? replyList,
    List<Reply>? hotReplyList,
    List<User>? userList,
    Set<Group>? groupSet,
    Set<Medal>? medalSet,
  }) {
    return TopicSinglePageState(
      page: page ?? this.page,
      maxPage: maxPage ?? this.maxPage,
      maxFloor: maxFloor ?? this.maxFloor,
      enablePullUp: enablePullUp ?? this.enablePullUp,
      truncated: truncated ?? this.truncated,
      topic: topic ?? this.topic,
      replyList: replyList ?? this.replyList,
      hotReplyList: hotReplyList ?? this.hotReplyList,
      userList: userList ?? this.userList,
      groupSet: groupSet ?? this.groupSet,
      medalSet: medalSet ?? this.medalSet,
    );
  }
}

/// Key for identifying a specific topic single page
class TopicSinglePageKey {
  final int tid;
  final int page;
  final int? authorid;

  const TopicSinglePageKey({
    required this.tid,
    required this.page,
    this.authorid,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopicSinglePageKey &&
          runtimeType == other.runtimeType &&
          tid == other.tid &&
          page == other.page &&
          authorid == other.authorid;

  @override
  int get hashCode => tid.hashCode ^ page.hashCode ^ authorid.hashCode;
}

class TopicSinglePageNotifier extends Notifier<TopicSinglePageState> {
  TopicSinglePageNotifier(this.key);
  final TopicSinglePageKey key;

  /// 每次 refresh 自增；热评异步回填时用它判断「这批复写是否还属于当前页」，
  /// 避免上一轮的慢请求把新一轮的楼层盖掉。
  int _generation = 0;

  @override
  TopicSinglePageState build() => TopicSinglePageState.initial();

  Future<TopicSinglePageState> refresh() async {
    final generation = ++_generation;
    try {
      final repository = ref.read(topicRepositoryProvider);
      final data = await repository.getTopicDetail(
        key.tid,
        key.page,
        key.authorid,
      );

      List<Reply> replyList = [];
      for (var reply in data.replyList.values) {
        replyList.add(reply);
      }

      List<User> userList = data.userList.values.toList();
      Set<Group> groups = data.groupList.values.toSet();
      Set<Medal> medals = data.medalList.values.toSet();

      // 正文先落地再取热评：热评是「精选区块」，每个 pid 一个请求，遇到
      // 服务端截断还要走 0.9s/2.5s 的重试等待，串在首屏前会把打开帖子的
      // 时间从一次请求拖成 N+1 次（用户看到的就是长时间转圈）。
      state = TopicSinglePageState(
        page: 1,
        // 截断抢救的数据页数/总楼数不可信（entity 的 maxPage 已回退为 1）。
        // 当前页至少是存在的（正在看的就是它），保底到当前页，避免
        // TabBarView 因页数缩水把用户正在看的页挤掉；总楼数用已解析出的
        // 最大楼层号顶上，界面上不至于显示 0。
        maxPage: data.truncated && key.page > data.maxPage
            ? key.page
            : data.maxPage,
        maxFloor: data.truncated
            ? replyList.fold<int>(
                0,
                (max, reply) => (reply.lou ?? 0) > max ? (reply.lou ?? 0) : max,
              )
            : data.rows,
        enablePullUp: 1 < data.maxPage,
        truncated: data.truncated,
        topic: data.topic,
        replyList: replyList,
        userList: userList,
        groupSet: groups,
        medalSet: medals,
      );

      if (key.page == 1 && data.hotReplies.isNotEmpty && key.authorid == null) {
        unawaited(
          _loadHotReplies(repository, data.hotReplies, generation: generation),
        );
      }
      return state;
    } catch (err) {
      rethrow;
    }
  }

  /// 后台拉热评，回来后把热评楼层与它们带来的用户/等级/勋章并进当前状态。
  ///
  /// 失败只降级为「没有热评区」，不影响已经渲染的正文。
  Future<void> _loadHotReplies(
    TopicRepository repository,
    List<int> pids, {
    required int generation,
  }) async {
    final List<TopicDetailData> hots;
    try {
      hots = await Future.wait(pids.map((e) => repository.getTopicReplies(e)));
    } catch (_) {
      return;
    }
    // 期间发生过刷新、页面已销毁，或用户已滑走：丢弃这批结果。
    if (generation != _generation || !ref.mounted) return;

    final current = state;
    final userList = [...current.userList];
    final groups = {...current.groupSet};
    final medals = {...current.medalSet};
    final hotReplyList = <Reply>[];
    for (final package in hots) {
      userList.addAll(package.userList.values);
      groups.addAll(package.groupList.values);
      medals.addAll(package.medalList.values);
      hotReplyList.addAll(package.replyList.values);
    }
    if (hotReplyList.isEmpty) return;

    state = current.copyWith(
      hotReplyList: hotReplyList,
      userList: userList,
      groupSet: groups,
      medalSet: medals,
    );
  }
}

final topicSinglePageProvider =
    NotifierProvider.family<
      TopicSinglePageNotifier,
      TopicSinglePageState,
      TopicSinglePageKey
    >(TopicSinglePageNotifier.new);
