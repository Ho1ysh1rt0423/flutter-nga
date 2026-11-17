import 'dart:async';

import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 列表缩略图的兜底数据源。
///
/// 背景：服务端只在部分版块给 `thread.php` 列表下发 `attachs`（小窗视界、
/// 原神有；剑斗绮谭这类没有），所以对「标了带附件（type & 8192）但列表没给图」
/// 的帖子，单独请求主楼取附件图：`read.php?__output=8&tid=X&pid=0`，实测约 3KB，
/// 最多取 3 张（对齐 NGA 原版的列表配图）。
///
/// 三个约束：
/// - **串行**：一屏可能十几条带附件帖子，同时打出去太像爬虫，宁可慢一点；
/// - **只问一次**：结果（包括失败）都记住，列表滚来滚去不会重复请求；
/// - **尽量少发**：成功取到的图 URL 会经 [persist] 落盘，重启后从
///   [loadPersisted] 回灌内存，杀进程也不再重新拉。
class TopicHeadThumbnailQueue {
  TopicHeadThumbnailQueue(
    this._read, {
    this.loadPersisted,
    this.persist,
  });

  final Future<List<String>> Function(int tid) _read;

  /// 启动时从持久层读回的历史结果（tid → 图 URL 列表）
  final Future<Map<int, List<String>>> Function()? loadPersisted;

  /// 成功取到图后的落盘回调
  final Future<void> Function(int tid, List<String> urls)? persist;

  /// tid → 图 URL 列表；空列表表示「主楼没图」或「请求失败」，都不再重试
  final Map<int, List<String>> _cache = {};

  /// tid → 还在排队/进行中的请求。
  ///
  /// 列表滚动时同一个帖子会被反复 rebuild，而 `FutureProvider.family` 出屏后
  /// 可能被 dispose 再重建。只靠 [_cache] 去重不够（结果还没回来时缓存是空的），
  /// 实测会对同一个 tid 连发 5 次请求。这里用 pending 表把在途请求也合并掉。
  final Map<int, Future<List<String>>> _pending = {};

  /// 串行队列的尾巴
  Future<void> _tail = Future<void>.value();

  /// 启动时从持久层回灌缓存（只记一次，失败当作没有持久数据）
  Future<void>? _preloadFuture;

  Future<List<String>> fetch(int tid) {
    final cached = _cache[tid];
    if (cached != null) return Future.value(cached);
    final pending = _pending[tid];
    if (pending != null) return pending;

    final completer = Completer<List<String>>();
    _pending[tid] = completer.future;
    _tail = _tail.then((_) async {
      var urls = const <String>[];
      try {
        // 持久层回灌可能在入队之后才完成：执行前再看一眼缓存，
        // 命中就省掉这次 HTTP。
        await _ensureLoaded();
        final cachedUrls = _cache[tid];
        if (cachedUrls != null && cachedUrls.isNotEmpty) {
          if (!completer.isCompleted) completer.complete(cachedUrls);
          return;
        }
        urls = await _read(tid);
      } catch (_) {
        // 缩略图是锦上添花：失败就静默不显示，绝不把错误抛到列表里
        urls = const <String>[];
      }
      _cache[tid] = urls;
      _pending.remove(tid);
      if (urls.isNotEmpty) persist?.call(tid, urls).catchError((_) {});
      if (!completer.isCompleted) completer.complete(urls);
    });
    return completer.future;
  }

  Future<void> _ensureLoaded() {
    final existing = loadPersisted;
    if (existing == null) return Future<void>.value();
    return _preloadFuture ??= existing()
        .then<void>((map) {
          for (final entry in map.entries) {
            // 已有内存结果（包括「没图」的负结果）不覆盖
            if (!_cache.containsKey(entry.key)) {
              _cache[entry.key] = entry.value;
            }
          }
        })
        .catchError((_) {
          // 持久层坏了不影响主流程，当作没有持久数据
        });
  }

  /// 清空内存缓存（切换账号 / 测试用）。持久层里的 URL 是公开图片地址，
  /// 与账号无关，不做清理。
  void clear() {
    _cache.clear();
  }
}

final topicHeadThumbnailQueueProvider = Provider<TopicHeadThumbnailQueue>((ref) {
  // Riverpod 3 默认 autoDispose：列表滚出屏这个 provider 就被销毁，队列里的
  // 缓存跟着丢，同一个 tid 会被反复请求（实测一次滚动发了 5 遍）。缩略图缓存
  // 本来就该是进程级的，这里显式保活。
  ref.keepAlive();
  final repository = ref.read(topicRepositoryProvider);
  return TopicHeadThumbnailQueue(
    repository.getTopicHeadImageUrls,
    loadPersisted: repository.loadHeadThumbnailCache,
    persist: repository.saveHeadThumbnail,
  );
});

/// 列表项配图（最多 3 张，横向排开）。返回空列表表示这条帖子主楼没有附图，
/// 界面不显示缩略图区。
final topicHeadThumbnailProvider = FutureProvider.family<List<String>, int>(
  (ref, tid) => ref.watch(topicHeadThumbnailQueueProvider).fetch(tid),
);
