import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'package:flutter_nga/data/core/nga_domains.dart';
import 'package:flutter_nga/data/entity/user.dart';
import 'package:flutter_nga/data/repository/user_repository.dart';
import 'package:flutter_nga/utils/code_utils.dart' as code_utils;

class NgaDioConfigurator {
  /// [enableLogging] 默认仅在 debug 构建开启：PrettyDioLogger 会把请求头
  /// （含 uid/cid 登录 Cookie）打印到 logcat / 系统日志，release 下必须关闭。
  NgaDioConfigurator(this._loadDefaultUser, {this.enableLogging = kDebugMode});

  /// 在 [RequestOptions.extra] 中置为 true 时，响应拦截器跳过 GBK 解码与
  /// JSON 解包，原样返回字节（用于下载图片等二进制资源）。
  static const String rawResponseKey = 'nga_raw_response';

  /// 记录「因响应被截断而重试」的次数，写在 [RequestOptions.extra] 里。
  static const String truncationRetryKey = 'nga_truncation_retry';

  /// 响应经 [repairTruncatedJson] 抢救后置为 true（写在 [RequestOptions.extra]
  /// 里）。仓库层据此把「数据不完整」往上层传，界面必须明确提示，不能把
  /// 抢救出来的部分当成完整内容展示。
  static const String truncatedRepairedKey = 'nga_truncated_repaired';

  /// 在 [RequestOptions.extra] 中置为 true 时，允许对截断的响应做「补闭合」抢救：
  /// 只保留已经写完整的部分，缺的尾巴丢掉。
  ///
  /// 给**能容忍缺数据**的请求用：列表缩略图只读主楼的 attachs，缺后面几楼
  /// 无所谓；详情页（getTopicDetail / getTopicReplies）也开了，但上层会拿
  /// truncatedRepairedKey 标记在界面明确提示「内容不完整」并禁用向后翻页，
  /// 不会把部分楼层当成完整内容误导用户。
  static const String allowTruncatedRepairKey = 'nga_allow_truncated_repair';

  /// 每请求覆盖截断重试上限（int）。省略时用 [maxTruncationRetries]。
  ///
  /// 可抢救的请求可以设 0：抢救出的主楼数据已够缩略图用，重试只会让
  /// 串行队列多等 0.9s + 2.5s（详情页保持默认，重试有机会拿全量数据）。
  static const String truncationMaxRetriesKey = 'nga_truncation_max_retries';

  /// 截断响应最多重试几次。
  ///
  /// 实测 NGA 会在输出帖子的 JSON 中途断掉（同一路径从 18054 字节缩到
  /// 12036 字节，且是在某个字段中途停止），过一会儿再请求又完整了。这类
  /// 中断不是网络层的问题（chunked 结尾是完整的），客户端拿不到任何可续传
  /// 的信息，只能重新请求。
  static const int maxTruncationRetries = 2;

  final Future<CacheUser?> Function() _loadDefaultUser;
  final bool enableLogging;
  final GbkCodec _gbk = const GbkCodec(allowMalformed: true);

  /// 用于在响应拦截器里重放请求；由 [configure] 注入。
  Dio? _dio;

  void configure(Dio dio) {
    _dio = dio;
    dio.options.connectTimeout = const Duration(milliseconds: 10000);
    dio.options.receiveTimeout = const Duration(milliseconds: 10000);
    dio.options.responseType = ResponseType.bytes;
    dio.options.headers["Accept-Encoding"] = "gzip";
    dio.options.headers["Cache-Control"] = "max-age=0";
    dio.options.headers["Connection"] = "Keep-Alive";

    dio.interceptors.add(_createMainInterceptor());
    if (enableLogging) {
      dio.interceptors.add(PrettyDioLogger(responseBody: false));
    }
  }

  InterceptorsWrapper _createMainInterceptor() {
    return InterceptorsWrapper(
      onRequest: _handleRequest,
      onResponse: _handleResponse,
      onError: _handleError,
    );
  }

