import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_nga/data/repository/user_repository.dart';
import 'package:flutter_nga/utils/nga_client_checksum.dart';

/// 捕获 multipart 请求体并返回固定登录响应的适配器。
class _CapturingAdapter implements HttpClientAdapter {
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await requestStream!.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    bodies.add(utf8.decode(bytes, allowMalformed: true));
    const body =
        '{"data":["",null,null,{"uid":"62097469","token":"X8v4dsmoqi8vbrt3064bcd31tkebrs1a15","username":"\\u6d4b\\u8bd5\\u7528\\u6237"}]}';
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(body)),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/javascript; charset=GBK'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<UserDataRepository> _repoWith(
  _CapturingAdapter adapter,
  String db,
) async {
  final database = await databaseFactoryMemory.openDatabase(db);
  final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
  dio.httpClientAdapter = adapter;
  // 仓库层依赖拦截器剥 script_muti_get_var_store 壳与 {data:...} 解包
  NgaDioConfigurator(() async => null).configure(dio);
  return UserDataRepository(database, dio);
}

String _formFieldValue(String multipartBody, String name) {
  // multipart 字段提取：--boundary 头后跟空行再跟值
  final pattern = RegExp('name="$name"\\r?\\n\\r?\\n([^\\r\\n]+)');
  return pattern.firstMatch(multipartBody)?.group(1) ?? '';
}

void main() {
  test('loginWithPassword 按官方登录页同构提交并解析响应', () async {
    final adapter = _CapturingAdapter();
    final repository = await _repoWith(adapter, 'login-test.db');

    final user = await repository.loginWithPassword(
      account: 'test_user',
      password: 'abc123',
      type: LoginAccountType.auto,
    );

    expect(adapter.bodies, hasLength(1));
    final body = adapter.bodies.single;

    expect(_formFieldValue(body, '__lib'), 'login');
    expect(_formFieldValue(body, '__act'), 'login');
    expect(_formFieldValue(body, '__output'), '1');
    expect(_formFieldValue(body, 'app_id'), '1010');
    expect(_formFieldValue(body, '__inchst'), 'UTF-8');
    expect(_formFieldValue(body, 'name'), 'test_user');
    expect(_formFieldValue(body, 'type'), '');
    // 无验证码场景不携带 captcha 字段
    expect(body.contains('name="captcha"'), isFalse);

    // checksum：从请求里抽出值，按其时间戳后缀重算校验
    final checksumValue = _formFieldValue(body, '__ngaClientChecksum');
    expect(checksumValue, isNotEmpty);
    final t = int.parse(checksumValue.substring(32));
    expect(
      checksumValue,
      ngaClientChecksum('${ngaLoginTempId('abc123')}', timestampSeconds: t),
    );

    // 密码已 RSA 加密：不是明文，且是合法 base64（2048 位 → 256 字节）
    final passwordField = _formFieldValue(body, 'password');
    expect(passwordField, isNot(contains('abc123')));
    expect(base64.decode(passwordField), hasLength(256));

    // 响应解析入库：data[3] 的 uid/token/username
    expect(user.uid, '62097469');
    expect(user.cid, 'X8v4dsmoqi8vbrt3064bcd31tkebrs1a15');
    expect(user.nickname, '测试用户');
  });

  test('显式指定邮箱类型时 type=mail', () async {
    final adapter = _CapturingAdapter();
    final repository = await _repoWith(adapter, 'login-test2.db');

    await repository.loginWithPassword(
      account: 'a@b.com',
      password: 'x',
      type: LoginAccountType.mail,
    );

    expect(_formFieldValue(adapter.bodies.single, 'type'), 'mail');
  });
}
