import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_nga/data/entity/topic_detail.dart';

/// 主楼 + 1 楼的完整响应骨架。
Map<String, dynamic> _fullDetail() => {
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

/// 一个内联热评对象（取真实响应里的字段形状）。
Map<String, dynamic> _inlineHot(int pid, int lou, String content) => {
  'pid': pid,
  'fid': 7,
  'tid': 1,
  'authorid': 66496004,
  'type': 0,
  'score': 448,
  'score_2': 0,
  'recommend': 0,
  'postdate': '2026-11-14 09:26',
  'subject': '',
  'alterinfo': '',
  'content': content,
  'lou': lou,
  'content_length': 93,
  'from_client': '100 /',
  'postdatetimestamp': 1794619560,
};

void main() {
  group('内联热评（__R.0.hotreply）', () {
    test('解析出正文、楼层号与作者', () {
      final map = _fullDetail();
      (map['__R'] as Map)['0'] = {
        'pid': 0,
        'lou': 0,
        'content': '主楼',
        'hotreply': {
          '0': _inlineHot(887851598, 3, '大秘里就一堆这种离谱的机制'),
          '1': _inlineHot(887852144, 13, '第二条热评'),
        },
      };

      final data = TopicDetailData.fromJson(map);

      expect(data.hotReplyList.length, 2);
      expect(data.hotReplyList[0].pid, 887851598);
      expect(data.hotReplyList[0].content, '大秘里就一堆这种离谱的机制');
      // 真实楼层号：pid 通道返回的 lou 恒为 0，内联的才是准的。
      expect(data.hotReplyList[0].lou, 3);
      expect(data.hotReplyList[1].lou, 13);
      expect(data.hotReplyList[0].authorId, 66496004);
    });

    test('内联热评带附件时一并解析', () {
      final map = _fullDetail();
      (map['__R'] as Map)['0'] = {
        'pid': 0,
        'lou': 0,
        'content': '主楼',
        'hotreply': {
          '0': {
            ..._inlineHot(887065464, 6, '带图的热评'),
            'attachs': {
              '0': {'attachurl': 'mon_202611/25/7Q95-abc.jpg', 'type': 'img'},
            },
          },
        },
      };

      final data = TopicDetailData.fromJson(map);

      expect(data.hotReplyList.single.attachmentList, hasLength(1));
    });

    test('没有 hotreply 键时为空列表，不崩', () {
      final data = TopicDetailData.fromJson(_fullDetail());
      expect(data.hotReplyList, isEmpty);
    });

    test('hotreply 为 [] （服务端空关联数组编码）时为空列表，不崩', () {
      final map = _fullDetail();
      (map['__R'] as Map)['0'] = {
        'pid': 0,
        'lou': 0,
        'content': '主楼',
        'hotreply': <dynamic>[],
      };

      final data = TopicDetailData.fromJson(map);

      expect(data.hotReplyList, isEmpty);
      expect(data.replyList.length, 2, reason: '楼层不能被热评解析影响');
    });

    test('hotreply 是字符串等变型值时为空列表，不崩', () {
      final map = _fullDetail();
      (map['__R'] as Map)['0'] = {
        'pid': 0,
        'lou': 0,
        'content': '主楼',
        'hotreply': 'not-a-map',
      };

      expect(TopicDetailData.fromJson(map).hotReplyList, isEmpty);
    });
  });

  group('热评 pid 列表（__T.post_misc_var["17"]）', () {
    Map<String, dynamic> withMisc(dynamic misc) {
      final map = _fullDetail();
      (map['__T'] as Map)['post_misc_var'] = misc;
      return map;
    }

    test('逗号串照旧解析出 pid 列表（与内联数据并存）', () {
      final map = withMisc({'17': ',887851598,887852144'});
      (map['__R'] as Map)['0'] = {
        'pid': 0,
        'lou': 0,
        'content': '主楼',
        'hotreply': {'0': _inlineHot(887851598, 3, '热评')},
      };

      final data = TopicDetailData.fromJson(map);

      expect(data.hotReplies, [887851598, 887852144], reason: 'pid 列表语义不变');
      expect(data.hotReplyList.single.pid, 887851598, reason: '内联数据也保留');
    });

    test('"17" 是 int 等非 String 时当作没有，不抛类型转换错误', () {
      // 旧实现是 `String hots = topicMisc["17"]`，这里会崩。
      final data = TopicDetailData.fromJson(withMisc({'17': 12345}));
      expect(data.hotReplies, isEmpty);
    });

    test('post_misc_var 是 [] 时当作空，不抛 FormatException', () {
      // 旧实现用 asJsonMapOrNull，它只容忍 null，遇 [] 会抛。
      expect(
        () => TopicDetailData.fromJson(withMisc(<dynamic>[])),
        returnsNormally,
      );
      expect(
        TopicDetailData.fromJson(withMisc(<dynamic>[])).hotReplies,
        isEmpty,
      );
    });

    test('post_misc_var 是字符串时当作空，不抛 FormatException', () {
      expect(TopicDetailData.fromJson(withMisc('garbage')).hotReplies, isEmpty);
    });

    test('缺 post_misc_var / 缺 __T 时都为空的 pid 列表', () {
      expect(TopicDetailData.fromJson(_fullDetail()).hotReplies, isEmpty);

      final noTopic = _fullDetail()..remove('__T');
      expect(TopicDetailData.fromJson(noTopic).hotReplies, isEmpty);
    });
  });
}
