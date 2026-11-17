import 'dart:async';

import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 列表缩略图的兜底数据源。
///
/// 背景：服务端只在部分版块给 `thread.php` 列表下发 `attachs`（小窗视界、
/// 原神有；剑斗绮谭这类没有），所以对「标了带附件（type & 8192）但列表没给图」
/// 的帖子，单独请求主楼取首图：`read.php?__output=8&tid=X&pid=0`，实测约 3KB。
///
/// 两个约束：
/// - **串行**：一屏可能十几条带附件帖子，同时打出去太像爬虫，宁可慢一点；
/// - **只问一次**：结果（包括失败）都记住，列表滚来滚去不会重复请求。
class TopicHeadThumbnailQueue {
  TopicHeadThumbnailQueue(this._read);

  final Future<List<String>> Function(int tid) _read;

  /// tid → 首图 URL；值为 null 表示「主楼没图」或「请求失败」，两者都不再重试
  final Map<int, String?> _cache = {};

  /// tid → 还在排队/进行中的请求。
  ///
  /// 列表滚动时同一个帖子会被反复 rebuild，而 `FutureProvider.family` 出屏后
  /// 可能被 dispose 再重建。只靠 [_cache] 去重不够（结果还没回来时缓存是空的），
  /// 实测会对同一个 tid 连发 5 次请求。这里用 pending 表把在途请求也合并掉。
  final Map<int, Future<String?>> _pending = {};

  /// 串行队列的尾巴
  Future<void> _tail = Future<void>.value();

  Future<String?> fetch(int tid) {
    if (_cache.containsKey(tid)) return Future.value(_cache[tid]);
    final pending = _pending[tid];
    if (pending != null) return pending;

    final completer = Completer<String?>();
    _pending[tid] = completer.future;
    _tail = _tail.then((_) async {
      String? url;
      try {
        final urls = await _read(tid);
        url = urls.isEmpty ? null : urls.first;
      } catch (_) {
        // 缩略图是锦上添花：失败就静默不显示，绝不把错误抛到列表里
        url = null;
      }
      _cache[tid] = url;
      _pending.remove(tid);
      if (!completer.isCompleted) completer.complete(url);
    });
    return completer.future;
  }

  /// 清空缓存（切换账号 / 测试用）
  void clear() {
    _cache.clear();
  }
}

final topicHeadThumbnailQueueProvider = Provider<TopicHeadThumbnailQueue>((ref) {
  // Riverpod 3 默认 autoDispose：列表滚出屏这个 provider 就被销毁，队列里的
  // 缓存跟着丢，同一个 tid 会被反复请求（实测一次滚动发了 5 遍）。缩略图缓存
  // 本来就该是进程级的，这里显式保活。
  ref.keepAlive();
  return TopicHeadThumbnailQueue(
    (tid) => ref.read(topicRepositoryProvider).getTopicHeadImageUrls(tid),
  );
});

/// 列表项首图。返回 null 表示这条帖子主楼没有附图，界面不显示缩略图区。
final topicHeadThumbnailProvider = FutureProvider.family<String?, int>(
  (ref, tid) => ref.watch(topicHeadThumbnailQueueProvider).fetch(tid),
);
