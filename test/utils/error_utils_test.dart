import 'package:dio/dio.dart';
import 'package:flutter_nga/utils/error_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('errorMessage', () {
    test('returns fallback for null and blank strings', () {
      expect(errorMessage(null), '操作失败');
      expect(errorMessage(''), '操作失败');
      expect(errorMessage('   '), '操作失败');
      expect(errorMessage(null, fallback: '自定义'), '自定义');
    });

    test('returns plain strings as-is', () {
      expect(errorMessage('网络错误'), '网络错误');
    });

    test('prefers DioException.error over message', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/test'),
        error: '服务器拒绝访问',
        message: 'ignored message',
        type: DioExceptionType.unknown,
      );
      expect(errorMessage(error), '服务器拒绝访问');
    });

    test('falls back to DioException.message when error is empty', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/test'),
        message: '连接超时',
        type: DioExceptionType.connectionTimeout,
      );
      expect(errorMessage(error), '连接超时');
    });

    test('falls back to statusMessage when error and message are empty', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 503,
          statusMessage: 'Service Unavailable',
        ),
        type: DioExceptionType.badResponse,
      );
      expect(errorMessage(error), 'Service Unavailable');
    });

    test('uses Exception.toString for generic exceptions', () {
      expect(errorMessage(Exception('boom')), 'Exception: boom');
    });
  });

  group('classifyNgaError', () {
    test('访客/未登录类报错归为 loginRequired', () {
      expect(classifyNgaError('15:访客不能直接访问'), NgaErrorCategory.loginRequired);
      expect(classifyNgaError('请先登录'), NgaErrorCategory.loginRequired);
      expect(classifyNgaError('登录状态已失效，请重新登录'), NgaErrorCategory.loginRequired);
    });

    test('风控/频率/截断/网络各归各类', () {
      expect(classifyNgaError('触发安全验证'), NgaErrorCategory.riskControl);
      expect(classifyNgaError('操作过于频繁'), NgaErrorCategory.rateLimited);
      expect(
        classifyNgaError('NGA 服务端返回的数据不完整'),
        NgaErrorCategory.serverDataIncomplete,
      );
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(classifyNgaError(timeout), NgaErrorCategory.network);
      final connection = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(classifyNgaError(connection), NgaErrorCategory.network);
      expect(classifyNgaError('服务器拒绝访问'), NgaErrorCategory.server);
    });
  });

  group('friendlyNgaErrorMessage', () {
    test('天书报错翻译成人话', () {
      expect(friendlyNgaErrorMessage('15:访客不能直接访问'), '该内容需要登录后才能查看，请先登录');
      expect(friendlyNgaErrorMessage('登录状态已失效，请重新登录'), '登录状态已失效，请重新登录');
      expect(friendlyNgaErrorMessage('触发安全验证'), '触发了站点安全验证，请稍后重试或更换网络环境');
      expect(friendlyNgaErrorMessage('操作过于频繁'), '操作过于频繁，请稍后再试');
    });

    test('超时/断网给可操作建议', () {
      final timeout = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(friendlyNgaErrorMessage(timeout), '网络连接超时，请检查网络后重试');
      final connection = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(friendlyNgaErrorMessage(connection), '网络连接失败，请检查网络后重试');
    });

    test('识别不出的报错原样透传', () {
      expect(friendlyNgaErrorMessage('服务器拒绝访问'), '服务器拒绝访问');
      expect(friendlyNgaErrorMessage(null), '操作失败');
    });

    test('截断类保留原提示（已足够明确）', () {
      expect(
        friendlyNgaErrorMessage('NGA 服务端返回的数据不完整，稍等片刻下拉刷新即可'),
        'NGA 服务端返回的数据不完整，稍等片刻下拉刷新即可',
      );
    });
  });
}
