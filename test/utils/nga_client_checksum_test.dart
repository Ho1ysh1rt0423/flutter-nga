import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/utils/nga_client_checksum.dart';

/// 固定向量由 Python hashlib 独立计算（逆向算法的对照基准，勿改 t）。
void main() {
  group('ngaClientChecksum', () {
    const t = 1795348710;

    test('真实 uid 的 checksum 链', () {
      expect(
        ngaClientChecksum('62097469', timestampSeconds: t),
        '4848a0f6d9c0cbdd65c8594ea3bdb27f1795348710',
      );
      expect(
        ngaClientChecksum('602', timestampSeconds: t),
        'c563601c4165ec111be3e384f3ebce5b1795348710',
      );
    });

    test('空 uid（首登场景）', () {
      expect(
        ngaClientChecksum('', timestampSeconds: t),
        '3c9d8c85675597e0ec1502206312dd611795348710',
      );
    });

    test('输出 = 32 位 hex + 时间戳后缀', () {
      final out = ngaClientChecksum('123456', timestampSeconds: t);
      expect(out.length, 42);
      expect(out.endsWith('$t'), isTrue);
      expect(RegExp(r'^[0-9a-f]{32}').hasMatch(out.substring(0, 32)), isTrue);
    });
  });

  group('ngaLoginTempId', () {
    test('密码中字母数字下划线的 charCode 求和', () {
      expect(ngaLoginTempId('abc'), 97 + 98 + 99);
      expect(ngaLoginTempId('Ab_1'), 65 + 98 + 95 + 49);
    });

    test('符号与中文不计入', () {
      expect(ngaLoginTempId('!@#'), 0);
      expect(ngaLoginTempId('中文'), 0);
      expect(ngaLoginTempId('a1!中'), 97 + 49);
    });

    test('空密码为 0', () {
      expect(ngaLoginTempId(''), 0);
    });
  });
}
