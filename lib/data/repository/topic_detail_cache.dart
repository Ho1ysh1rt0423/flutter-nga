import 'package:sembast/sembast.dart';

/// 详情页原始响应缓存：刷新失败时兜底展示旧数据（stale-while-revalidate）。
///
/// 只存**未截断**的成功响应（截断抢救出来的本来就是残缺数据，缓存它只会
/// 让用户下次看到同样的残页）。存的是拦截器清洗后的原始 Map，避免给
/// TopicDetailData 全家补序列化器；过期上限 7 天，总量环形 200 条。
class TopicDetailCache {
  TopicDetailCache(this.database);

  final Database database;

  static const String storeName = 'topic_cache';
  static const int _maxEntries = 200;

  Future<void> save(String key, Map<String, dynamic> data) async {
    try {
      final store = StoreRef<String, Object?>(storeName);
      // put 覆盖同 key 旧值（同一帖刷新成功就更新缓存时间戳）
      await store.record(key).put(database, _wrap(data));
      await _prune(store);
    } catch (_) {
      // 缓存写失败不影响功能
    }
  }

  Future<({Map<String, dynamic> data, int fetchedAt})?> load(
    String key, {
    Duration maxAge = const Duration(days: 7),
  }) async {
    try {
      final store = StoreRef<String, Object?>(storeName);
      final value = await store.record(key).get(database);
      if (value is! Map) return null;
      final fetchedAt = value['fetchedAt'];
      final data = value['data'];
      if (fetchedAt is! int || data is! Map) return null;
      if (DateTime.now().millisecondsSinceEpoch - fetchedAt >
          maxAge.inMilliseconds) {
        return null;
      }
      return (data: Map<String, dynamic>.from(data), fetchedAt: fetchedAt);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> _wrap(Map<String, dynamic> data) => {
    'data': data,
    'fetchedAt': DateTime.now().millisecondsSinceEpoch,
  };

  Future<void> _prune(StoreRef<String, Object?> store) async {
    final count = await store.count(database);
    if (count <= _maxEntries) return;
    final oldest = await store.find(
      database,
      finder: Finder(
        sortOrders: [SortOrder('fetchedAt')],
        limit: count - _maxEntries,
      ),
    );
    for (final record in oldest) {
      await store.record(record.key).delete(database);
    }
  }
}
