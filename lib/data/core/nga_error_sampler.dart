import 'dart:async';

import 'package:sembast/sembast.dart';

import 'package:flutter_nga/utils/error_utils.dart';

/// 网络错误采样：把失败请求的「归因类别 + 摘要 + URL」写进 main.db 的
/// `error_samples` store（环形上限 200 条）。
///
/// 目的只有一个：回答「用户经常报的到底是哪种错、多频繁、集中在哪些接口」——
/// 以前这类信息只存在于 release 下看不到的 debugPrint 里。只写不读，不做
/// 界面，诊断时从设备拉库查 store。采样失败一律静默，诊断设施不能反过来
/// 影响功能。
class NgaErrorSampler {
  NgaErrorSampler._();

  static final NgaErrorSampler instance = NgaErrorSampler._();

  static const String storeName = 'error_samples';
  static const int _maxEntries = 200;

  Database? _database;

  /// 在 Data.init() 打开 main.db 后调用；未 attach 时采样为 no-op。
  void attach(Database database) {
    _database = database;
  }

  void sample(Object? error, {String? url}) {
    final db = _database;
    if (db == null) return;
    unawaited(_write(db, error, url));
  }

  Future<void> _write(Database db, Object? error, String? url) async {
    try {
      final store = StoreRef<String, Object?>(storeName);
      final category = classifyNgaError(error);
      final message = friendlyNgaErrorMessage(
        error,
        fallback: error?.toString() ?? '未知错误',
      );
      await store.record('${DateTime.now().microsecondsSinceEpoch}').add(db, {
        'ts': DateTime.now().millisecondsSinceEpoch,
        'category': category.name,
        'message': message.length > 200 ? message.substring(0, 200) : message,
        if (url != null && url.isNotEmpty)
          'url': url.length > 300 ? url.substring(0, 300) : url,
      });
      final count = await store.count(db);
      if (count > _maxEntries) {
        final oldest = await store.find(
          db,
          finder: Finder(
            sortOrders: [SortOrder('ts')],
            limit: count - _maxEntries,
          ),
        );
        for (final record in oldest) {
          await store.record(record.key).delete(db);
        }
      }
    } catch (_) {
      // 静默
    }
  }
}
