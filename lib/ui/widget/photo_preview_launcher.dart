import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/utils/route.dart';

/// 打开图片预览页（支持双指缩放 / 拖动 / 图组左右切换）。
///
/// [urls] / [initialIndex] 给多图场景用：贴内一组图片打开时可左右滑动切换。
/// 单图调用只传 [url] 即可。
///
/// `screenWidth` 保留在跳转参数里供预览页布局参考。
Future<void> openPhotoPreview(
  BuildContext context,
  String? url, {
  List<String>? urls,
  int initialIndex = 0,
}) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty) return Future.value();

  return Routes.openPhotoPreview(
    context,
    trimmed,
    urls: urls,
    initialIndex: initialIndex,
  );
}
