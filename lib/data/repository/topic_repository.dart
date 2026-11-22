import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart';
import 'package:sembast/sembast.dart';
import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_nga/data/entity/toggle_like_reaction.dart';
import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/data/entity/topic_detail.dart';
import 'package:flutter_nga/data/entity/topic_history.dart';
import 'package:flutter_nga/data/entity/topic_tag.dart';
import 'package:flutter_nga/utils/code_utils.dart' as code_utils;
import 'package:flutter_nga/utils/parser/html_topic_detail_parser.dart';

abstract class TopicRepository {
  Future<TopicListData> getTopicList({
    int? fid,
    int? authorid,
    int? page,
    bool recommend = false,
    int? type = 0,
  });

  Future<dynamic> getUserReplies(int authorid, int page);

  Future<TopicDetailData> getTopicDetail(int tid, int page, int? authorid);

  /// 只取主楼首图，列表缩略图兜底用。
  ///
  /// 服务端只在部分版块给列表接口下发 `attachs`，剑斗绮谭这类版块拿不到，
  /// 于是对「标记了带附件（type & 8192）但列表没给图」的帖子单独请求主楼。
  /// 用 `pid=0` 只拿一楼，响应约 3KB。
  Future<List<String>> getTopicHeadImageUrls(int tid);

  /// 已取到的列表配图（tid → URL 列表），进程重启后回灌，避免重新请求。
  /// 只存成功结果；取不到图 / 请求失败留在内存缓存里即可。
  Future<Map<int, List<String>>> loadHeadThumbnailCache();

  /// 落盘一条配图结果（upsert，失败静默——缓存是锦上添花）。
  Future<void> saveHeadThumbnail(int tid, List<String> urls);

  Future<TopicDetailData> getTopicReplies(int? pid);

  Future<TopicListData> getFavouriteTopicList(int page);

  Future<String?> addFavouriteTopic(int? tid);

  Future<String?> deleteFavouriteTopic(int? tid, int? page);

  Future<List<TopicTag>> getTopicTagList(int fid);

  Future<String?> getAuthCode(int? fid, int? tid, String action);

  Future<Map<String, dynamic>> uploadAttachment(
    int? fid,
    String? authCode,
    String filePath,
  );

  Future<String?> checkCreateTopic(int fid);

  Future<String> createTopic(
    int? fid,
    String subject,
    String content,
    bool isAnonymous,
    String attachments,
    String attachmentsCheck,
  );

  Future<String> createReply(
    int? tid,
    int? fid,
    String subject,
    String content,
    bool isAnonymous,
    String attachments,
    String attachmentsCheck,
  );

  Future<ToggleLikeReaction> likeReply(int? tid, int? pid);

  Future<ToggleLikeReaction> dislikeReply(int? tid, int? pid);

  Future<TopicListData> searchTopic(
    String keyword,
    int? fid,
    bool content,
    int? page,
  );

  Future<int> insertTopicHistory(TopicHistory history);

  Future<List<TopicHistory>> getTopicHistories(int limit, int offset);

  /// 浏览历史中出现过的全部 tid，用于列表标记已读
  Future<Set<int>> getHistoryTopicIds();

  Future deleteTopicHistoryById(int id);

  Future<int> deleteAllTopicHistory();
}

class TopicDataRepository implements TopicRepository {
  static const _RESULT_START_TAG = "<span style='color:#aaa'>&gt;</span>";
  static const _RESULT_END_TAG = "<br/>";

  TopicDataRepository(this.database, this._dio);

  final Database database;
  final Dio _dio;

  StoreRef<int, dynamic> get _store {
    _lateInitStore ??= intMapStoreFactory.store('topic_histories');
    return _lateInitStore!;
  }

  StoreRef<int, dynamic>? _lateInitStore;

  StoreRef<int, dynamic> get _headThumbnailStore {
    _lateHeadThumbnailStore ??= intMapStoreFactory.store(
      'topic_head_thumbnails',
    );
    return _lateHeadThumbnailStore!;
  }

