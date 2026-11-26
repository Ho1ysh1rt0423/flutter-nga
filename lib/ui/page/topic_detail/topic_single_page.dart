import 'dart:async';

import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/providers/settings/blocklist_settings_provider.dart';
import 'package:flutter_nga/providers/topic/topic_detail_provider.dart';
import 'package:flutter_nga/providers/topic/topic_single_page_provider.dart';
import 'package:flutter_nga/ui/page/topic_detail/hot_replies_section.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_reply_item_widget.dart';
import 'package:flutter_nga/ui/widget/readable_width.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/hooks/easy_refresh_hooks.dart';
import 'package:flutter_nga/utils/parser/content_parser.dart';

class TopicSinglePage extends HookConsumerWidget {
  const TopicSinglePage({
    super.key,
    required this.tid,
    required this.page,
    this.authorid,
    this.onJumpToFloor,
  });

  final int tid;
  final int page;
  final int? authorid;

  /// 跳转原楼层回调，参数为楼层号（lou）
  final ValueChanged<int>? onJumpToFloor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshController = useEasyRefreshController();
    final replyWidgetCache = useRef(<String, Widget>{});
    final detailProviderKey = TopicDetailKey(tid: tid);
    final providerKey = TopicSinglePageKey(
      tid: tid,
      page: page,
      authorid: authorid,
    );
    final state = ref.watch(topicSinglePageProvider(providerKey));
    final blockFilter = ref.watch(blockFilterProvider);
    // 防重复刷新：EasyRefresh 自己的下拉有节流，但截断横幅的「重试」按钮
    // 直接调 onRefresh，连点会并发多个请求互相覆盖状态
    final refreshing = useRef(false);

    Future<IndicatorResult?> onRefresh({
      bool fromRetryButton = false,
      bool silent = false,
    }) async {
      if (refreshing.value) return null;
      refreshing.value = true;
      try {
        replyWidgetCache.value.clear();
        final notifier = ref.read(
          topicSinglePageProvider(providerKey).notifier,
        );
        final next = await notifier.refresh();
        if (!context.mounted) return null;

        ref
            .read(topicDetailProvider(detailProviderKey).notifier)
            .updateMetadata(
              maxPage: next.maxPage,
              maxFloor: next.maxFloor,
              topic: next.topic,
            );
        refreshController.finishRefresh();
        // 服务端截断是源站坏对象：短时间内重试/下拉拿到的都是同一份坏数据
        // （实测换参数也一样），只有等它几分钟自愈。重试后仍截断时明确告知，
        // 别让用户以为多刷几次有用。
        if (fromRetryButton && next.truncated) {
          AppToast.info('服务端仍未恢复，建议过几分钟再试');
        }
        return null;
      } catch (err) {
        if (!context.mounted) return null;

        refreshController.finishRefresh(IndicatorResult.fail);
        // 静默刷新（重进帖子时的后台 revalidate）失败了不打扰用户：
        // 旧内容已经可读，缓存提示条也还在。
        if (!silent) AppToast.error(err);
        return IndicatorResult.fail;
      } finally {
        refreshing.value = false;
      }
    }

    // 重进已看过的帖子：provider 不是 autoDispose，state 还在，于是
    // `refreshOnStart` 为 false、`updateMetadata` 从未被调用 —— 而外层
    // topicDetailProvider 是 autoDispose，页面关闭后重建时 maxPage 回 1，
    // 结果就是底部页码永远停在「1/1」，只能手动下拉才恢复。
    //
    // 两步修：先把已有 state 的元数据补报上去（页码立刻正确、零请求），
    // 再静默 revalidate 一次（不转圈不弹错），让新回复能刷出来。
    usePostFrameEffect(() {
      if (state.replyList.isEmpty) return;
      // 直接用本次 build 里 watch 到的 state —— 不必、也不能去读 notifier.state
      // （那是受保护成员，仅限 subclass / 测试使用）。
      ref
          .read(topicDetailProvider(detailProviderKey).notifier)
          .updateMetadata(
            maxPage: state.maxPage,
            maxFloor: state.maxFloor,
            topic: state.topic,
          );
      unawaited(onRefresh(silent: true));
    });

