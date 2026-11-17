import 'dart:async';

import 'package:flutter_nga/providers/topic/topic_head_thumbnail_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns the head image urls', () async {
    final queue = TopicHeadThumbnailQueue(
      (tid) async => ['https://img.nga.cn/a.jpg', 'https://img.nga.cn/b.jpg'],
    );
    expect(await queue.fetch(42), [
      'https://img.nga.cn/a.jpg',
      'https://img.nga.cn/b.jpg',
    ]);
  });

  test('a topic without head image yields empty list', () async {
    final queue = TopicHeadThumbnailQueue((tid) async => const []);
    expect(await queue.fetch(42), isEmpty);
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

    expect(await queue.fetch(7), isEmpty);
    expect(await queue.fetch(7), isEmpty);
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
      ['https://img.nga.cn/1.jpg'],
      ['https://img.nga.cn/2.jpg'],
      ['https://img.nga.cn/3.jpg'],
      ['https://img.nga.cn/4.jpg'],
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

    expect(await Future.wait([first, second, third]), everyElement([
      'https://img.nga.cn/7.jpg',
    ]));
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

  test('persisted urls are reused without an HTTP request', () async {
    var calls = 0;
    final queue = TopicHeadThumbnailQueue(
      (tid) async {
        calls++;
        return ['https://img.nga.cn/$tid.jpg'];
      },
      loadPersisted: () async => {
        7: ['https://img.nga.cn/persisted.jpg'],
      },
    );

    expect(await queue.fetch(7), ['https://img.nga.cn/persisted.jpg']);
    expect(calls, 0, reason: '重启后不再为已有结果的帖子发请求');
  });

  test('successful results are written back to the persistent layer',
      () async {
    final persisted = <int, List<String>>{};
    var calls = 0;
    final queue = TopicHeadThumbnailQueue(
      (tid) async {
        calls++;
        return [
          'https://img.nga.cn/${tid}_a.jpg',
          'https://img.nga.cn/${tid}_b.jpg',
        ];
      },
      loadPersisted: () async => persisted,
      persist: (tid, urls) async => persisted[tid] = urls,
    );

    expect(await queue.fetch(7), [
      'https://img.nga.cn/7_a.jpg',
      'https://img.nga.cn/7_b.jpg',
    ]);
    expect(persisted[7], [
      'https://img.nga.cn/7_a.jpg',
      'https://img.nga.cn/7_b.jpg',
    ]);
    expect(calls, 1);

    // 模拟重启：同一队列配置、持久层里有数据
    final restarted = TopicHeadThumbnailQueue(
      (tid) async {
        calls++;
        return ['https://img.nga.cn/$tid.jpg'];
      },
      loadPersisted: () async => persisted,
      persist: (tid, urls) async => persisted[tid] = urls,
    );
    expect(await restarted.fetch(7), [
      'https://img.nga.cn/7_a.jpg',
      'https://img.nga.cn/7_b.jpg',
    ]);
    expect(calls, 1, reason: '重启后命中持久缓存，不再请求');
  });

  test('negative results are not persisted', () async {
    final persisted = <int, List<String>>{};
    final queue = TopicHeadThumbnailQueue(
      (tid) async => const [],
      loadPersisted: () async => persisted,
      persist: (tid, urls) async => persisted[tid] = urls,
    );

    await queue.fetch(7);
    expect(persisted, isEmpty,
        reason: '「主楼没图」可能是后续编辑加了图，重启后再确认一次');
  });

  test('a broken persistent layer does not break fetching', () async {
    final queue = TopicHeadThumbnailQueue(
      (tid) async => ['https://img.nga.cn/$tid.jpg'],
      loadPersisted: () async => throw Exception('db broken'),
      persist: (tid, urls) async => throw Exception('db broken'),
    );

    expect(await queue.fetch(7), ['https://img.nga.cn/7.jpg']);
    expect(await queue.fetch(7), ['https://img.nga.cn/7.jpg']);
  });
}
