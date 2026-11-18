import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/ui/widget/nga_html_extensions.dart';
import 'package:flutter_nga/utils/theme_builder.dart';

final _theme = ThemeBuilder.buildLightTheme(Colors.brown);

/// 选出给定文本所在 RichText 的 selectionRegistrar。
///
/// fwfh 只有在祖先存在选择注册器时才给 RichText 挂 selectionRegistrar；
/// 没有它就是「长按没反应」，有它长按才会出现系统的选择手柄/复制菜单。
RichText? _richTextFor(WidgetTester tester, String text) {
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    var found = false;
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if ((span.text ?? '').contains(text)) found = true;
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }

    visit(richText.text);
    if (found) return richText;
  }
  return null;
}

void main() {
  testWidgets('selectable:false renders plain text without a selection area', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(body: NgaHtml('不可选的正文')),
      ),
    );

    expect(find.byType(SelectionArea), findsNothing);
    final richText = _richTextFor(tester, '不可选的正文');
    expect(richText, isNotNull);
    expect(richText!.selectionRegistrar, isNull, reason: '没有注册器时长按不会选中');
  });

  testWidgets('selectable:true enables long-press text selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        home: Scaffold(body: NgaHtml('长按可以选中的正文', selectable: true)),
      ),
    );

    expect(find.byType(SelectionArea), findsOneWidget);
    final richText = _richTextFor(tester, '长按可以选中的正文');
    expect(richText, isNotNull);
    expect(richText!.selectionRegistrar, isNotNull, reason: '挂了注册器后长按才能选中并复制');
  });
}
