import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/repository/topic_repository.dart';
import 'package:flutter_nga/providers/core/repository_providers.dart';
import 'package:flutter_nga/providers/topic/topic_single_page_provider.dart';

TopicDetailData _detail({
  List<int> hotReplies = const [],
  Map<String, Reply> replies = const {},
}) {
  return TopicDetailData(
    userList: const {},
    replyList: replies,
    groupList: const {},
    medalList: const {},
    reputationList: const {},
    rows: 20,
    currentRows: 20,
    replyPageRows: 20,
    topic: Topic(tid: 1, subject: '测试帖'),
    hotReplies: hotReplies,
  );
}

Reply _reply(String content, {int? pid}) => Reply(
  content: content,
  pid: pid,
  commentList: const [],
  attachmentList: const [],
);

class _FakeTopicRepository implements TopicRepository {
  _FakeTopicRepository({required this.hotGate});

  /// 热评请求的可控闸门：模拟服务端截断时漫长的重试等待。
  final Completer<TopicDetailData> hotGate;
  int detailCalls = 0;
  int hotCalls = 0;

  @override
  Future<TopicDetailData> getTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    detailCalls++;
    return _detail(hotReplies: detailCalls == 1 ? const [101] : const []);
  }

  @override
  Future<TopicDetailData> getTopicReplies(int? pid) {
    hotCalls++;
    return hotGate.future;
  }

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test(
    'main posts render before hot replies resolve; late hot results are merged',
    () async {
      final hotGate = Completer<TopicDetailData>();
      final repo = _FakeTopicRepository(hotGate: hotGate);
      final container = ProviderContainer(
        overrides: [topicRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      const key = TopicSinglePageKey(tid: 1, page: 1);
      final provider = topicSinglePageProvider(key);
      final notifier = container.read(provider.notifier);

      // 首屏请求返回；此时热评请求仍卡在 hotGate 上。
      final first = await notifier.refresh();
      expect(first.replyList, isEmpty);
      expect(first.hotReplyList, isEmpty);
      expect(repo.hotCalls, 1, reason: '热评请求要发出去，但不能阻塞首屏');

      // 热评回来后异步并入。
      hotGate.complete(_detail(replies: {'1': _reply('热评内容', pid: 101)}));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(container.read(provider).hotReplyList.map((e) => e.content), [
        '热评内容',
      ]);
    },
  );

  test('a stale hot-reply result does not overwrite a newer refresh', () async {
    final hotGate = Completer<TopicDetailData>();
    final repo = _FakeTopicRepository(hotGate: hotGate);
    final container = ProviderContainer(
      overrides: [topicRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    const key = TopicSinglePageKey(tid: 1, page: 1);
    final provider = topicSinglePageProvider(key);
    final notifier = container.read(provider.notifier);

    // 第一次刷新：主楼落地、热评卡住。
    await notifier.refresh();
    // 第二次刷新：新主楼落地（generation 递增），这次没有热评。
    await notifier.refresh();

    // 旧的热评请求现在才回来 —— 必须被丢弃，不能盖到新页上。
    hotGate.complete(_detail(replies: {'1': _reply('过期的热评', pid: 101)}));
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final state = container.read(provider);
    expect(state.hotReplyList, isEmpty, reason: '上一轮的慢热评不能盖到新页');
  });
}
