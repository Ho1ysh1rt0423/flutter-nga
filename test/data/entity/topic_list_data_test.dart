import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/entity/topic.dart';

void main() {
  group('TopicListData.maxPage', () {
    Map<String, dynamic> map({dynamic rows, dynamic rRows}) => {
      '__T': <String, dynamic>{},
      '__F': <String, dynamic>{},
      '__ROWS': ?rows,
      '__R__ROWS_PAGE': ?rRows,
    };

    test('总页数 = ceil(rows / 每页行数)，含尾页', () {
      final data = TopicListData.fromJson(map(rows: 71, rRows: 35), 1);
      expect(data.maxPage, 3, reason: '71 条、每页 35 条 = 3 页');
    });

    test('整除时不多出一页', () {
      final data = TopicListData.fromJson(map(rows: 70, rRows: 35), 1);
      expect(data.maxPage, 2);
    });

    test('截断抢救缺 __ROWS 时回退 1，不抛异常', () {
      final data = TopicListData.fromJson(map(rRows: 35), 1);
      expect(data.maxPage, 1);
    });

    test('缺 __R__ROWS_PAGE 时回退 1，不抛 TypeError / 除零', () {
      final data = TopicListData.fromJson(map(rows: 100), 1);
      expect(data.maxPage, 1);
    });

    test('__ROWS 为空串或 0 时回退 1', () {
      expect(TopicListData.fromJson(map(rows: '', rRows: 35), 1).maxPage, 1);
      expect(TopicListData.fromJson(map(rows: 0, rRows: 35), 1).maxPage, 1);
    });
  });
}
