import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/repository/topic_repository.dart';
import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_nga/providers/topic/topic_single_page_provider.dart';

TopicDetailData _detail() {
  return TopicDetailData(
    userList: const {},
    replyList: const {},
    groupList: const {},
    medalList: const {},
    reputationList: const {},
    rows: 20,
    currentRows: 20,
    replyPageRows: 20,
    topic: Topic(tid: 1, subject: '缓存兜底帖'),
    hotReplies: const [],
  );
}

/// 刷新永远失败、缓存可配置的假仓库。
class _FailingRepository implements TopicRepository {
  _FailingRepository({required this.cached});

  final ({TopicDetailData data, int fetchedAt})? cached;
  int cacheReads = 0;

  @override
  Future<TopicDetailData> getTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    throw const FormatException('NGA 服务端返回的数据不完整');
  }

  @override
  Future<({TopicDetailData data, int fetchedAt})?> getCachedTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    cacheReads++;
    return cached;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _key = TopicSinglePageKey(tid: 1, page: 1);

void main() {
  test('刷新失败但有缓存：展示缓存内容并标记 cachedAt', () async {
    final repo = _FailingRepository(
      cached: (data: _detail(), fetchedAt: 1795347363000),
    );
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final state = await container
        .read(topicSinglePageProvider(_key).notifier)
        .refresh();

    expect(state.cachedAt, 1795347363000, reason: '界面要靠它显示缓存提示条');
    expect(state.truncated, isFalse);
    expect(state.topic?.subject, '缓存兜底帖');
    expect(state.replyList, isEmpty, reason: '缓存里的楼层原样展示');
    // 只读一次：首屏直出那次查库的 future 被失败兜底复用，不再重复查。
    expect(repo.cacheReads, 1, reason: '首屏缓存读与网络并行，失败兜底复用同一个 future');
  });

  test('刷新失败且无缓存：错误继续抛给界面（首次加载没有内容可兜底）', () async {
    final repo = _FailingRepository(cached: null);
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(topicSinglePageProvider(_key).notifier).refresh(),
      throwsA(isA<FormatException>()),
    );
    // 同上：首屏直出那次查库的结果被兜底路径复用，只读一次。
    expect(repo.cacheReads, 1, reason: '失败后复用首屏缓存读，不重复查库');
  });

  test('首屏缓存直出：缓存与网络都可用时，先把缓存铺上再被实时数据替换', () async {
    final repo = _SwrRepository(
      cached: (data: _detail(), fetchedAt: 1795347363000),
    );
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(topicSinglePageProvider(_key).notifier);
    final future = notifier.refresh();

    // 网络还没回来时，缓存已经把内容铺上了（缓存同步返回，网络 5ms）。
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(
      container.read(topicSinglePageProvider(_key)).cachedAt,
      1795347363000,
      reason: '网络返回前就应该有内容可看',
    );

    final state = await future;
    expect(state.cachedAt, isNull, reason: '实时数据回来后横幅要消失');
    expect(state.topic?.subject, '实时帖');
  });

  test('已 hydrate 过再刷新：不会用旧缓存盖住刚拿到的实时数据', () async {
    final repo = _SwrRepository(
      cached: (data: _detail(), fetchedAt: 1795347363000),
    );
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(topicSinglePageProvider(_key).notifier);
    await notifier.refresh();
    expect(repo.cacheReads, 1, reason: '只有首次进入才读缓存打底');

    // 第二次刷新：缓存里的楼层非空，但不能再被当成展示内容。
    await notifier.refresh();
    expect(repo.cacheReads, 1, reason: 'hydrate 只做一次');
    expect(container.read(topicSinglePageProvider(_key)).cachedAt, isNull);
  });

  test('缓存读抛异常：不影响网络请求，当作没有缓存', () async {
    // 回归护栏：缓存读曾经被挪出 try 块，同步抛出的异常会让 refresh()
    // 在发出网络请求前就崩掉（整页错误，而网络本来好好的）。
    final repo = _ThrowingCacheRepository();
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final state = await container
        .read(topicSinglePageProvider(_key).notifier)
        .refresh();

    expect(repo.networkCalls, 1, reason: '缓存读失败也必须照常请求网络');
    expect(state.cachedAt, isNull);
    expect(state.topic?.subject, '实时帖');
  });

  test('缓存读与网络请求并行：网络不等磁盘读完才发出', () async {
    final repo = _SwrRepository(
      cached: (data: _detail(), fetchedAt: 1795347363000),
      cacheDelay: const Duration(milliseconds: 200),
    );
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    unawaited(container.read(topicSinglePageProvider(_key).notifier).refresh());
    // 缓存读故意慢 200ms：若网络请求要等它，这个时间点就还不会发出。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.networkCalls, 1, reason: '网络请求必须立刻发出，不能排在磁盘读之后');
  });
}

/// 缓存读直接抛异常的仓库（模拟 sembast 打不开、参数校验失败等）。
class _ThrowingCacheRepository implements TopicRepository {
  int networkCalls = 0;

  @override
  Future<({TopicDetailData data, int fetchedAt})?> getCachedTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    throw StateError('sembast 打不开');
  }

  @override
  Future<TopicDetailData> getTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    networkCalls++;
    return TopicDetailData(
      userList: const {},
      replyList: const {},
      groupList: const {},
      medalList: const {},
      reputationList: const {},
      rows: 20,
      currentRows: 20,
      replyPageRows: 20,
      topic: Topic(tid: tid, subject: '实时帖'),
      hotReplies: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 缓存与网络都成功的仓库：网络返回的标题与缓存不同，便于区分。
///
/// 网络那一路固定慢于缓存 5ms，测试才能稳定观察到「缓存已铺、网络未回」
/// 的中间态（并行化后两者都在同一条事件循环上，只靠 `Duration.zero`
/// 无法保证顺序）。
class _SwrRepository implements TopicRepository {
  _SwrRepository({required this.cached, this.cacheDelay = Duration.zero});

  final ({TopicDetailData data, int fetchedAt})? cached;

  /// 缓存读的模拟耗时，用于验证「网络请求不等磁盘读」
  final Duration cacheDelay;

  int cacheReads = 0;
  int networkCalls = 0;

  @override
  Future<TopicDetailData> getTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    networkCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return TopicDetailData(
      userList: const {},
      replyList: const {},
      groupList: const {},
      medalList: const {},
      reputationList: const {},
      rows: 40,
      currentRows: 20,
      replyPageRows: 20,
      topic: Topic(tid: 1, subject: '实时帖'),
      hotReplies: const [],
    );
  }

  @override
  Future<({TopicDetailData data, int fetchedAt})?> getCachedTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    cacheReads++;
    if (cacheDelay > Duration.zero) {
      await Future<void>.delayed(cacheDelay);
    }
    return cached;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
