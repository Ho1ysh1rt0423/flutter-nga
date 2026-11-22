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
    expect(repo.cacheReads, 1);
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
    expect(repo.cacheReads, 1, reason: '失败后应先尝试缓存再放弃');
  });
}
