import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/utils/emoticon_visibility.dart';

/// 生成 [width]x[height] 的 RGBA 像素数据。
///
/// [pixel] 返回 `0xRRGGBBAA` 形式的颜色（alpha 在最低字节）。
Uint8List _rgba(
  int width,
  int height,
  int Function(int index) pixel,
) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final color = pixel(i);
    data[i * 4] = (color >> 24) & 0xFF; // R
    data[i * 4 + 1] = (color >> 16) & 0xFF; // G
    data[i * 4 + 2] = (color >> 8) & 0xFF; // B
    data[i * 4 + 3] = color & 0xFF; // A
  }
  return data;
}

void main() {
  group('EmoticonVisibility.needsInvertInDark', () {
    test('flags transparent black line art (AC娘 style)', () {
      // 30% 像素为不透明纯黑，其余全透明 —— 与实测的 ac0.png / dt01.png 一致
      final data = _rgba(10, 10, (i) => i % 10 < 3 ? 0x000000FF : 0x00000000);
      expect(
        EmoticonVisibility.needsInvertInDark(data, width: 10, height: 10),
        isTrue,
      );
    });

    test('does not flag opaque colorful emoticon (smile.gif style)', () {
      // 80% 不透明、黄色为主的圆脸
      final data = _rgba(
        10,
        10,
        (i) => i % 10 < 8 ? 0xF0D040FF : 0x00000000,
      );
      expect(
        EmoticonVisibility.needsInvertInDark(data, width: 10, height: 10),
        isFalse,
      );
    });

    test('does not flag bright transparent line art', () {
      final data = _rgba(10, 10, (i) => i % 10 < 3 ? 0xFFFFFFF0 : 0x00000000);
      expect(
        EmoticonVisibility.needsInvertInDark(data, width: 10, height: 10),
        isFalse,
      );
    });

    test('fully opaque dark image is left alone (has its own background)', () {
      final data = _rgba(10, 10, (_) => 0x101010FF);
      expect(
        EmoticonVisibility.needsInvertInDark(data, width: 10, height: 10),
        isFalse,
      );
    });

    test('returns false for empty or short buffers', () {
      expect(
        EmoticonVisibility.needsInvertInDark(Uint8List(0), width: 0, height: 0),
        isFalse,
      );
      expect(
        EmoticonVisibility.needsInvertInDark(
          Uint8List(8),
          width: 10,
          height: 10,
        ),
        isFalse,
      );
    });

    test('fully transparent image is left alone', () {
      final data = _rgba(4, 4, (_) => 0x00000000);
      expect(
        EmoticonVisibility.needsInvertInDark(data, width: 4, height: 4),
        isFalse,
      );
    });
  });
}