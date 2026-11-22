import 'package:material_ui/material_ui.dart';

/// 图片预览上下文：让贴内图片知道「我属于哪个图组、我是第几张」。
///
/// 贴内一张帖子里的所有正文图片构成一个图组（`[album]` 相册单独成组——
/// 相册内图片连续排列），预览页据此支持左右滑动切换、显示「3/8」位置。
/// 见 [PhotoGalleryScope]、`openPhotoPreview` 与 `PhotoPreviewPage`。
class PhotoGalleryContext {
  const PhotoGalleryContext({required this.urls, required this.index});

  /// 图组内的原图地址（已规范化、去重，顺序即浏览顺序）
  final List<String> urls;

  /// 当前图片在 [urls] 中的下标；不在组内时按 0 处理
  final int index;
}

/// 把图组上下文传给子树里所有 `_NgaPreviewableImage`（InheritedWidget）。
///
/// 用 InheritedWidget 而不是给每张图显式传参，是为了让 `buildImage` 这类
/// 逐图回调无需知道整组图片——渲染层不知道整组信息，只在扫描阶段构建。
class PhotoGalleryScope extends InheritedWidget {
  const PhotoGalleryScope({
    super.key,
    required this.urls,
    required super.child,
  });

  /// 图组内全部图片地址
  final List<String> urls;

  /// 取最近的图组；没有则为 null
  static PhotoGalleryScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PhotoGalleryScope>();

  @override
  bool updateShouldNotify(PhotoGalleryScope oldWidget) {
    if (identical(urls, oldWidget.urls)) return false;
    if (urls.length != oldWidget.urls.length) return true;
    for (var i = 0; i < urls.length; i++) {
      if (urls[i] != oldWidget.urls[i]) return true;
    }
    return false;
  }
}
