import 'package:dio/dio.dart';

/// Extracts a short, user-facing message from an arbitrary error.
///
/// Prefer [DioException.error] (where this app puts server text) over
/// [DioException.message], then fall back to [Object.toString].
String errorMessage(Object? error, {String fallback = '操作失败'}) {
  if (error == null) return fallback;

  if (error is String) {
    final text = error.trim();
    return text.isEmpty ? fallback : text;
  }

  if (error is DioException) {
    for (final candidate in [
      error.error,
      error.message,
      error.response?.statusMessage,
    ]) {
      final text = _nonEmpty(candidate);
      if (text != null) return text;
    }
  }

  final text = error.toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _nonEmpty(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// 服务端/网络错误的归因类别。采样日志按它统计「用户遇到的到底是哪种错」，
/// 界面提示按它给可读文案。
enum NgaErrorCategory {
  /// 未登录 / 登录失效（cookie 过期、访客受限）
  loginRequired,

  /// 触发站点风控 / 安全验证
  riskControl,

  /// 操作过于频繁
  rateLimited,

  /// 服务端返回的数据被截断（本项目的「数据不完整」错误）
  serverDataIncomplete,

  /// 网络/超时类，与服务端无关
  network,

  /// 服务端业务错误（有明确文案）
  server,

  /// 其他
  other,
}

/// 对 [errorMessage] 提取出的文本做归因。
NgaErrorCategory classifyNgaError(Object? error) {
  final text = errorMessage(error, fallback: '');

  if (text.contains('访客不能') ||
      text.contains('游客不能') ||
      text.contains('请先登录') ||
      text.contains('未登录') ||
      text.contains('登录已失效') ||
      text.contains('请重新登录') ||
      text.contains('登录状态已失效')) {
    return NgaErrorCategory.loginRequired;
  }
  if (text.contains('安全验证') || text.contains('风控') || text.contains('异常流量')) {
    return NgaErrorCategory.riskControl;
  }
  if (text.contains('过于频繁')) {
    return NgaErrorCategory.rateLimited;
  }
  if (text.contains('数据不完整')) {
    return NgaErrorCategory.serverDataIncomplete;
  }
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
        return NgaErrorCategory.network;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
  }
  return text.isEmpty ? NgaErrorCategory.other : NgaErrorCategory.server;
}

/// 面向用户的可读文案：把 NGA 的天书报错（「15:访客不能直接访问」等）
/// 翻译成人话；识别不出的原样透传。
String friendlyNgaErrorMessage(Object? error, {String fallback = '操作失败'}) {
  final text = errorMessage(error, fallback: fallback);
  final category = classifyNgaError(error);
  return switch (category) {
    NgaErrorCategory.loginRequired =>
      text.contains('登录已失效') ||
              text.contains('请重新登录') ||
              text.contains('登录状态已失效')
          ? '登录状态已失效，请重新登录'
          : '该内容需要登录后才能查看，请先登录',
    NgaErrorCategory.riskControl => '触发了站点安全验证，请稍后重试或更换网络环境',
    NgaErrorCategory.rateLimited => '操作过于频繁，请稍后再试',
    NgaErrorCategory.serverDataIncomplete => text,
    NgaErrorCategory.network =>
      error is DioException && error.type == DioExceptionType.connectionError
          ? '网络连接失败，请检查网络后重试'
          : '网络连接超时，请检查网络后重试',
    NgaErrorCategory.server || NgaErrorCategory.other => text,
  };
}