    // 详情页把整块 TabBarView 的触摸斜率提到了 kPageFlipTouchSlop（翻页
    // 防误触）；列表的竖向滚动不该被波及，这里恢复默认斜率 —— 竞技场里
    // 列表层次更深、斜率更小，斜滑优先滚动而不是翻页。
    //
    // 「Reply to」引用的同页正文缓存按 state 记忆：原先在 itemBuilder 里
    // 每个楼层都算一遍全页摘要（每层都要跑一次正则剥 quote），20 楼的帖子
    // 就是 400 次解析，打开正文时明显拖慢首帧。
    final quoteBodyByPid = useMemoized(() => _quoteBodyCacheFor(state), [
      state.replyList,
      state.hotReplyList,
    ]);
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(gestureSettings: DeviceGestureSettings(touchSlop: null)),
      child: EasyRefresh(
        controller: refreshController,
        refreshOnStart: state.replyList.isEmpty,
        onRefresh: () => onRefresh(),
        child: Column(
          children: [
            if (state.truncated) _buildTruncatedBanner(context, onRefresh),
            if (state.cachedAt != null) _buildCachedBanner(context, state),
            Expanded(
              // 大屏下楼层列表收窄居中；截断横幅仍在全宽顶部
              child: ReadableListPadding(
                builder: (context, padding) => ListView.builder(
                  padding: padding,
                  itemCount: state.replyList.length,
                  itemBuilder: (context, position) => _buildListItem(
                    context,
                    position,
                    state,
                    blockFilter,
                    replyWidgetCache.value,
                    quoteBodyByPid,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 截断抢救的数据不是完整内容：顶部明确提示，避免用户以为帖子就这几楼。
  Widget _buildTruncatedBanner(
    BuildContext context,
    Future<IndicatorResult?> Function({bool fromRetryButton}) onRefresh,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer.withValues(alpha: 0.35),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  // 强调「服务端故障、需等待」，避免用户反复下拉以为马上能刷出来。
                  // 实测故障可持续 1 小时以上（2026-11-19 签到活动帖），
                  // 别写「几分钟」误导预期；重试无效 = 源站还没恢复
                  '服务端返回的数据不完整（NGA 服务端故障，需等待源站自行恢复）；'
                  '当前仅显示已加载的楼层',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => onRefresh(fromRetryButton: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 刷新失败但本地有缓存：展示缓存内容并明确告知「这不是实时数据」。
  /// 对齐官方 App 的本地缓存兜底——它「看起来稳」的另一半就是刷新失败时
  /// 旧内容继续可读、错误不顶到脸上。
  Widget _buildCachedBanner(BuildContext context, TopicSinglePageState state) {
    final colorScheme = Theme.of(context).colorScheme;
    final age = DateTime.now().millisecondsSinceEpoch - state.cachedAt!;
    final String ago;
    if (age < const Duration(hours: 1).inMilliseconds) {
      ago = '${age ~/ const Duration(minutes: 1).inMilliseconds + 1} 分钟';
    } else if (age < const Duration(days: 1).inMilliseconds) {
      ago = '${age ~/ const Duration(hours: 1).inMilliseconds + 1} 小时';
    } else {
      ago = '${age ~/ const Duration(days: 1).inMilliseconds + 1} 天';
    }
    return Material(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '服务端暂时没有响应，正在显示 $ago 前的缓存内容，下拉可重试',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    int position,
    TopicSinglePageState state,
    BlockFilter blockFilter,
    Map<String, Widget> replyWidgetCache,
    Map<int, String> quoteBodyByPid,
  ) {
    final reply = state.replyList[position];
    // 热点回复是精选区块，被屏蔽的直接移除而不是按屏蔽模式展示
    final hotReplies = position == 0 && page == 1
        ? state.hotReplyList
              .where(
                (hot) =>
                    blockFilter.replyMode(
                      hot,
                      username: _findUser(state, hot.authorId)?.username,
                    ) ==
                    null,
              )
              .toList()
        : const <Reply>[];
    if (hotReplies.isNotEmpty) {
      // 楼主下方展示热点回复区块
      return Column(
        children: [
          _buildReplyWidget(
            context,
            reply,
            state,
            blockFilter,
            quoteBodyByPid,
            replyWidgetCache,
          ),
          HotRepliesSection(
            replies: hotReplies,
            userList: state.userList,
            onJumpToFloor: onJumpToFloor,
            quoteBodyByPid: quoteBodyByPid,
          ),
        ],
      );
    } else {
      return _buildReplyWidget(
        context,
        reply,
        state,
        blockFilter,
        quoteBodyByPid,
        replyWidgetCache,
      );
    }
  }

  /// 同页（含热评）楼层正文缓存，Reply to 补原文
  Map<int, String> _quoteBodyCacheFor(TopicSinglePageState state) {
    return NgaContentParser.buildQuoteBodyCache([
      ...state.replyList.map((r) => (pid: r.pid, content: r.content)),
      ...state.hotReplyList.map((r) => (pid: r.pid, content: r.content)),
    ]);
  }

  Widget _buildReplyWidget(
    BuildContext context,
    Reply reply,
    TopicSinglePageState state,
    BlockFilter blockFilter,
    Map<int, String> quoteBodyByPid,
    Map<String, Widget> replyWidgetCache,
  ) {
    final user = _findUser(state, reply.authorId) ?? User();
    // 评论占位楼层（无正文、标题为系统文案）按 pid 找回真实评论
    Reply? commentSource;
    if (reply.content.isEmpty && (reply.subject ?? '').contains('发表了一条评论')) {
      commentSource = _findCommentByPid(state, reply.pid);
    }
    final blockMode =
        blockFilter.replyMode(reply, username: user.username) ??
        (commentSource == null
            ? null
            : blockFilter.replyMode(commentSource, username: user.username));

    final commentBlockModes = [
      for (final comment in reply.commentList)
        blockFilter.replyMode(
          comment,
          username: _findUser(state, comment.authorId)?.username,
        ),
    ];

    // 楼层与评论的屏蔽模式参与缓存 key，屏蔽设置变化后重新构建楼层
    final blockKey = [
      blockMode,
      ...commentBlockModes,
    ].map((mode) => mode?.index ?? '-').join();
    final uniqueId = "${reply.pid}_${reply.tid}_${reply.fid}_$blockKey";
    var cached = replyWidgetCache[uniqueId];
    if (cached != null) {
      return cached;
    } else {
      Group? group;
      if (user.memberId != null) {
        for (var g in state.groupSet) {
          if (g.id == user.memberId) {
            group = g;
            break;
          }
        }
      }

      List<Medal> medalList = [];
      if (user.medal != null && user.medal!.isNotEmpty) {
        user.medal!.split(",").forEach((id) {
          for (var m in state.medalSet) {
            if (id == m.id.toString()) {
              medalList.add(m);
              break;
            }
          }
        });
      }

      List<User> commentUserList = [];
      if (reply.commentList.isNotEmpty) {
        for (var comment in reply.commentList) {
          for (var user in state.userList) {
            if (user.uid == comment.authorId) {
              commentUserList.add(user);
              break;
            }
          }
        }
      }

      cached = TopicReplyItemWidget(
        reply: reply,
        user: user,
        group: group,
        medalList: medalList,
        userList: commentUserList,
        quoteBodyByPid: quoteBodyByPid,
        commentSource: commentSource,
        blockMode: blockMode,
        commentBlockModes: commentBlockModes,
        isTopicAuthor: _isTopicAuthor(state, reply),
      );
      replyWidgetCache[uniqueId] = cached;
      return cached;
    }
  }

  /// 楼主 uid 取自帖子信息；匿名帖的 authorid 可能是字符串，统一按字符串比较。
  bool _isTopicAuthor(TopicSinglePageState state, Reply reply) {
    final topicAuthor = state.topic?.authorId?.toString() ?? '';
    if (topicAuthor.isEmpty || topicAuthor == '0') return false;
    return topicAuthor == reply.authorId?.toString();
  }

  User? _findUser(TopicSinglePageState state, int? uid) {
    for (final user in state.userList) {
      if (user.uid == uid) return user;
    }
    return null;
  }

  /// 在本页所有楼层的评论列表中按 pid 查找真实评论
  Reply? _findCommentByPid(TopicSinglePageState state, int? pid) {
    if (pid == null) return null;
    for (final reply in state.replyList) {
      for (final comment in reply.commentList) {
        if (comment.pid == pid) return comment;
      }
    }
    return null;
  }
}
