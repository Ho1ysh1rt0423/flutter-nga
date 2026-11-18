import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/entity/user.dart';

void main() {
  group('User.fromJson avatar 容错', () {
    test('avatar 为 Map 且 "l" 缺失时回退 null，不抛 RangeError', () {
      // 服务端偶尔把 avatar 下发成 {"0": "..."} 而 "l"（张数）缺失
      final user = User.fromJson({
        'uid': 1,
        'username': 'alice',
        'avatar': {'0': 'https://img.example/a.png'},
      });

      expect(user.avatar, isNull);
      expect(user.avatarList, isEmpty);
    });

    test('avatar 为 Map 且 "l" 非 int 时同样回退 null', () {
      final user = User.fromJson({
        'uid': 1,
        'username': 'alice',
        'avatar': {'l': '3', '0': 'a.png', '1': 'b.png'},
      });

      expect(user.avatar, isNull);
    });

    test('avatar 为正常 Map 时仍取第一张', () {
      final user = User.fromJson({
        'uid': 1,
        'username': 'alice',
        'avatar': {'l': 2, '0': 'a.png', '1': 'b.png'},
      });

      expect(user.avatar, 'a.png');
      expect(user.avatarList, ['a.png', 'b.png']);
    });

    test('avatar 为字符串时原样保留', () {
      final user = User.fromJson({
        'uid': 1,
        'username': 'alice',
        'avatar': 'https://img.example/a.png',
      });

      expect(user.avatar, 'https://img.example/a.png');
    });
  });
}
