import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/entity/conversation.dart';
import 'package:flutter_nga/ui/page/conversation/conversation_item_widget.dart';

Conversation _conversation(int? lastModify) => Conversation(
  1,
  lastModify,
  0,
  '对话标题',
  100,
  1700000000,
  200,
  3,
  0,
  'alice',
  'bob',
);

Future<void> _pump(WidgetTester tester, Conversation conversation) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ConversationItemWidget(conversation: conversation)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('lastModify 缺失时不显示时间且不崩溃（原为空断言红屏）', (tester) async {
    await _pump(tester, _conversation(null));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('对话标题', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.access_time), findsNothing);
  });

  testWidgets('lastModify 正常时显示时间', (tester) async {
    await _pump(tester, _conversation(1700000000));

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.access_time), findsOneWidget);
  });
}
