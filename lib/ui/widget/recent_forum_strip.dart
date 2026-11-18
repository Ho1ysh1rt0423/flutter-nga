import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/entity/recent_forum.dart';
import 'package:flutter_nga/providers/forum/recent_forum_provider.dart';
import 'package:flutter_nga/utils/dimen.dart';
import 'package:flutter_nga/utils/route.dart';

/// 首页顶部的「最近访问」横向快捷条。
///
/// 没有访问记录时整块不占位（返回 shrink），避免把收藏宫格挤下去。
class RecentForumStrip extends ConsumerWidget {
  const RecentForumStrip({super.key});

  static const double _iconSize = 44;
  static const double _itemWidth = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forums = ref.watch(
      recentForumProvider.select((state) => state.forums),
    );
    if (forums.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dimen.spacingL, 12, 8, 4),
          child: Row(
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '最近访问',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _confirmClear(context, ref),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: _iconSize + 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Dimen.spacingL),
            itemCount: forums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) =>
                _buildItem(context, forums[index], colorScheme, textTheme),
          ),
        ),
        Divider(height: 1, color: colorScheme.surfaceContainerHighest),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    RecentForum recent,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final forum = recent.forum;
    return SizedBox(
      width: _itemWidth,
      child: InkWell(
        borderRadius: BorderRadius.circular(Dimen.radiusL),
        onTap: () => Routes.navigateTo(
          context,
          "${Routes.FORUM_DETAIL}?fid=${forum.fid}&name=${Uri.encodeComponent(forum.name)}&type=${forum.type}",
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              SizedBox(
                width: _iconSize,
                height: _iconSize,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Dimen.radiusL),
                  child: CachedNetworkImage(
                    imageUrl: forum.getIconUrl(),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _fallbackIcon(colorScheme),
                    errorWidget: (context, url, err) =>
                        _fallbackIcon(colorScheme),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                forum.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.forum_outlined,
        size: 20,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提示'),
        content: const Text('清空最近访问记录？'),
        actions: [
          TextButton(
            onPressed: () => Routes.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(recentForumProvider.notifier).clear();
  }
}
