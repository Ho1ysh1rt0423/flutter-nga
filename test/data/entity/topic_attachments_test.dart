import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_nga/data/entity/topic.dart';

void main() {
  group('Topic.parseListAttachmentUrls', () {
    test('parses img attachments into full urls, capped at 3', () {
      final urls = Topic.parseListAttachmentUrls({
        '0': {
          'attachurl': 'mon_202611/17/-570ynQ48-kv6dZ15T3cSqo-zk.jpg',
          'type': 'img',
        },
        '1': {'attachurl': './mon_202611/17/abc-ro.jpg', 'type': 'img'},
        '2': {'attachurl': 'mon_202611/17/c.webp'},
        '3': {'attachurl': 'mon_202611/17/d.jpg', 'type': 'img'},
        '4': {'attachurl': 'mon_202611/17/e.jpg', 'type': 'img'},
      });
      expect(urls, hasLength(Topic.maxListAttachmentCount));
      expect(
        urls[0],
        'https://img.nga.cn/attachments/mon_202611/17/-570ynQ48-kv6dZ15T3cSqo-zk.jpg',
      );
      expect(
        urls[1],
        'https://img.nga.cn/attachments/mon_202611/17/abc-ro.jpg',
      );
      expect(urls[2], 'https://img.nga.cn/attachments/mon_202611/17/c.webp');
    });

    test('skips non-image attachments', () {
      final urls = Topic.parseListAttachmentUrls({
        '0': {'attachurl': 'mon_202611/17/doc.pdf', 'type': 'pdf'},
        '1': {'attachurl': 'mon_202611/17/x.jpg', 'type': 'img'},
      });
      expect(urls, ['https://img.nga.cn/attachments/mon_202611/17/x.jpg']);
    });

    test('returns empty for missing or malformed attachs', () {
      expect(Topic.parseListAttachmentUrls(null), isEmpty);
      expect(Topic.parseListAttachmentUrls(''), isEmpty);
      expect(Topic.parseListAttachmentUrls({'0': 'not-a-map'}), isEmpty);
    });

    test('fromJson picks up attachs field', () {
      final topic = Topic.fromJson({
        'tid': 1,
        'fid': 2,
        'subject': '标题',
        'attachs': {
          '0': {'attachurl': 'mon_202611/17/a.jpg', 'type': 'img'},
        },
      });
      expect(topic.attachmentUrls, hasLength(1));
      expect(
        topic.attachmentUrls.first,
        'https://img.nga.cn/attachments/mon_202611/17/a.jpg',
      );
    });
  });
}
