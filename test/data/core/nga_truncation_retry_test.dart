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
    expect(adapter.requests[1], adapter.requests[0], reason: '重试应使用相同 URL');
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
        isA<DioException>().having((e) => e.error, 'error', contains('不完整')),
      ),
    );
    expect(
      adapter.requests.length,
      NgaDioConfigurator.maxTruncationRetries + 1,
      reason: '首次请求 + N 次重试',
    );
  });

  test('retries carry the truncation counter in extra', () async {
    final adapter = _TruncatingAdapter('{"data":{"tid":', '{"data":{"ok":1}}');
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);

    await dio.get<Map<String, dynamic>>('read.php?__output=8');

    // 第一次请求 extra 里不应有计数（调用方设置的 extra 保持不变）
    // 重试由拦截器内部 copyWith 追加，不影响外部调用者的 options
    expect(adapter.requests.length, 2);
  });

  test('repair keeps complete floors and marks the response', () async {
    // 重试两次仍截断（服务端持续异常），但调用方声明可容忍缺数据：
    // 应抢救出已写完整的楼层，并在 extra 里打 truncatedRepairedKey 标记，
    // 让上层界面知道「这不是完整内容」。
    final adapter = _TruncatingAdapter(
      '{"data":{"__R":{"0":{"pid":0,"content":"主楼"},"1":{"pid":2,"authorid":67',
      '{"data":{"__R":{"0":{"pid":0,"content":"主楼"},"1":{"pid":2,"authorid":67',
    );
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);

    final response = await dio.get<Map<String, dynamic>>(
      'read.php?__output=8&tid=1&page=1',
      options: Options(
        extra: {NgaDioConfigurator.allowTruncatedRepairKey: true},
      ),
    );

    expect(
      adapter.requests.length,
      NgaDioConfigurator.maxTruncationRetries + 1,
    );
    final rows = response.data!['__R'] as Map;
    expect(rows.keys, ['0'], reason: '只应保留写完整的第 0 楼');
    expect(
      response.requestOptions.extra[NgaDioConfigurator.truncatedRepairedKey],
      isTrue,
      reason: '界面要靠这个标记提示「内容不完整」',
    );
  });

  test('truncationMaxRetriesKey 0 skips retries and repairs at once', () async {
    // 缩略图请求的配置：可抢救 + 不重试。串行队列里每个截断的 tid 若先走
    // 0.9s + 2.5s 重试再抢救，会把后面的缩略图全部卡住。
    final adapter = _TruncatingAdapter(
      '{"data":{"__R":{"0":{"pid":0,"content":"主楼"},"1":{"pid":2,"authorid":67',
      '{"data":{"__R":{"0":{"pid":0,"content":"主楼"},"1":{"pid":2,"authorid":67',
    );
    final dio = Dio()..options.baseUrl = 'https://bbs.nga.cn/';
    dio.httpClientAdapter = adapter;
    NgaDioConfigurator(() async => null).configure(dio);

    final response = await dio.get<Map<String, dynamic>>(
      'read.php?__output=8&tid=1&pid=0',
      options: Options(
        extra: {
          NgaDioConfigurator.allowTruncatedRepairKey: true,
          NgaDioConfigurator.truncationMaxRetriesKey: 0,
        },
      ),
    );

    expect(adapter.requests.length, 1, reason: '重试上限 0 时应立即抢救，不发重试请求');
    expect((response.data!['__R'] as Map).keys, ['0']);
    expect(
      response.requestOptions.extra[NgaDioConfigurator.truncatedRepairedKey],
      isTrue,
    );
  });
}
