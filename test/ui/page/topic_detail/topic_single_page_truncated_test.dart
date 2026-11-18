import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/providers/topic/topic_single_page_provider.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_single_page.dart';

/// refresh() 直接产出预制状态的 notifier，用来驱动界面的各个状态分支。
class _FixedTopicSinglePageNotifier extends TopicSinglePageNotifier {
  _FixedTopicSinglePageNotifier(super.key, this.fixedState);

  final TopicSinglePageState fixedState;

  @override
  Future<TopicSinglePageState> refresh() async {
    state = fixedState;
    return state;
  }
}

Future<void> _pumpPage(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: TopicSinglePage(tid: 2, page: 1)),
      ),
    ),
  );
  // refreshOnStart 是异步触发，多泵几拍等它跑完
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  const bannerText = '服务端返回的数据不完整，当前仅显示已加载的楼层';

  testWidgets('truncated page shows the incomplete-content banner', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        topicSinglePageProvider.overrideWith2(
          (key) => _FixedTopicSinglePageNotifier(
            key,
            TopicSinglePageState(
              maxPage: 1,
              maxFloor: 3,
              truncated: true,
              topic: const Topic(tid: 2, subject: '被截断的帖子'),
              replyList: [
                Reply(
                  content: '主楼内容',
                  subject: '被截断的帖子',
                  tid: 2,
                  pid: 1,
                  authorId: 10,
                  postDate: '2026-11-18 00:00',
                  commentList: [],
                  attachmentList: [],
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpPage(tester, container);

    final key = const TopicSinglePageKey(tid: 2, page: 1);
    // refreshOnStart 必须真的跑过：状态里已经有预制数据
    expect(
      container.read(topicSinglePageProvider(key)).truncated,
      isTrue,
      reason: 'refresh 没有被 EasyRefresh 触发',
    );
    expect(container.read(topicSinglePageProvider(key)).replyList, isNotEmpty);

    expect(find.textContaining(bannerText), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(
      find.textContaining('主楼内容', findRichText: true),
      findsOneWidget,
      reason: '抢救出的楼层仍要正常渲染',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: '横幅 + Column 包裹不能破坏 EasyRefresh 的布局',
    );

    // 卸载页面，避免 EasyRefresh 的定时器残留触发 pending-timer 断言
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full page renders without the banner', (tester) async {
    final container = ProviderContainer(
      overrides: [
        topicSinglePageProvider.overrideWith2(
          (key) => _FixedTopicSinglePageNotifier(
            key,
            TopicSinglePageState(
              maxPage: 5,
              maxFloor: 88,
              topic: const Topic(tid: 2, subject: '正常帖子'),
              replyList: [
                Reply(
                  content: '第一楼',
                  subject: '正常帖子',
                  tid: 2,
                  pid: 1,
                  authorId: 10,
                  postDate: '2026-11-18 00:00',
                  commentList: [],
                  attachmentList: [],
                ),
              ],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await _pumpPage(tester, container);

    final key = const TopicSinglePageKey(tid: 2, page: 1);
    expect(container.read(topicSinglePageProvider(key)).truncated, isFalse);

    expect(find.textContaining(bannerText), findsNothing);
    expect(find.textContaining('第一楼', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
