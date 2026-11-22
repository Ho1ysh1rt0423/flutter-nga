import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:flutter_nga/data/repository/topic_detail_cache.dart';

void main() {
  late Database database;
  late TopicDetailCache cache;

  setUp(() async {
    database = await databaseFactoryMemory.openDatabase('topic-cache-test.db');
    cache = TopicDetailCache(database);
  });

  test('save 后 load 能取回原始响应与时间戳', () async {
    final data = {
      '__ROWS': 20,
      '__R': {
        '0': {'pid': 1},
      },
    };
    await cache.save('d:1:1:null', data);

    final cached = await cache.load('d:1:1:null');
    expect(cached, isNotNull);
    expect(cached!.data['__ROWS'], 20);
    expect(cached.fetchedAt, greaterThan(0));
  });

  test('同 key 重复 save 覆盖旧值', () async {
    await cache.save('d:1:1:null', {'v': 1});
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await cache.save('d:1:1:null', {'v': 2});

    final cached = await cache.load('d:1:1:null');
    expect(cached!.data['v'], 2);
  });

  test('超过 maxAge 的缓存视为不存在', () async {
    final data = {'v': 1};
    await cache.save('d:old:1:null', data);
    // 直接改库里的时间戳模拟过期
    final store = StoreRef<String, Object?>(TopicDetailCache.storeName);
    final record = await store.record('d:old:1:null').get(database) as Map;
    await store.record('d:old:1:null').put(database, {
      ...record,
      'fetchedAt': DateTime.now().millisecondsSinceEpoch - 8 * 24 * 3600 * 1000,
    });

    expect(await cache.load('d:old:1:null'), isNull);
    expect(
      await cache.load('d:old:1:null', maxAge: const Duration(days: 30)),
      isNotNull,
      reason: '调宽 maxAge 仍可读',
    );
  });

  test('缓存超量时按时间淘汰最老的', () async {
    for (var i = 0; i < 205; i++) {
      await cache.save('k:$i', {'i': i});
    }
    final store = StoreRef<String, Object?>(TopicDetailCache.storeName);
    final count = await store.count(database);
    expect(count, lessThanOrEqualTo(200));
    // 最老的一批被淘汰，最新的一条仍在
    expect(await cache.load('k:204'), isNotNull);
    expect(await cache.load('k:0'), isNull);
  });

  test('load 对损坏的记录返回 null 而不是抛错', () async {
    final store = StoreRef<String, Object?>(TopicDetailCache.storeName);
    await store.record('broken').put(database, {'data': 'not-a-map'});
    expect(await cache.load('broken'), isNull);
    expect(await cache.load('missing'), isNull);
  });
}
