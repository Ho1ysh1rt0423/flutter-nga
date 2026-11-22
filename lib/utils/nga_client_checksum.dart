import 'dart:convert';

import 'package:crypto/crypto.dart';

/// `__ngaClientChecksum`（逆向自官方 APK `rv/m0.java`）。
///
/// NGA 服务端用它识别官方客户端：登录页表单带真值时免图片验证码；
/// 官方 App 的 web 请求也普遍携带。算法（小写 hex md5）：
///
/// ```
/// t = unix 秒
/// md51 = md5("161c8c015f912abf4434c3263279c296" + t)
/// md52 = md5(md51 + "12d6af9da0f1fe4e3c87f76ce0aec149")
/// checksum = md5(uid + md52 + t) + t
/// ```
///
/// [uid] 由调用方按页面规则传入：登录场景是 `_tempid(密码)`（密码中
/// `[a-zA-Z0-9_]` 字符的 charCode 求和，见 [ngaLoginTempId]），首登无需
/// 已知账号；登录后场景传真实 uid 字符串。
String ngaClientChecksum(String uid, {int? timestampSeconds}) {
  final t = (timestampSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000)
      .toString();
  final md51 = md5Hex('161c8c015f912abf4434c3263279c296$t');
  final md52 = md5Hex(
    '$md51'
    '12d6af9da0f1fe4e3c87f76ce0aec149',
  );
  return '${md5Hex('$uid$md52$t')}$t';
}

/// 登录页的 `_tempid(密码)`：密码中 `[a-zA-Z0-9_]` 字符的 charCode 求和。
int ngaLoginTempId(String password) {
  var sum = 0;
  for (final rune in password.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[a-zA-Z0-9_]').hasMatch(ch)) sum += rune;
  }
  return sum;
}

String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();
