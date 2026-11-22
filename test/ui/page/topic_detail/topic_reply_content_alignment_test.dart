import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_reply_item_widget.dart';
import 'package:flutter_nga/ui/widget/nga_html_content_widget.dart';

void main() {
  testWidgets('short floor content is left aligned', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TopicReplyItemWidget(
                  reply: Reply(
                    content: '短正文',
                    tid: 1,
                    pid: 2,
                    authorId: 123,
                    postDate: '2026-11-17 12:00',
                    commentList: [],
                    attachmentList: [],
                  ),
                  user: User(uid: 123, username: '测试用户'),
                  medalList: const [],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    // 2026-11-22 楼层卡片化：楼层包在 10dp 外边距 + 16dp 内边距的 M3 卡片里
    const cardMargin = 10.0;
    const floorPadding = 16.0;
    final content = tester.getRect(find.byType(NgaHtmlContentWidget));
    expect(content.left, cardMargin + floorPadding);
    expect(content.width, screenWidth - 2 * (cardMargin + floorPadding));
    final text = tester.getRect(
      find.textContaining('短正文', findRichText: true).first,
    );
    expect(text.left, cardMargin + floorPadding);
  });
}
