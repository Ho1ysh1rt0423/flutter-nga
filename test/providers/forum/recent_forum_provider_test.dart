import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/core/app_preferences.dart';
import 'package:flutter_nga/data/entity/forum.dart';
import 'package:flutter_nga/data/entity/recent_forum.dart';
import 'package:flutter_nga/providers/forum/recent_forum_provider.dart';

import '../../test_utils/preferences.dart';

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(ProviderContainer container) async {
  // 先 read 触发 build()（provider 是懒加载），再 pump 完所有异步与 microtask。
  container.read(recentForumProvider);
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RecentForum parses defensively and drops broken entries', () {
    final valid = RecentForum.fromJson({
      'fid': 7,
      'name': '议事厅',
      'type': 0,
      'iconId': 88,
      'visitedAt': 1234,
    });
    expect(valid.forum.fid, 7);
    expect(valid.forum.name, '议事厅');
    expect(valid.forum.type, 0);
    expect(valid.forum.iconId, 88);
    expect(valid.visitedAt, 1234);

    for (final broken in [
      {'fid': 'x', 'name': '坏 fid'},
      {'fid': 1},
      'not a map',
    ]) {
      expect(
        () => RecentForum.fromJson(broken),
        throwsA(isA<FormatException>()),
        reason: '$broken should be rejected',
      );
    }
  });

  test(
    'record de-dupes by identity, keeps newest first, caps the list',
    () async {
      setUpTestPreferences();
      final container = _container();
      await _settle(container);

      final notifier = container.read(recentForumProvider.notifier);
      notifier.record(const Forum(1, '议事厅'));
      await _settle(container);
      notifier.record(const Forum(2, '剑斗绮谭'));
      await _settle(container);
      notifier.record(const Forum(1, '议事厅', iconId: 99));
      await _settle(container);

      final forums = container.read(recentForumProvider).forums;
      expect(forums.map((e) => e.forum.fid), [1, 2]);
      // 同名同 type 只留最新一条，并且带上了新 iconId。
      expect(forums.first.forum.iconId, 99);
    },
  );

  test('record persists across a provider restart', () async {
    setUpTestPreferences();
    final container = _container();
    await _settle(container);

    container
        .read(recentForumProvider.notifier)
        .record(const Forum(5, '原神', type: 1));
    await _settle(container);

    // 模拟冷启动：清掉进程内 provider 缓存，重新读取落盘数据。
    final prefs = await AppPreferences.instance();
    final raw = prefs.getString(PrefsKeys.visitedForums);
    expect(raw, isNotNull);
    final decoded = (jsonDecode(raw!) as List)
        .map((e) => RecentForum.fromJson(e))
        .toList();
    expect(decoded.single.forum.fid, 5);
    expect(decoded.single.forum.name, '原神');
    expect(decoded.single.forum.type, 1);
  });

  test('a corrupted stored payload does not crash the provider', () async {
    setUpTestPreferences(current: {PrefsKeys.visitedForums: '{broken'});
    final container = _container();
    await _settle(container);

    expect(container.read(recentForumProvider).forums, isEmpty);
    expect(container.read(recentForumProvider).isLoaded, isTrue);
  });

  test('clear empties both state and storage', () async {
    setUpTestPreferences();
    final container = _container();
    await _settle(container);
    final notifier = container.read(recentForumProvider.notifier);

    notifier.record(const Forum(3, '崩铁'));
    await _settle(container);
    await notifier.clear();
    await _settle(container);

    expect(container.read(recentForumProvider).forums, isEmpty);
    final prefs = await AppPreferences.instance();
    expect(prefs.getString(PrefsKeys.visitedForums), isNull);
  });
}
