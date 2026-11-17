import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_nga/utils/picture_utils.dart' as picture_utils;

void main() {
  group('getThumbUrl', () {
    test('appends .thumb.jpg to original attachment url', () {
      expect(
        picture_utils.getThumbUrl(
          'https://img.nga.cn/attachments/mon_202611/17/x-ro.jpg',
        ),
        'https://img.nga.cn/attachments/mon_202611/17/x-ro.jpg.thumb.jpg',
      );
    });

    test('also works for webp originals', () {
      expect(
        picture_utils.getThumbUrl(
          'https://img.nga.cn/attachments/mon_xxx.webp',
        ),
        'https://img.nga.cn/attachments/mon_xxx.webp.thumb.jpg',
      );
    });

    test('leaves already-thumbnailed urls alone', () {
      const url =
          'https://img.nga.cn/attachments/mon_xxx.jpg.thumb.jpg';
      expect(picture_utils.getThumbUrl(url), url);
    });

    test('leaves urls with query strings alone', () {
      expect(
        picture_utils.getThumbUrl('https://img.nga.cn/avatars/a.jpg?55'),
        'https://img.nga.cn/avatars/a.jpg?55',
      );
    });

    test('handles empty input', () {
      expect(picture_utils.getThumbUrl(''), '');
    });
  });
}