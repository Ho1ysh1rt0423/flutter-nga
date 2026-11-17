import 'dart:convert';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('repairTruncatedJson', () {
    test('keeps whole floors and closes the brackets', () {
      // 真实形态：第 1 楼写到 authorid 中途就断了
      const truncated =
          '{"data":{"__R":{"0":{"pid":0,"content":"主楼"},"1":{"pid":888226851,"authorid":672';

      final repaired = NgaDioConfigurator.repairTruncatedJson(truncated);

      expect(repaired, isNotNull);
      final decoded = json.decode(repaired!) as Map<String, dynamic>;
      final rows = (decoded['data'] as Map<String, dynamic>)['__R'] as Map;
      expect(rows.keys, ['0']);
      expect((rows['0'] as Map)['content'], '主楼');
    });

    test('ignores braces inside strings', () {
      const truncated =
          '{"data":{"__R":{"0":{"content":"a{b}c\\"d"}}}},"__PAGE":1,"__T":{"0":{"subject":"x';

      final repaired = NgaDioConfigurator.repairTruncatedJson(truncated);

      expect(repaired, isNotNull);
      // 已经闭合到 __T 之前，补括号后必须仍是合法 JSON
      expect(() => json.decode(repaired!), returnsNormally);
    });

    test('returns null when nothing is closed yet', () {
      const truncated = '{"data":{"__R":{"0":{"content":"还没结束的字符串';
      expect(NgaDioConfigurator.repairTruncatedJson(truncated), isNull);
    });

    test('a complete json stays parseable', () {
      const complete = '{"data":{"__R":{"0":{"pid":0}}}}';
      // 完整 JSON 不会被这一步破坏：要么返回 null，要么返回等价内容。
      // （它只在 JSON 解析失败的路径上被调用，这里只是守住"不会越修越坏"。）
      final repaired = NgaDioConfigurator.repairTruncatedJson(complete);
      if (repaired != null) {
        expect(json.decode(repaired), json.decode(complete));
      }
    });
  });
}
