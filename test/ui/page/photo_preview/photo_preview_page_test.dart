import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/ui/page/photo_preview/photo_preview_page.dart';
import 'package:flutter_nga/ui/widget/photo_gallery_scope.dart';

Widget _wrap(Widget child) {
  return UncontrolledProviderScope(
    container: ProviderContainer(),
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('单图：标题不带页码', (tester) async {
    await tester.pumpWidget(
      _wrap(const PhotoPreviewPage(url: 'https://img.nga.cn/a.jpg')),
    );
    await tester.pump();
    expect(find.text('查看图片'), findsOneWidget);
    expect(find.textContaining('查看图片 1/'), findsNothing);
  });

  testWidgets('图组：标题显示当前位置', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PhotoPreviewPage(
          urls: [
            'https://img.nga.cn/a.jpg',
            'https://img.nga.cn/b.jpg',
            'https://img.nga.cn/c.jpg',
          ],
          initialIndex: 1,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('查看图片 2/3'), findsOneWidget);
  });

  testWidgets('空地址给出提示而不是崩溃', (tester) async {
    await tester.pumpWidget(_wrap(const PhotoPreviewPage(url: '')));
    await tester.pump();
    expect(find.text('图片地址为空'), findsOneWidget);
  });

  test('PhotoGalleryScope.updateShouldNotify 只比较内容', () {
    const urls = ['a', 'b'];
    final same = PhotoGalleryScope(urls: urls, child: const SizedBox());
    final sameOther = PhotoGalleryScope(
      urls: ['a', 'b'],
      child: const SizedBox(),
    );
    final different = PhotoGalleryScope(
      urls: ['a', 'c'],
      child: const SizedBox(),
    );
    // 同一实例引用：不通知
    expect(same.updateShouldNotify(same), isFalse);
    // 内容相同（不同 List 实例）：不通知
    expect(same.updateShouldNotify(sameOther), isFalse);
    // 内容变化：通知
    expect(same.updateShouldNotify(different), isTrue);
  });
}
