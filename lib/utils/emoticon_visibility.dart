import 'dart:typed_data';
import 'dart:ui' as ui;

/// 表情在深色主题下的可见性判定。
///
/// NGA 的 AC娘 / 新AC娘 / 外域三人组等表情是**纯黑线稿 + 透明背景**（实测
/// 不透明像素平均亮度 = 0），在深色主题下与背景融为一体，看起来就像"表情没
/// 加载出来"。这里通过分析像素识别出这类"深色透明线稿"，由渲染层在深色模式下
/// 把线条反相成白色，让它们融入暗色界面且不留白块。
///
/// 彩色表情（黄脸、潘斯特、企鹅等）自带颜色与底色，不满足判定条件，保持原样。
class EmoticonVisibility {
  EmoticonVisibility._();

  /// 低于该平均亮度（0-1）视为深色线稿。
  ///
  /// 实测：需要反相的 123 张图平均亮度均为 0.00；彩色表情最低也有 0.49
  /// （19.gif），0.35 的阈值有充足余量。
  static const double darkMeanLuminance = 0.35;

  /// 不透明像素占比超过该值视为"自带背景的整图"（如彩色圆脸），
  /// 即使偏暗也不反相 —— 反相会破坏它原本的底色。
  ///
  /// 实测：需要反相的图占比都在 0.28–0.44；彩色表情最低 0.75。
  static const double opaqueRatioThreshold = 0.92;

  /// alpha 低于该值的像素视为透明。
  static const int alphaThreshold = 40;

  /// 判断一张图是否为"深色透明线稿"，需要在深色主题下反相。
  ///
  /// [rgba] 为 `rawRgba` 格式（每像素 4 字节，顺序 R,G,B,A）。
  static bool needsInvertInDark(
    Uint8List rgba, {
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0) return false;
    final pixelCount = width * height;
    if (rgba.length < pixelCount * 4) return false;

    var opaque = 0;
    var luminanceSum = 0.0;
    for (var i = 0; i < pixelCount; i++) {
      final offset = i * 4;
      final alpha = rgba[offset + 3];
      if (alpha < alphaThreshold) continue;
      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];
      // Rec. 709 亮度，与 Color.computeLuminance 的权重一致
      luminanceSum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
      opaque++;
    }

    if (opaque == 0) return false;
    // 自带不透明底色的表情无需反相
    if (opaque / pixelCount >= opaqueRatioThreshold) return false;
    return luminanceSum / opaque < darkMeanLuminance;
  }

  /// 解码图片字节并判断是否需要反相；解码失败时返回 false。
  static Future<bool> needsInvertInDarkForBytes(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return false;
      return needsInvertInDark(
        data.buffer.asUint8List(),
        width: image.width,
        height: image.height,
      );
    } catch (_) {
      return false;
    } finally {
      codec?.dispose();
    }
  }
}
