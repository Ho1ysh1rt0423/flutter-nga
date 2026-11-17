import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/utils/route.dart';

/// 打开图片预览页（支持双指缩放 / 拖动）。
///
/// `screenWidth` 用于预览页计算初始缩放：图片比屏幕宽时按屏幕宽度铺满，
/// 否则保持 1:1。缺它会退化成 0 倍缩放，页面只剩转圈，所以这里统一在
/// 跳转时带上当前窗口宽度。
Future<void> openPhotoPreview(BuildContext context, String? url) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty) return Future.value();

  final screenWidth = MediaQuery.sizeOf(context).width;
  return Routes.navigateToWithParams(
    context,
    Routes.PHOTO_PREVIEW,
    {
      'url': trimmed,
      'screenWidth': screenWidth.toStringAsFixed(2),
    },
  );
}