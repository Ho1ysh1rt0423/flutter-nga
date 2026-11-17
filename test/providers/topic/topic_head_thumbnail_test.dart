import 'dart:async';

import 'package:flutter_nga/providers/topic/topic_head_thumbnail_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the first head image url', () async {
    final queue = TopicHeadThumbnailQueue(
      (tid) async => ['https://img.nga.cn/a.jpg', 'https://img.nga.cn/b.jpg'],
    );
    expect(await queue.fetch(42), 'https://img.nga.cn/a.jpg');
  });

  test('a topic without head image yields null', () async {
    final queue = TopicHeadThumbnailQueue((tid) async => const []);
    expect(await queue.fetch(42), isNull);
  });

  test('only asks the repository once per tid', () async {
    var calls = 0;
    final queue = TopicHeadThumbnailQueue((tid) async {
      calls++;
      return ['https://img.nga.cn/$tid.jpg'];
    });

    await queue.fetch(7);
    await queue.fetch(7);
    await queue.fetch(7);

    expect(calls, 1);
  });

  test('failures are swallowed and not retried', () async {
    var calls = 0;
    final queue = TopicHeadThumbnailQueue((tid) async {
      calls++;
      throw Exception('boom');
    });

    expect(await queue.fetch(7), isNull);
    expect(await queue.fetch(7), isNull);
    // 失败也要缓存，否则列表每次重建都会重新打一次请求
    expect(calls, 1);
  });

  test('requests run serially even when many are queued at once', () async {
    var running = 0;
    var maxRunning = 0;
    final queue = TopicHeadThumbnailQueue((tid) async {
      running++;
      if (running > maxRunning) maxRunning = running;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      return ['https://img.nga.cn/$tid.jpg'];
    });

    final urls = await Future.wait([
      queue.fetch(1),
      queue.fetch(2),
      queue.fetch(3),
      queue.fetch(4),
    ]);

    expect(maxRunning, 1, reason: '一屏十几条同时请求太像爬虫');
    expect(urls, [
      'https://img.nga.cn/1.jpg',
      'https://img.nga.cn/2.jpg',
      'https://img.nga.cn/3.jpg',
      'https://img.nga.cn/4.jpg',
    ]);
  });

  test('in-flight requests are merged, not queued again', () async {
    // 列表滚动时同一帖子会反复 rebuild；结果没回来之前也必须去重，
    // 否则实测会对同一个 tid 连发 5 次请求。
    var calls = 0;
    final gate = Completer<void>();
    final queue = TopicHeadThumbnailQueue((tid) async {
      calls++;
      await gate.future;
      return ['https://img.nga.cn/$tid.jpg'];
    });

    final first = queue.fetch(7);
    final second = queue.fetch(7);
    final third = queue.fetch(7);
    gate.complete();

    expect(await Future.wait([first, second, third]),
        ['https://img.nga.cn/7.jpg', 'https://img.nga.cn/7.jpg', 'https://img.nga.cn/7.jpg']);
    expect(calls, 1);
  });

  test('clear() drops cached results', () async {
    var calls = 0;
    final queue = TopicHeadThumbnailQueue((tid) async {
      calls++;
      return ['https://img.nga.cn/$tid.jpg'];
    });

    await queue.fetch(1);
    queue.clear();
    await queue.fetch(1);

    expect(calls, 2);
  });
}
