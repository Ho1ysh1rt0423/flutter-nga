import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/data/entity/topic.dart';
import 'package:flutter_nga/providers/settings/blocklist_settings_provider.dart';
import 'package:flutter_nga/providers/settings/interface_settings_provider.dart';
import 'package:flutter_nga/providers/topic/topic_history_provider.dart';
import 'package:flutter_nga/providers/topic/topic_head_thumbnail_provider.dart';
import 'package:flutter_nga/utils/code_utils.dart' as code_utils;
import 'package:flutter_nga/utils/dimen.dart';
import 'package:flutter_nga/utils/name_utils.dart' as name_utils;
import 'package:flutter_nga/utils/picture_utils.dart' as picture_utils;
import 'package:flutter_nga/ui/widget/photo_preview_launcher.dart';
import 'package:flutter_nga/utils/route.dart';

class TopicListItemWidget extends ConsumerWidget {
  const TopicListItemWidget({
    super.key,
    required this.topic,
    this.blockMode,
    this.onLongPress,
    this.trailing,
  });

  final Topic topic;

  /// 主题被屏蔽时的展示模式，由页面通过 [BlockFilter] 判定；null 表示正常展示
  final BlockMode? blockMode;
  final GestureLongPressCallback? onLongPress;

  /// 行尾操作区（如「更多」菜单按钮），显示在标题右侧
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interfaceState = ref.watch(interfaceSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final topicSubject = code_utils.unescapeHtml(topic.subject);
    // select 只在本帖已读状态变化时重建，集合查找为 O(1)
    final isRead = ref.watch(
      readTopicIdsProvider.select((ids) => ids.contains(topic.tid)),
    );

    // 折叠模式
    if (blockMode == BlockMode.COLLAPSE) {
      return _buildCollapsedCard(context, colorScheme);
    }

    // 隐藏模式：页面通常已通过 BlockFilter.visibleTopics 移除，这里兜底
    if (blockMode == BlockMode.GONE) {
      return const SizedBox.shrink();
    }

    // 计算透明度
    final alpha = blockMode == BlockMode.ALPHA ? 0.38 : 1.0;

    // M3 卡片式列表项：圆角 16 容器 + surfaceContainerLow 底色，块间留白
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _goTopicDetail(context, topic, ref),
          onLongPress: onLongPress,
          child: Opacity(
            opacity: alpha,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                14,
                trailing == null ? 16 : 4,
                14,
              ),
              child: _withTrailing(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    _buildTitle(
                      context,
                      topic,
                      topicSubject,
                      interfaceState,
                      textTheme,
                      colorScheme,
                      isRead: isRead,
                    ),

                    // 配图（最多 3 张，对齐 NGA 原版）
                    if (topic.attachmentUrls.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildAttachmentPreview(
                          context,
                          topic.attachmentUrls,
                        ),
                      ),
                    ] else if (topic.hasAttachment()) ...[
                      // 列表接口没给 attachs（服务端按版块下发），退化为请求主楼首图
                      _buildLazyThumbnail(context, ref, topic),
                    ],

                    const SizedBox(height: 8),

                    // 元信息行
                    _buildMetaRow(context, colorScheme, textTheme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _withTrailing(Widget content) {
    final trailing = this.trailing;
    if (trailing == null) return content;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: content),
        trailing,
      ],
    );
  }

  Widget _buildCollapsedCard(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Text(
            "折叠的屏蔽内容",
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(
    BuildContext context,
    Topic topic,
    String topicSubject,
    InterfaceSettingsState interfaceState,
    TextTheme textTheme,
    ColorScheme colorScheme, {
    required bool isRead,
  }) {
    final isPaintBlockMode = blockMode == BlockMode.PAINT;
    final subjectColor = topic.getSubjectColor();
    // 已读：有标题色的保留色相、降低不透明度，普通标题改用弱色
    final titleColor = isRead
        ? subjectColor?.withValues(alpha: 0.6) ?? colorScheme.onSurfaceVariant
        : subjectColor ?? textTheme.bodyLarge?.color;
    final isDeleteBlockMode = blockMode == BlockMode.DELETE_LINE;

    return Text.rich(
      TextSpan(
        text: topicSubject,
        style: textTheme.titleMedium?.copyWith(
          fontSize: Dimen.titleMedium * interfaceState.titleSizeMultiple,
          backgroundColor: isPaintBlockMode
              ? textTheme.bodyMedium?.color
              : null,
          color: isPaintBlockMode ? Colors.transparent : titleColor,
          fontWeight: topic.isBold() ? FontWeight.bold : FontWeight.normal,
          fontStyle: topic.isItalic() ? FontStyle.italic : FontStyle.normal,
          decoration: isDeleteBlockMode
              ? TextDecoration.lineThrough
              : topic.isUnderline()
              ? TextDecoration.underline
              : null,
          height: interfaceState.lineHeight.size,
        ),
        children: [
          if (topic.parent?.name?.isNotEmpty == true)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code_utils.unescapeHtml(topic.parent!.name!),
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontSize: 10,
                      height: 1,
                    ),
                    // WidgetSpan 已随外层 Text.rich 整体缩放，这里不再重复缩放。
                    textScaler: TextScaler.noScaling,
                  ),
                ),
              ),
            ),
          if (topic.locked())
            TextSpan(
              text: " [锁定]",
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.normal,
              ),
            ),
          if (topic.isAssemble())
            TextSpan(
              text: " [合集]",
              style: textTheme.labelMedium?.copyWith(
                color: colorScheme.tertiary,
                fontWeight: FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  /// 服务端没给列表 `attachs` 时的兜底：异步取主楼配图（最多 3 张）。
  ///
  /// 加载中、没图、请求失败都返回空 —— 列表不留占位，避免滚动时布局跳动。
  Widget _buildLazyThumbnail(BuildContext context, WidgetRef ref, Topic topic) {
    final tid = topic.tid;
    if (tid == null) return const SizedBox.shrink();
    final async = ref.watch(topicHeadThumbnailProvider(tid));
    // 只在拿到数据时显示；loading / error 都当「没有图」，不留占位
    final urls = async is AsyncData<List<String>> ? async.value : null;
    if (urls == null || urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _buildAttachmentPreview(context, urls),
    );
  }

  /// 列表配图：最多 3 张，按 16:10 裁切、圆角，间距均分整行宽度。
  ///
  /// 用 `.thumb.jpg` 缩略图地址，避免列表里直接拉原图（NGA 原图常有数 MB）。
  /// 点击跳到图片预览页，与帖子内图片的交互一致。
  Widget _buildAttachmentPreview(BuildContext context, List<String> urls) {
    // 本卡片展示的配图组（截断到最多 3 张，与渲染一致）
    final galleryUrls = urls.take(Topic.maxListAttachmentCount).toList();
    // 单图限制尺寸（用户反馈全宽 16:10 太大），多图维持均分整行
    if (urls.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 224,
          height: 140,
          child: _attachmentThumb(
            context,
            urls.first,
            galleryUrls: galleryUrls,
          ),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final url in urls.take(Topic.maxListAttachmentCount)) ...[
          Expanded(
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: _attachmentThumb(context, url, galleryUrls: galleryUrls),
            ),
          ),
          if (url != urls.last) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _attachmentThumb(
    BuildContext context,
    String url, {
    required List<String> galleryUrls,
  }) {
    return GestureDetector(
      onTap: () => openPhotoPreview(
        context,
        url,
        // 列表缩略图之间同样可左右切换（同一条帖子的配图构成一组）
        urls: galleryUrls,
        initialIndex: galleryUrls.indexOf(url),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: CachedNetworkImage(
          imageUrl: picture_utils.getThumbUrl(url),
          fit: BoxFit.cover,
          placeholder: (context, url) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (context, url, error) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    BuildContext context,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isPaintBlockMode = blockMode == BlockMode.PAINT;

    return Row(
      children: [
        // 作者
        Icon(
          Icons.person_outline,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            name_utils.getShowName(topic.author ?? ''),
            style: textTheme.bodySmall?.copyWith(
              color: isPaintBlockMode
                  ? Colors.transparent
                  : colorScheme.onSurfaceVariant,
              backgroundColor: isPaintBlockMode
                  ? colorScheme.onSurfaceVariant
                  : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // 附件图标
        if (topic.hasAttachment()) ...[
          Icon(
            Icons.attach_file,
            size: 14,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
        ],

        // 回复数
        Icon(
          Icons.chat_bubble_outline,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          "${topic.replies}",
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),

        const SizedBox(width: 12),

        // 时间
        Icon(Icons.access_time, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          code_utils.formatPostDate(topic.lastPost! * 1000),
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  void _goTopicDetail(BuildContext context, Topic topic, WidgetRef ref) {
    ref
        .read(topicHistoryProvider.notifier)
        .insertHistory(topic.createHistory());
    Routes.navigateTo(
      context,
      "${Routes.TOPIC_DETAIL}?tid=${topic.tid}&fid=${topic.fid}&subject=${topic.subject!}",
    );
  }
}