  Future<void> _handleRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.headers["Cookie"] == null && shouldAttachLoginCookie(options)) {
      final user = await _loadDefaultUser();
      if (user != null) {
        options.headers["Cookie"] = "$TAG_UID=${user.uid};$TAG_CID=${user.cid}";
      }
    }
    handler.next(options);
  }

  /// 只有请求 NGA 自有域名或当前 baseUrl（含用户自定义地址）时才携带登录
  /// Cookie，避免把凭据发给帖子中引用的第三方图床等外部站点。
  @visibleForTesting
  static bool shouldAttachLoginCookie(RequestOptions options) {
    final host = options.uri.host.toLowerCase();
    if (host.isEmpty) return false;
    if (isNgaHost(host)) return true;
    final baseHost = Uri.tryParse(options.baseUrl)?.host.toLowerCase() ?? '';
    return baseHost.isNotEmpty && host == baseHost;
  }

  Future<void> _handleResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (_isRawResponse(response.requestOptions)) {
      handler.next(response);
      return;
    }
    response.headers.set('Content-Type', "application/json; charset=GBK");
    final responseBody = _formatResponseBody(response);
    final map = _tryDecodeMap(responseBody);
    if (map == null) {
      // 正文明显是 JSON（以 { / [ 开头）却解析不出来，基本可以断定是服务端
      // 返回了被截断的响应（实测有 4106 / 10775 / 12036 字节的残缺 JSON，
      // 都在某个字段中途停住）。这类中断在 chunked 层是"完整"的，客户端
      // 拿不到续传信息，只能重新请求；服务端偶尔会在几秒后恢复正常。
      if (_looksLikeJson(responseBody)) {
        if (await _retryTruncated(response.requestOptions, handler)) return;
        // 重试还是截断：调用方若声明「能容忍缺数据」，抢救出已写完整的部分。
        // 截断点常落在某个楼层对象中途（`..."authorid":672`），把它前面那些
        // 完整的楼层保留下来，足够列表缩略图这类只关心主楼的场景使用。
        if (response.requestOptions.extra[allowTruncatedRepairKey] == true) {
          final repaired = repairTruncatedJson(responseBody);
          final repairedMap = repaired == null ? null : _tryDecodeMap(repaired);
          final repairedPayload = repairedMap == null
              ? null
              : (repairedMap.containsKey("data")
                    ? repairedMap["data"]
                    : repairedMap);
          if (repairedPayload is Map<String, dynamic>) {
            debugPrint('[json] 响应被截断，已抢救出完整部分: ${response.requestOptions.uri}');
            response.requestOptions.extra[truncatedRepairedKey] = true;
            response.data = repairedPayload;
            handler.next(response);
            return;
          }
        }
        // 重试机会用尽（或无法重试）：此时若把原始字符串塞回 response.data，
        // 声明了 Response<Map<String, dynamic>> 的仓库会在 Dio 的 `as T?`
        // 转型处抛 "type 'String' is not a subtype of type
        // 'Map<String, dynamic>?'"，用户看到的是一句天书。这里主动 reject
        // 成可读错误。
        handler.reject(
          DioException(
            requestOptions: response.requestOptions,
            error: 'NGA 服务端返回的数据不完整（常见于新帖或热门帖），稍等片刻下拉刷新即可',
            type: DioExceptionType.badResponse,
          ),
        );
        return;
      }
      // 非 JSON（如 post.php 的 HTML 结果页）保持原样，供 Response<String> 使用
      response.data = responseBody;
      handler.next(response);
      return;
    }

    final dioError = _preHandleServerError(response, map);
    if (dioError != null) {
      handler.reject(dioError);
      return;
    }

    // 部分接口（帖子被删除、权限不足等）会把提示语直接放进 data 字段。
    // 之前无条件写入 response.data，会让 Dio 在返回时做
    // `String -> Map<String, dynamic>` 的泛型转型并抛
    // "type 'String' is not a subtype of type 'Map<String, dynamic>?'"，
    // 整个帖子页面因此变成空白。这里按类型分支处理。
    final dynamic payload = map.containsKey("data") ? map["data"] : map;
    if (payload is Map<String, dynamic>) {
      response.data = payload;
    } else if (payload is String && payload.isNotEmpty) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          error: payload,
          type: DioExceptionType.unknown,
        ),
      );
      return;
    } else {
      response.data = map;
    }
    handler.next(response);
  }

  Future<void> _handleError(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    debugPrint(e.toString());
    if (e.error is IOException) {
      handler.next(
        DioException(
          requestOptions: e.requestOptions,
          error: "网络错误，请稍候重试。",
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }
    if (_isRawResponse(e.requestOptions) ||
        e.response == null ||
        e.response!.data == null) {
      handler.next(e);
      return;
    }

    final responseBody = _formatResponseBody(e.response!);
    final map = _tryDecodeMap(responseBody);
    if (map == null) {
      handler.next(e);
      return;
    }

    final dioError = _preHandleServerError(e.response, map);
    handler.next(dioError ?? e);
  }

  bool _isRawResponse(RequestOptions options) =>
      options.extra[rawResponseKey] == true;

  /// 因响应被截断而重放请求。
  ///
  /// 只在满足以下条件时重试，其余情况返回 false 交给调用方报错：
  /// - 有可复用的 [Dio] 实例；
  /// - 请求可安全重放（GET，或带显式 `data` 的请求不带流式 body）；
  /// - 还没超过 [maxTruncationRetries] 次。
  ///
  /// 重放走 [Dio.fetch]，因此会重新经过拦截器（cookie 注入、GBK 解码、
  /// JSON 清洗都有）。成功后直接 `handler.resolve`，原请求的 future 正常
  /// 返回数据，调用方完全感知不到这次重试。
  Future<bool> _retryTruncated(
    RequestOptions options,
    ResponseInterceptorHandler handler,
  ) async {
    final dio = _dio;
    if (dio == null) return false;
    if (options.method.toUpperCase() != 'GET') return false;
    if (options.data is Stream) return false;

    final attempt = (options.extra[truncationRetryKey] as int?) ?? 0;
    final maxRetries =
        (options.extra[truncationMaxRetriesKey] as int?) ??
        maxTruncationRetries;
    if (attempt >= maxRetries) return false;

    // 重试前等一等。实测（2026-11-17）这类截断**不是** CDN 边缘缓存问题：
    // 同一 tid 连发 8 种请求（原样 3 次 / 加随机参数破缓存 / 换 ngabbs.com 和
    // nga.178.com / 换 __output=1、8、11 / 换 page=2）返回的截断长度**完全一致**，
    // 说明是源站侧某个坏掉的响应对象，短时间内重放同一请求必然拿到同一份坏数据。
    // 所以间隔给足（0.9s / 2.5s）而不是密集重试，等服务端把它刷掉。
    await Future<void>.delayed(Duration(milliseconds: 900 + attempt * 1600));
    if (options.cancelToken?.isCancelled == true) return false;

    final nextExtra = Map<String, dynamic>.from(options.extra)
      ..[truncationRetryKey] = attempt + 1;
    final next = options.copyWith(extra: nextExtra);
    debugPrint('[json] 响应被截断，重试 ${attempt + 1}/$maxRetries: ${options.uri}');

    try {
      final retried = await dio.fetch<dynamic>(next);
      handler.resolve(retried);
      return true;
    } on DioException catch (err) {
      // 重试也失败：交给 onError 链路走正常错误处理
      handler.reject(err);
      return true;
    }
  }

  /// 去掉首尾空白后是否以 JSON 的起始字符开头。
  ///
  /// 用来区分「本该是 JSON 但被截断」和「本来就是 HTML / 纯文本」：
  /// 前者要给用户可读的错误提示，后者要原样返回（如 post.php 的结果页）。
  static bool _looksLikeJson(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  Map<String, dynamic>? _tryDecodeMap(String responseBody) {
    for (final candidate in _jsonCandidates(responseBody)) {
      try {
        final decoded = json.decode(candidate);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {
        // 该策略不适用，换下一种清洗方式重试
      }
    }
    debugPrint('[json] 所有清洗策略均无法解析，响应长度=${responseBody.length}');
    // 打首尾片段：能区分「服务端在中途截断」和「解码/Gzip 异常」。
    // logcat 单条有长度上限，只取两端各 160 字符。
    const previewLength = 160;
    final head = responseBody.length > previewLength
        ? responseBody.substring(0, previewLength)
        : responseBody;
    debugPrint('[json] 头部: $head');
    if (responseBody.length > previewLength) {
      debugPrint(
        '[json] 尾部: ${responseBody.substring(responseBody.length - previewLength)}',
      );
    }
    return null;
  }

  /// 从被截断的 JSON 里抢救出已经写完整的部分。
  ///
  /// 扫描一遍，记下「最后一个完整闭合的对象边界」，从那里截断并把括号补齐，
  /// 得到一份合法但更短的 JSON。返回 null 表示救不出来。
  ///
  /// 只在 [allowTruncatedRepairKey] 为 true 的请求上用：**数据会缺**，界面不能
  /// 把它当成完整内容展示。
  @visibleForTesting
  static String? repairTruncatedJson(String body) {
    final open = <int>[]; // 尚未闭合的 '{' / '['
    var inString = false;
    var escaped = false;
    int? cutIndex;
    List<int>? cutStack;

    for (var i = 0; i < body.length; i++) {
      final ch = body.codeUnitAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == 0x5C) {
          // 反斜杠转义
          escaped = true;
        } else if (ch == 0x22) {
          inString = false;
        }
        continue;
      }
      if (ch == 0x22) {
        inString = true;
        continue;
      }
      if (ch == 0x7B || ch == 0x5B) {
        // { [
        open.add(ch);
        continue;
      }
      if (ch == 0x7D || ch == 0x5D) {
        // } ]
        if (open.isEmpty) return null;
        open.removeLast();
        // 只认「比较靠外层」的边界，太深的地方补出来也没多少内容
        if (open.isNotEmpty && open.length <= 4) {
          cutIndex = i;
          cutStack = List<int>.of(open);
        }
      }
    }

    if (cutIndex == null || cutStack == null) return null;
    final buffer = StringBuffer(body.substring(0, cutIndex + 1));
    for (final opened in cutStack.reversed) {
      buffer.write(opened == 0x5B ? ']' : '}');
    }
    return buffer.toString();
  }

  /// 按「从保守到激进」的顺序给出候选文本，原文能解析就不会走到后面的清洗。
  Iterable<String> _jsonCandidates(String body) sync* {
    yield body;
    yield code_utils.stripLow(body);
    yield code_utils.stripLow(body, true);
    yield _escapeControlChars(body);
  }

  /// 把控制字符转义而不是删除，避免删掉换行后前一个反斜杠把引号吃掉。
  String _escapeControlChars(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      switch (rune) {
        case 0x0A:
        case 0x0D:
          buffer.write(r'\n');
        case 0x09:
          buffer.write(r'\t');
        case < 0x20:
        case 0x7F:
          break;
        default:
          buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  String _formatResponseBody(Response response) {
    final bytes = response.data as List<int>;
    var responseBody = _gbk.decode(bytes);
    // 这里不再删除控制字符。stripLow 会把字符串内部的换行去掉，一旦前一个
    // 字符正好是反斜杠，就会把后面的引号一并转义，导致 json 报
    // "Unterminated string"，整页解析失败。清洗策略统一放到 _tryDecodeMap
    // 里按需尝试，原文能直接解析时就用原文。
    responseBody = responseBody
        .replaceAll(
          "<html><head><meta http-equiv='Content-Type' content='text/html; charset=GBK'></head><body><script>",
          "",
        )
        .replaceAll("</script></body></html>", "")
        .replaceAll("window.script_muti_get_var_store=", "");
    if (response.requestOptions.path.contains("__lib=noti") &&
        response.requestOptions.path.contains("__act=get_all")) {
      responseBody = code_utils.fixUnquotedJsonKeys(responseBody);
    }
    return responseBody;
  }

  DioException? _preHandleServerError(
    Response? response,
    Map<String, dynamic> map,
  ) {
    if (response == null) return null;
    if (map["data"] is Map<String, dynamic> &&
        map["data"].containsKey("__MESSAGE")) {
      final errorMessage = map["data"]["__MESSAGE"]["1"];
      return DioException(
        requestOptions: response.requestOptions,
        error: errorMessage,
        type: DioExceptionType.unknown,
      );
    }
    if (map["error"] is Map) {
      final err = map["error"] as Map<String, dynamic>;
      if (err["0"] is String) {
        return DioException(
          requestOptions: response.requestOptions,
          error: err["0"],
          type: DioExceptionType.unknown,
        );
      }
    }
    if (map["error"] is String) {
      final errorMessage = map["error"];
      return DioException(
        requestOptions: response.requestOptions,
        error: errorMessage,
        type: DioExceptionType.unknown,
      );
    }
    return null;
  }
}
