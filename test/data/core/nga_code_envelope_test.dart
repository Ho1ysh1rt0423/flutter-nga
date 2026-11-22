import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';

/// 每次返回同一固定响应体的适配器，用于测拦截器对官方
/// `{"code":N,"msg":..}` 业务信封的处理。
class _FixedBodyAdapter implements HttpClientAdapter {
  _FixedBodyAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(
      Uint8List.fromList(body.codeUnits),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/javascript; charset=GBK'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<Dio> _dioWith(String body) async {
  final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
  dio.httpClientAdapter = _FixedBodyAdapter(body);
  NgaDioConfigurator(() async => null).configure(dio);
  return dio;
}

void main() {
  test('code=12 登录失效被拦截成人话', () async {
    // 真实接口的中文是 \u 转义的纯 ASCII（GBK 通道），测试体保持同构
    final dio = await _dioWith(
      '{"code":12,"msg":"\\u8bf7\\u5148\\u767b\\u5f55"}',
    );
    await expectLater(
      dio.get<Map<String, dynamic>>('app_api.php?__lib=x&__act=y'),
      throwsA(
        isA<DioException>().having((e) => e.error, 'error', '登录状态已失效，请重新登录'),
      ),
    );
  });

  test('纯 code=521（无 html）按风控提示拦截', () async {
    final dio = await _dioWith('{"code":521,"msg":""}');
    await expectLater(
      dio.get<Map<String, dynamic>>('app_api.php?__lib=x&__act=y'),
      throwsA(
        isA<DioException>().having((e) => e.error, 'error', contains('安全验证')),
      ),
    );
  });

  test('code=4 带服务端文案的透传文案', () async {
    final dio = await _dioWith(
      '{"code":4,"msg":"\\u53c2\\u6570\\u9519\\u8bef","result":[]}',
    );
    await expectLater(
      dio.get<Map<String, dynamic>>('app_api.php?__lib=post&__act=list'),
      throwsA(isA<DioException>().having((e) => e.error, 'error', '参数错误')),
    );
  });

  test('code=0 成功信封原样放行', () async {
    final dio = await _dioWith('{"code":0,"result":[[0,0,0,0,0]]}');
    final response = await dio.get<Map<String, dynamic>>(
      'nuke.php?__output=14&__lib=noti&__act=if',
    );
    expect(response.data, isA<Map<String, dynamic>>());
    expect(response.data!['code'], 0);
    expect(response.data!['result'], isNotEmpty);
  });

  test('code=521 带 html 的官方 HTML 通道数据放行（详情回退在用）', () async {
    final dio = await _dioWith(
      '{"code":521,"msg":"","html":"<tr id=\'post1strow0\'>x</tr>","template":"read"}',
    );
    final response = await dio.get<Map<String, dynamic>>(
      'read.php?__output=17&tid=1&page=1',
    );
    expect(response.data, isA<Map<String, dynamic>>());
    expect(response.data!['html'], contains('post1strow0'));
  });

  test('未知 code 的信封不拦截（官方存在 code=1 成功信封）', () async {
    final dio = await _dioWith('{"code":1,"__data":{"a":1}}');
    final response = await dio.get<Map<String, dynamic>>('app_api.php?x=1');
    expect(response.data, isA<Map<String, dynamic>>());
    expect(response.data!['__data'], isA<Map>());
  });
}