  StoreRef<int, dynamic>? _lateHeadThumbnailStore;

  @override
  Future<TopicListData> getTopicList({
    int? fid,
    int? authorid,
    int? page,
    bool recommend = false,
    int? type = 0,
  }) async {
    try {
      var params = "__output=8";
      if (fid != null) {
        params += type == 1 ? "&stid=$fid" : "&fid=$fid";
      }
      if (authorid != null) {
        params += "&authorid=$authorid";
      }
      if (page != null) {
        params += "&page=$page";
      }
      if (recommend) {
        params += "&recommend=1&order_by=postdatedesc";
      }
      Response<Map<String, dynamic>> response = await _dio.get(
        "thread.php?$params",
      );
      return TopicListData.fromJson(response.data!, page);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<dynamic> getUserReplies(int authorid, int page) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "thread.php?__output=8&searchpost=1&authorid=$authorid&page=$page",
      );
      return TopicListData.fromJson(response.data!, page);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<TopicListData> getFavouriteTopicList(int page) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "thread.php?favor=1&__output=8&page=$page",
      );
      return TopicListData.fromJson(response.data!, page);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String?> addFavouriteTopic(int? tid) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php?__lib=topic_favor&__output=8&__act=topic_favor&action=add&tid=$tid",
      );
      return response.data!['0'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String?> deleteFavouriteTopic(int? tid, int? page) async {
    try {
      final postData =
          "__output=8"
          "&__lib=topic_favor"
          "&__act=topic_favor"
          "&action=del"
          "&page=$page"
          "&tidarray=$tid";
      final options = Options()
        ..contentType = Headers.formUrlEncodedContentType;
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php",
        data: postData,
        options: options,
      );
      return response.data!['0'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<TopicDetailData> getTopicDetail(
    int tid,
    int page,
    int? authorid,
  ) async {
    try {
      // 允许「截断抢救」：NGA 源站偶发把响应在中途截断（重试也不恢复），把
      // 已写完整的楼层抢出来总比整页报错强。抢救出的数据带 truncated 标记，
      // 界面会提示「内容不完整」并禁用翻页（详见 TopicDetailData.maxPage）。
      final Response<Map<String, dynamic>> response = await _dio.get(
        "read.php?__output=8&tid=$tid&page=$page${authorid == null ? "" : "&authorid=$authorid"}",
        options: Options(
          extra: {NgaDioConfigurator.allowTruncatedRepairKey: true},
        ),
      );
      final repaired =
          response.requestOptions.extra[NgaDioConfigurator
              .truncatedRepairedKey] ==
          true;
      if (repaired) {
        // 抢救出的数据不完整。官方 App 详情页走 __output=17（服务端渲染的
        // HTML 骨架，另一条序列化路径），截断发生在 8 通道时它通常还是好的
        // ——尝试回退拿完整数据，拿不到再用抢救的部分。
        try {
          final fallback = await _getTopicDetailViaHtmlChannel(
            tid: tid,
            page: page,
            authorid: authorid,
          );
          if (fallback != null) return fallback;
        } catch (_) {
          // 回退失败：继续用抢救出的部分数据
        }
      }
      return TopicDetailData.fromJson(response.data!, truncated: repaired);
    } catch (err) {
      if (_isTruncationReject(err)) {
        try {
          final fallback = await _getTopicDetailViaHtmlChannel(
            tid: tid,
            page: page,
            authorid: authorid,
          );
          if (fallback != null) return fallback;
        } catch (_) {
          // 回退也失败：抛出原始的截断错误（提示语更明确）
        }
      }
      rethrow;
    }
  }

  /// 官方 App 详情页用的输出格式（逆向自官方 APK）：服务端渲染的楼层骨架
  /// + 原始 UBB，与 __output=8 的 JSON 序列化是不同代码路径。
  Future<TopicDetailData?> _getTopicDetailViaHtmlChannel({
    required int tid,
    required int page,
    int? authorid,
  }) async {
    final Response<Map<String, dynamic>> response = await _dio.get(
      "read.php?tid=$tid&page=$page${authorid == null ? "" : "&authorid=$authorid"}&__localres=1&__output=17",
      options: Options(extra: {NgaDioConfigurator.htmlChannelKey: true}),
    );
    return parseHtmlTopicDetail(response.data!, tid: tid, page: page);
  }

  bool _isTruncationReject(Object? err) =>
      err is DioException &&
      err.requestOptions.extra[NgaDioConfigurator.truncationRejectedKey] ==
          true &&
      err.requestOptions.extra[NgaDioConfigurator.htmlChannelKey] != true;

  @override
  Future<List<String>> getTopicHeadImageUrls(int tid) async {
    // pid=0 只返回主楼，实测响应约 2.8KB（整页 8~15KB），专门给列表缩略图用。
    // 允许「截断抢救」且重试上限为 0：抢救出的主楼已够用，重试只会让
    // 串行队列每个截断的 tid 多白等 3.4 秒。
    final Response<Map<String, dynamic>> response = await _dio.get(
      "read.php?__output=8&tid=$tid&pid=0",
      options: Options(
        extra: {
          NgaDioConfigurator.allowTruncatedRepairKey: true,
          NgaDioConfigurator.truncationMaxRetriesKey: 0,
        },
      ),
    );
    final data = response.data;
    if (data == null) return const [];
    final rows = data["__R"];
    if (rows is! Map) return const [];
    for (final value in rows.values) {
      if (value is! Map) continue;
      // 主楼：pid / lou 都是 0。服务端偶尔不带这两个字段，那就整页只有一楼
      final pid = value["pid"];
      final lou = value["lou"];
      if (pid != null && pid != 0) continue;
      if (lou != null && lou != 0) continue;
      final urls = Topic.parseListAttachmentUrls(value["attachs"]);
      if (urls.isNotEmpty) return urls;
    }
    return const [];
  }

  @override
  Future<Map<int, List<String>>> loadHeadThumbnailCache() async {
    try {
      final records = await _headThumbnailStore.find(database);
      final result = <int, List<String>>{};
      for (final record in records) {
        final value = record.value;
        if (value is List) {
          // 当前格式：URL 列表
          final urls = value
              .whereType<String>()
              .where((url) => url.isNotEmpty)
              .toList();
          if (urls.isNotEmpty) result[record.key] = urls;
        } else if (value is String && value.isNotEmpty) {
          // 旧格式：单条 URL 字符串
          result[record.key] = [value];
        }
      }
      return result;
    } catch (err) {
      // 持久层坏了当作没有缓存，列表缩略图回退到正常请求
      return const {};
    }
  }

  @override
  Future<void> saveHeadThumbnail(int tid, List<String> urls) async {
    try {
      await _headThumbnailStore.record(tid).put(database, urls);
    } catch (_) {
      // 缓存写失败不影响功能
    }
  }

  @override
  Future<TopicDetailData> getTopicReplies(int? pid) async {
    try {
      // 与 getTopicDetail 同理允许截断抢救：调用方（热评展开 / 回复详情弹窗）
      // 只消费 replyList / userList，缺总览字段不影响使用。
      final Response<Map<String, dynamic>> response = await _dio.get(
        "read.php?__output=8&pid=$pid",
        options: Options(
          extra: {NgaDioConfigurator.allowTruncatedRepairKey: true},
        ),
      );
      final repaired =
          response.requestOptions.extra[NgaDioConfigurator
              .truncatedRepairedKey] ==
          true;
      if (repaired) {
        // 同 getTopicDetail：抢救数据不完整时尝试官方 HTML 通道
        try {
          final fallback = await _getTopicRepliesViaHtmlChannel(pid: pid);
          if (fallback != null) return fallback;
        } catch (_) {
          // 回退失败：继续用抢救出的部分数据
        }
      }
      return TopicDetailData.fromJson(response.data!, truncated: repaired);
    } catch (err) {
      if (_isTruncationReject(err)) {
        try {
          final fallback = await _getTopicRepliesViaHtmlChannel(pid: pid);
          if (fallback != null) return fallback;
        } catch (_) {
          // 回退也失败：抛出原始的截断错误
        }
      }
      rethrow;
    }
  }

  /// pid 定位单楼的场景官方 HTML 通道同样支持（实测返回单层骨架）。
  Future<TopicDetailData?> _getTopicRepliesViaHtmlChannel({
    required int? pid,
  }) async {
    final Response<Map<String, dynamic>> response = await _dio.get(
      "read.php?pid=$pid&__localres=1&__output=17",
      options: Options(extra: {NgaDioConfigurator.htmlChannelKey: true}),
    );
    return parseHtmlTopicDetail(response.data!, tid: 0, page: 1);
  }

  @override
  Future<List<TopicTag>> getTopicTagList(int fid) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "nuke.php?fid=$fid&__output=8&__lib=topic_key&__act=get",
      );
      List<TopicTag> list = [];
      Map<String, dynamic> tagMap = response.data!["0"];
      tagMap.forEach((k, v) {
        list.add(TopicTag(id: int.tryParse(k)!, content: v["0"]));
      });
      return list;
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String?> getAuthCode(int? fid, int? tid, String action) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "post.php?__output=8&fid=$fid${tid != null ? "&tid=$tid" : ""}&action=$action",
      );
      return response.data!["auth"];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> uploadAttachment(
    int? fid,
    String? authCode,
    String filePath,
  ) async {
    try {
      final fileName = basename(filePath);
      final formData = FormData.fromMap({
        "attachment_file1": await MultipartFile.fromFile(
          filePath,
          filename: fileName,
        ),
        "attachment_file1_url_utf8_name": fileName,
        "fid": "$fid",
        "auth": authCode,
        "func": "upload",
        // "v2": "1",
        "__output": "11",
        // 1 是自动缩图
        "attachment_file1_auto_size": "",
        //水印位置tl/tr/bl/br 左上右上左下右下 不设为无水印
        "attachment_file1_watermark": "",
        "attachment_file1_dscp": "",
        "attachment_file1_img": "1",
        "origin_domain": "bbs.ngacn.cc",
        "noprefix": "",
      });
      Response<Map<String, dynamic>> response = await _dio.post(
        "https://img8.nga.cn/attach.php",
        data: formData,
      );
      debugPrint(response.toString());
      return response.data!;
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String?> checkCreateTopic(int fid) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "nuke.php?fid=$fid&__output=8&action=new",
      );
      return response.data!['auth'];
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String> createTopic(
    int? fid,
    String subject,
    String content,
    bool isAnonymous,
    String attachments,
    String attachmentsCheck,
  ) async {
    final postData =
        "step=2"
        "&post_content=${code_utils.urlEncode(content)}"
        "&action=new"
        "&post_subject=${code_utils.urlEncode(subject)}"
        "&fid=$fid${isAnonymous ? "anony=1" : ""}"
        "${!code_utils.isStringEmpty(attachments) ? "&attachments=$attachments" : ""}"
        "${!code_utils.isStringEmpty(attachmentsCheck) ? "&attachments_check=$attachmentsCheck" : ""}";
    try {
      final options = Options()
        ..contentType = Headers.formUrlEncodedContentType;
      Response<String> response = await _dio.post(
        "post.php",
        data: postData,
        options: options,
      );
      final html = response.data!;
      int start = html.indexOf(_RESULT_START_TAG);
      if (start == -1) return "发帖失败";
      start += _RESULT_START_TAG.length;
      int end = html.indexOf(_RESULT_END_TAG, start);
      if (end < 0) return "发帖失败";
      return html.substring(start, end);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<String> createReply(
    int? tid,
    int? fid,
    String subject,
    String content,
    bool isAnonymous,
    String attachments,
    String attachmentsCheck,
  ) async {
    final postData =
        "step=2"
        "&post_content=${code_utils.urlEncode(content)}"
        "&tid=$tid"
        "&action=reply"
        "&post_subject=${code_utils.urlEncode(subject)}"
        "&fid=$fid${isAnonymous ? "anony=1" : ""}"
        "${!code_utils.isStringEmpty(attachments) ? "&attachments=$attachments" : ""}"
        "${!code_utils.isStringEmpty(attachmentsCheck) ? "&attachments_check=$attachmentsCheck" : ""}";
    try {
      final options = Options();
      options.contentType = Headers.formUrlEncodedContentType;
      Response<String> response = await _dio.post(
        "post.php",
        data: postData,
        options: options,
      );
      final html = response.data!;
      int start = html.indexOf(_RESULT_START_TAG);
      if (start == -1) return "发帖失败";
      start += _RESULT_START_TAG.length;
      int end = html.indexOf(_RESULT_END_TAG, start);
      if (end < 0) return "发帖失败";
      return html.substring(start, end);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<ToggleLikeReaction> likeReply(int? tid, int? pid) async {
    final postData =
        "__output=8&__lib=topic_recommend&__act=add&raw=3&pid=$pid&value=1&tid=$tid";
    try {
      final options = Options();
      options.contentType = Headers.formUrlEncodedContentType;
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php",
        data: postData,
        options: options,
      );
      return ToggleLikeReaction.fromJson(response.data!);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<ToggleLikeReaction> dislikeReply(int? tid, int? pid) async {
    final postData =
        "__output=8&__lib=topic_recommend&__act=add&raw=3&pid=$pid&value=-1&tid=$tid";
    try {
      final options = Options();
      options.contentType = Headers.formUrlEncodedContentType;
      Response<Map<String, dynamic>> response = await _dio.post(
        "nuke.php",
        data: postData,
        options: options,
      );
      return ToggleLikeReaction.fromJson(response.data!);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<TopicListData> searchTopic(
    String keyword,
    int? fid,
    bool content,
    int? page,
  ) async {
    try {
      Response<Map<String, dynamic>> response = await _dio.get(
        "thread.php?${fid == null ? "" : "fid=$fid&"}key=$keyword&page=$page${content ? "&content=1" : ""}&__output=8",
      );
      return TopicListData.fromJson(response.data!, page);
    } catch (err) {
      rethrow;
    }
  }

  @override
  Future<int> insertTopicHistory(TopicHistory history) async {
    final finder = Finder(
      limit: 1,
      offset: 0,
      filter: Filter.equals('tid', history.tid),
      sortOrders: [SortOrder('time', false)],
    );
    RecordSnapshot<int, dynamic>? record = await _store
        .query(finder: finder)
        .getSnapshot(database);
    if (record != null) {
      final latest = TopicHistory.fromJson(record.value)..id = record.key;
      final latestDate = DateTime.fromMicrosecondsSinceEpoch(latest.time!);
      final historyDate = DateTime.fromMicrosecondsSinceEpoch(history.time!);
      if (latestDate.difference(historyDate).inDays == 0) {
        history.id = latest.id;
        return _store.update(database, history.toJson(), finder: finder);
      }
    }
    return _store.add(database, history.toJson());
  }

  @override
  Future<List<TopicHistory>> getTopicHistories(int limit, int offset) async {
    List<RecordSnapshot<int, dynamic>> results = await _store.find(
      database,
      finder: Finder(
        limit: limit,
        offset: offset,
        sortOrders: [SortOrder('time', false)],
      ),
    );
    return results
        .map((map) => TopicHistory.fromJson(map.value)..id = map.key)
        .toList();
  }

  @override
  Future<Set<int>> getHistoryTopicIds() async {
    final records = await _store.find(database);
    return {
      for (final record in records)
        if (record.value is Map && record.value['tid'] is int)
          record.value['tid'] as int,
    };
  }

  @override
  Future deleteTopicHistoryById(int id) async {
    return _store.record(id).delete(database);
  }

  @override
  Future<int> deleteAllTopicHistory() {
    return _store.delete(database);
  }
}
