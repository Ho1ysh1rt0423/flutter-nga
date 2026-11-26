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

  /// 本页数据来自本地缓存（刷新失败时的 stale-while-revalidate 兜底），
  /// 值为缓存写入时间戳；null = 服务端实时数据。界面据此显示「缓存内容」
  /// 提示条，与 [truncated] 的横幅互斥出现。
  final int? cachedAt;
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
    this.cachedAt,
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
    int? cachedAt,
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
      cachedAt: cachedAt ?? this.cachedAt,
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

  /// 本次会话内是否已经把本地缓存铺到 state 上过。
  ///
  /// 只在「首次进入且 state 为空」时用缓存打底（首屏缓存直出），之后的下拉
  /// 刷新、重试按钮都必须走网络，否则旧缓存会盖住刚拿到的实时数据。
  bool _hydrated = false;

  @override
  TopicSinglePageState build() => TopicSinglePageState.initial();

  Future<TopicSinglePageState> refresh() async {
    final generation = ++_generation;
    final repository = ref.read(topicRepositoryProvider);

    // 首屏缓存直出：先把上次成功响应的内容铺上，用户立刻有东西看，网络
    // 请求随后在后台跑；成功回来会整体替换（cachedAt 归空、横幅消失）。
    //
    // 必须放在 refresh() 内部而不是 widget 层：详情页靠 EasyRefresh 的
    // `refreshOnStart: state.replyList.isEmpty` 触发首刷，widget 层预填会让
    // 这个判断永远为 false，首刷直接被跳过。
    //
    // ★ 缓存读与网络请求**并行**：sembast 读 + fromJson 是磁盘 + JSON 解析
    // 开销（冷启动几十毫秒量级），先 await 它再发请求等于把这段白加在首字
    // 延迟上。这里只把「是否首屏」判断出来，缓存读扔进 future 不等，网络
    // 请求立刻发出；缓存回来时若网络还没回来就把内容铺上。
    Future<({TopicDetailData data, int fetchedAt})?>? hydrating;
    if (!_hydrated && state.replyList.isEmpty) {
      _hydrated = true;
      hydrating = _hydrateCache(repository, generation);
    }

    try {
      final data = await repository.getTopicDetail(
        key.tid,
        key.page,
        key.authorid,
      );
      _applyData(data, generation: generation, cachedAt: null);
      return state;
    } catch (err) {
      // 刷新失败：有缓存就展示缓存（stale-while-revalidate，对齐官方 App
      // 的本地缓存兜底）。无缓存的首次加载没有内容可兜底，错误继续抛给
      // 界面显示错误页。
      try {
        // 首屏那次缓存读可能还在路上，直接复用，不再重复查库
        final cached =
            await (hydrating ??
                repository.getCachedTopicDetail(
                  key.tid,
                  key.page,
                  key.authorid,
                ));
        if (cached != null) {
          _applyData(
            cached.data,
            generation: generation,
            cachedAt: cached.fetchedAt,
          );
          return state;
        }
      } catch (_) {
        // 缓存读取失败：抛出原始错误
      }
      rethrow;
    }
  }

  void _applyData(
    TopicDetailData data, {
    required int generation,
    required int? cachedAt,
  }) {
    final repository = ref.read(topicRepositoryProvider);

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
      cachedAt: cachedAt,
      topic: data.topic,
      replyList: replyList,
      userList: userList,
      groupSet: groups,
      medalSet: medals,
    );

    if (key.page == 1 && key.authorid == null) {
      if (data.hotReplyList.isNotEmpty) {
        // 同一份响应里已内联带下热评正文（`__R.0.hotreply`）——直接落地，
        // 不发任何 pid 请求。这就是打开帖子少 1~4 次网络往返的来源。
        state = state.copyWith(hotReplyList: data.hotReplyList);
      } else if (cachedAt == null && data.hotReplies.isNotEmpty) {
        // 老路：响应只有 pid 列表（o17 回退 / 老数据），逐 pid 拉正文。
        //
        // cachedAt != null 时跳过：首屏缓存直出（功能 13）会立刻触发这条，
        // 让「先出缓存再后台更新」反而多打 N 个请求且全是后台噪音。
        // 缓存里也没有内联热评（TopicDetailCache 存的是原始 o8 响应，若当时
        // 有 hotreply 也已一并解析），所以缓存态的 pid 请求是没有收益的。
        unawaited(
          _loadHotReplies(repository, data.hotReplies, generation: generation),
        );
      }
    }
  }

  /// 读本地缓存并把内容铺到 state 上（首屏直出）。
  ///
  /// **任何失败都当作没有缓存**：缓存只是锦上添花，读失败不能让首屏刷新
  /// 整体崩掉。注意这里必须用 try/catch 而不是 `.catchError` —— 仓库实现
  /// 可能在**同步阶段**就抛（例如假仓库的 noSuchMethod、真实实现里的参数
  /// 校验），那种异常挂在 then/catchError 链之前就跑出来了。
  Future<({TopicDetailData data, int fetchedAt})?> _hydrateCache(
    TopicRepository repository,
    int generation,
  ) async {
    try {
      final cached = await repository.getCachedTopicDetail(
        key.tid,
        key.page,
        key.authorid,
      );
      if (cached == null) return null;
      // 网络结果先到就别再铺缓存（会在实时数据上闪一下旧内容）
      if (generation != _generation || state.replyList.isNotEmpty) {
        return cached;
      }
      _applyData(
        cached.data,
        generation: generation,
        cachedAt: cached.fetchedAt,
      );
      return cached;
    } catch (_) {
      return null;
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
