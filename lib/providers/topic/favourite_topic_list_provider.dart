import 'package:flutter/foundation.dart';
import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FavouriteTopicListState {
  final int size;
  final int page;
  final int maxPage;
  final bool enablePullUp;
  final List<Topic> list;
  final bool isLoading;

  const FavouriteTopicListState({
    this.size = 35,
    this.page = 1,
    this.maxPage = 1,
    this.enablePullUp = false,
    this.list = const [],
    this.isLoading = false,
  });

  FavouriteTopicListState copyWith({
    int? size,
    int? page,
    int? maxPage,
    bool? enablePullUp,
    List<Topic>? list,
    bool? isLoading,
  }) {
    return FavouriteTopicListState(
      size: size ?? this.size,
      page: page ?? this.page,
      maxPage: maxPage ?? this.maxPage,
      enablePullUp: enablePullUp ?? this.enablePullUp,
      list: list ?? this.list,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  factory FavouriteTopicListState.initial() => const FavouriteTopicListState();
}

/// 已从列表移除、等待提交到服务端的收藏删除
class _PendingDeletion {
  const _PendingDeletion(this.topic, this.index);

  final Topic topic;

  /// 移除前在列表中的位置，撤销或提交失败时按原位插回
  final int index;
}

class FavouriteTopicListNotifier extends Notifier<FavouriteTopicListState> {
  /// tid → 待提交的删除。删除先只改本地列表，撤销窗口结束后再调接口，
  /// 这样撤销能真正恢复原状（重新收藏会改变排序和所在收藏夹）。
  final _pending = <int, _PendingDeletion>{};

  /// 已发出、尚未返回的删除请求。刷新前必须等它们完成，否则服务端还没删掉，
  /// 刷新结果会把条目带回来，之后删除成功也不会再移除。
  final _inFlight = <Future<void>>{};

  /// 本地已删除、尚未确认「服务端也删掉了」的 tid → 提交时间（null = 未提交）。
  ///
  /// 刷新/翻页的取数与删除并发时，取回的是删除前的快照，直接整表覆盖会让
  /// 已删条目复活。组装新列表时按这里过滤；提交时间早于取数开始的条目由
  /// 服务端确认已删（或用户重新收藏后服务端重新返回），从集合清理放行。
  final _hiddenTids = <int, DateTime?>{};

  @override
  FavouriteTopicListState build() => FavouriteTopicListState.initial();

  bool get hasPendingDeletion => _pending.isNotEmpty;

  /// 先从本地列表移除，等待 [commitDeletion] 或 [undoDeletion]。
  void removeLocally(Topic topic) {
    final tid = topic.tid;
    if (tid == null) return;
    final index = state.list.indexWhere((t) => t.tid == tid);
    if (index < 0) return;
    _pending[tid] = _PendingDeletion(topic, index);
    _hiddenTids[tid] = null;
    state = state.copyWith(list: [...state.list]..removeAt(index));
  }

  /// 撤销删除：按原位置插回。
  void undoDeletion(int tid) {
    final pending = _pending.remove(tid);
    if (pending != null) {
      _hiddenTids.remove(tid);
      _restore(pending);
    }
  }

  /// 提交删除到服务端；失败时插回列表并抛出错误。已提交或已撤销时返回 null。
  Future<String?> commitDeletion(int tid) async {
    final pending = _pending.remove(tid);
    if (pending == null) return null;
    // page 用移除时条目自带的收藏列表页码，与网页版删除参数一致。
    final request = ref
        .read(topicRepositoryProvider)
        .deleteFavouriteTopic(tid, pending.topic.page);
    final tracked = request.then<void>((_) {}, onError: (_) {});
    _inFlight.add(tracked);
    try {
      final message = await request;
      _hiddenTids[tid] = DateTime.now();
      return message;
    } catch (err) {
      if (ref.mounted) {
        _restore(pending);
        _hiddenTids.remove(tid);
      }
      rethrow;
    } finally {
      _inFlight.remove(tracked);
    }
  }

  /// 提交全部待删条目，并等待已在进行中的删除请求结束；
  /// 返回本次提交的第一个错误（全部成功为 null）。
  Future<Object?> commitAllDeletions() async {
    Object? firstError;
    for (final tid in [..._pending.keys]) {
      try {
        await commitDeletion(tid);
      } catch (err) {
        firstError ??= err;
      }
    }
    await Future.wait([..._inFlight]);
    return firstError;
  }

  void _restore(_PendingDeletion pending) {
    if (state.list.any((t) => t.tid == pending.topic.tid)) return;
    final index = pending.index.clamp(0, state.list.length);
    state = state.copyWith(list: [...state.list]..insert(index, pending.topic));
  }

  /// 刷新 / 翻页前先提交待删条目，否则服务端数据会把它们带回来；
  /// 提交失败的条目会随刷新结果重新出现。
  Future<void> _flushBeforeLoading() async {
    final err = await commitAllDeletions();
    if (err != null) debugPrint('提交收藏删除失败: $err');
  }

  /// 清理「提交不晚于本次取数开始」的隐藏 tid：服务端已确认删除（取回的
  /// 数据里不会再有；若因重新收藏重新返回，也会在本过滤放行后自然清理）。
  /// 用「不晚于」而非「早于」：测试与极快操作里两个时间戳可能同毫秒。
  void _pruneConfirmedGone(DateTime fetchStartedAt) {
    _hiddenTids.removeWhere(
      (tid, committedAt) =>
          committedAt != null && !committedAt.isAfter(fetchStartedAt),
    );
  }

  Future<FavouriteTopicListState> refresh() async {
    await _flushBeforeLoading();
    state = state.copyWith(isLoading: true);
    final fetchStartedAt = DateTime.now();
    try {
      TopicListData data = await ref
          .read(topicRepositoryProvider)
          .getFavouriteTopicList(1);
      // 取数期间用户仍可删条目：先提交并等在途请求结束，再按隐藏集过滤
      // 删除前的快照，已删条目不复活。
      await _flushBeforeLoading();
      _pruneConfirmedGone(fetchStartedAt);
      state = FavouriteTopicListState(
        size: data.topicRows,
        page: 1,
        maxPage: data.maxPage,
        enablePullUp: 1 < data.maxPage,
        list: data.topicList.values
            .where((t) => !_hiddenTids.containsKey(t.tid))
            .toList(),
        isLoading: false,
      );
      return state;
    } catch (err) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<FavouriteTopicListState> loadMore() async {
    if (state.isLoading) return state;
    await _flushBeforeLoading();
    state = state.copyWith(isLoading: true);
    final fetchStartedAt = DateTime.now();
    try {
      TopicListData data = await ref
          .read(topicRepositoryProvider)
          .getFavouriteTopicList(state.page + 1);
      await _flushBeforeLoading();
      _pruneConfirmedGone(fetchStartedAt);
      final loadedTids = {for (final t in state.list) t.tid};
      state = FavouriteTopicListState(
        size: data.topicRows,
        page: state.page + 1,
        maxPage: data.maxPage,
        enablePullUp: state.page + 1 < data.maxPage,
        // 删除后服务端分页前移，下一页可能与已加载内容重叠：
        // 按 tid 去重，且用户已删（含取数期间删的）条目不放回。
        list: [
          ...state.list,
          ...data.topicList.values.where(
            (t) =>
                !loadedTids.contains(t.tid) && !_hiddenTids.containsKey(t.tid),
          ),
        ],
        isLoading: false,
      );
      return state;
    } catch (err) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }
}

final favouriteTopicListProvider =
    NotifierProvider<FavouriteTopicListNotifier, FavouriteTopicListState>(
      FavouriteTopicListNotifier.new,
    );
