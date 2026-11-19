import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_reply_item_widget.dart';

/// 楼层号与评论徽标被并入「级别/威望/发帖」的 meta 行（本 fork 定制）。
///
/// 上游 #38 把整块 meta 行包进 `if (headerStats.isNotEmpty)`：统计全空时整行
/// 不渲染。楼层号必须留在该 Wrap 内部 —— 一旦上游再改这块结构，本测试会先红，
/// 提醒「楼层号不能跟着统计一起消失」。
Future<void> _pump(
  WidgetTester tester, {
  required User user,
  Group? group,
  int? commentSourcePid,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.teal),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TopicReplyItemWidget(
              reply: Reply(
                content: '回复内容',
                tid: 1,
                pid: 2,
                lou: 7,
                authorId: 123,
                postDate: '2026-07-26 12:00',
                commentList: [],
                attachmentList: [],
              ),
              user: user,
              group: group,
              medalList: const [],
              commentSource: commentSourcePid == null
                  ? null
                  : Reply(
                      content: '原帖内容',
                      tid: 1,
                      pid: commentSourcePid,
                      lou: 1,
                      authorId: 123,
                      postDate: '2026-07-26 11:00',
                      commentList: [],
                      attachmentList: [],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('楼层号在统计数据缺失时仍然显示', (tester) async {
    // User 只有 uid/username：级别、威望、发帖与勋章全空，meta 行只剩楼层号。
    await _pump(tester, user: User(uid: 123, username: '测试用户'));

    expect(find.text('[7 楼]'), findsOneWidget);
    expect(find.textContaining('级别'), findsNothing);
    expect(find.textContaining('威望'), findsNothing);
    expect(find.textContaining('发帖'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('楼层号与统计同行显示', (tester) async {
    await _pump(
      tester,
      user: User(uid: 123, username: '测试用户', rvrc: 25, postNum: 8),
      group: const Group(1, '学徒'),
    );

    expect(find.text('级别: 学徒'), findsOneWidget);
    expect(find.text('[7 楼]'), findsOneWidget);

    // 同一 Wrap 内：楼层号与统计的纵向中心一致（证明没被拆回独立行）。
    final floorNumber = tester.getCenter(find.text('[7 楼]'));
    final stats = tester.getCenter(find.text('级别: 学徒'));
    expect((floorNumber.dy - stats.dy).abs(), lessThan(2));
  });

  testWidgets('评论楼层显示随行的评论徽标', (tester) async {
    await _pump(
      tester,
      user: User(uid: 123, username: '测试用户'),
      commentSourcePid: 99,
    );

    expect(find.text('[7 楼]'), findsOneWidget);
    expect(find.text('评论'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
