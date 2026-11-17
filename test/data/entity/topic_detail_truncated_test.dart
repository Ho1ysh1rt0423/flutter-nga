import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> fullDetail() => {
    '__R': {
      '0': {'pid': 0, 'lou': 0, 'content': '主楼'},
      '1': {'pid': 11, 'lou': 1, 'content': '第 1 楼'},
    },
    '__U': {},
    '__T': {'tid': 1, 'subject': '标题'},
    '__ROWS': 42,
    '__R__ROWS': 20,
    '__R__ROWS_PAGE': 20,
  };

  test('full data computes maxPage from rows', () {
    final data = TopicDetailData.fromJson(fullDetail());
    expect(data.truncated, isFalse);
    expect(data.rows, 42);
    expect(data.replyPageRows, 20);
    expect(data.maxPage, 3);
  });

  test('truncated data without overview fields stays parseable', () {
    // 截断抢救出的数据：楼层完整，但 __ROWS / __R__ROWS_PAGE 在截断点之后，
    // 全部缺失。之前直接 `map["__ROWS"]` 赋给 int 字段会抛 TypeError。
    final map = fullDetail()..remove('__ROWS')..remove('__R__ROWS_PAGE');
    final data = TopicDetailData.fromJson(map, truncated: true);

    expect(data.truncated, isTrue);
    expect(data.rows, 0);
    expect(data.replyPageRows, 0);
    expect(data.replyList.length, 2, reason: '已写完整的楼层必须保留');
    expect(data.topic?.subject, '标题');
  });

  test('repaired data without __T keeps floors and yields a null topic', () {
    // 真实案例（2026-11-18）：NGA 的响应里 __T 排在 __R 之后，截断点落在
    // 后半段时抢救出的数据只有楼层。之前 asJsonMap(null) 直接抛
    // FormatException: JSON TopicDetailData.__T 期望 Map，整页报错。
    final map = fullDetail()
      ..remove('__ROWS')
      ..remove('__R__ROWS_PAGE')
      ..remove('__T')
      ..remove('__U');
    final data = TopicDetailData.fromJson(map, truncated: true);

    expect(data.truncated, isTrue);
    expect(data.topic, isNull, reason: '__T 缺失时主题信息为空，标题回落到路由参数');
    expect(data.replyList.length, 2, reason: '楼层仍然全部保留');
    expect(data.userList, isEmpty);
    expect(data.hotReplies, isEmpty, reason: '没有 __T 就没有热评配置');
    expect(data.maxPage, 1);
  });

  test('truncated or zero overview fields make maxPage fall back to 1', () {
    final map = fullDetail()..remove('__ROWS')..remove('__R__ROWS_PAGE');
    expect(TopicDetailData.fromJson(map, truncated: true).maxPage, 1,
        reason: '页数不可信时回退为当前页，禁用向后翻页');
    expect(TopicDetailData.fromJson(map, truncated: false).maxPage, 1,
        reason: '总览字段为 0 时同样无页可算，避免除零抛异常');
  });

  test('non-integer overview values are tolerated', () {
    // 服务端偶发把数字字段下发成字符串
    final map = fullDetail()
      ..['__ROWS'] = '42'
      ..['__R__ROWS_PAGE'] = '20';
    final data = TopicDetailData.fromJson(map);
    expect(data.maxPage, 3);
  });
}
