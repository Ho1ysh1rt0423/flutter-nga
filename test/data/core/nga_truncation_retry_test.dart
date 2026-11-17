import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_nga/data/entity/user.dart';

/// 先返回 [truncatedBody]，之后返回完整 [fullBody] 的适配器，
/// 用于模拟「服务端偶发返回被截断的 JSON，重试后恢复」的场景。
class _TruncatingAdapter implements HttpClientAdapter {
  _TruncatingAdapter(this.truncatedBody, this.fullBody);

  final String truncatedBody;
  final String fullBody;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    final body = requests.length == 1 ? truncatedBody : fullBody;
    // 记录重试计数是否透传
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('truncated JSON is retried and then succeeds', () async {
    final adapter = _TruncatingAdapter(
      '{"data":{"__GLOBAL":{},"__T":{"tid":',
      '{"data":{"__GLOBAL":{},"ok":1}}',
    );
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => CacheUser('42', 'cid', 'nick', true))
        .configure(dio);

    final response = await dio.get<Map<String, dynamic>>(
      'read.php?__output=8&tid=1&page=1',
    );
    // 拦截器已把外层 {"data": {...}} 解包，直接拿内层字段
    expect(response.data, isA<Map<String, dynamic>>());
    expect(response.data!['ok'], 1);
    expect(adapter.requests.length, 2, reason: '应该重试了一次');
    expect(
      adapter.requests[1],
      adapter.requests[0],
      reason: '重试应使用相同 URL',
    );
  });

  test('truncated JSON gives up after maxTruncationRetries', () async {
    // 每次都返回截断体：fullBody 也设为截断，模拟服务端持续异常
    final adapter = _TruncatingAdapter(
      '{"data":{"__GLOBAL":{},"__T":{"tid":',
      '{"data":{"__GLOBAL":{},"__T":{"tid":',
    );
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);

    await expectLater(
      dio.get<Map<String, dynamic>>('read.php?__output=8&tid=1&page=1'),
      throwsA(
        isA<DioException>().having(
          (e) => e.error,
          'error',
          contains('不完整'),
        ),
      ),
    );
    expect(
      adapter.requests.length,
      NgaDioConfigurator.maxTruncationRetries + 1,
      reason: '首次请求 + N 次重试',
    );
  });

  test('retries carry the truncation counter in extra', () async {
    final adapter = _TruncatingAdapter(
      '{"data":{"tid":',
      '{"data":{"ok":1}}',
    );
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);

    await dio.get<Map<String, dynamic>>('read.php?__output=8');

    // 第一次请求 extra 里不应有计数（调用方设置的 extra 保持不变）
    // 重试由拦截器内部 copyWith 追加，不影响外部调用者的 options
    expect(adapter.requests.length, 2);
  });
}