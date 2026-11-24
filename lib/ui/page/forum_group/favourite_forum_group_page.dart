import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/entity/forum.dart';
import 'package:flutter_nga/providers/forum/favourite_forum_list_provider.dart';
import 'package:flutter_nga/providers/forum/favourite_forum_provider.dart';
import 'package:flutter_nga/ui/widget/forum_grid_item_widget.dart';
import 'package:flutter_nga/ui/widget/m3_dialog.dart';
import 'package:flutter_nga/ui/widget/recent_forum_strip.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/hooks/easy_refresh_hooks.dart';
import 'package:flutter_nga/utils/hooks/scroll_to_top.dart';

class FavouriteForumGroupPage extends StatefulHookConsumerWidget {
  const FavouriteForumGroupPage({super.key, this.scrollToTop});

  final ScrollToTopSignal? scrollToTop;

  @override
  ConsumerState<FavouriteForumGroupPage> createState() =>
      _FavouriteForumGroupState();
}

class _FavouriteForumGroupState extends ConsumerState<FavouriteForumGroupPage> {
  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(favouriteForumListProvider.notifier);
    final scrollController = useScrollToTopController(widget.scrollToTop);
    usePostFrameEffect(() {
      notifier.refresh().catchError(AppToast.error);
    });

    final state = ref.watch(favouriteForumListProvider);
    final forums = state.forums;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            try {
              await notifier.refresh();
            } catch (error) {
              AppToast.error(error);
            }
          },
          child: CustomScrollView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // 最近访问快捷条：没有记录时内部返回 shrink，不占位
              const SliverToBoxAdapter(child: RecentForumStrip()),
              SliverPadding(
                // 为手势条 + FAB 留出空间（上游 #41）
                padding: EdgeInsets.only(bottom: bottomPadding + 88),
                sliver: SliverGrid.builder(
                  // 上游 #41：固定宽度的自适应网格，大屏不再被拉成三列巨块
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 120,
                    mainAxisExtent: 108,
                  ),
                  itemCount: forums.length,
                  itemBuilder: (_, index) => ForumGridItemWidget(
                    forums[index],
                    onLongPress: () =>
                        _showDeleteDialog(notifier, forums[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (state.isSyncing && forums.isEmpty)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  void _showDeleteDialog(FavouriteForumListNotifier notifier, Forum forum) {
    showDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final isBusy = ref.watch(favouriteForumBusyProvider(forum.identity));
          final colorScheme = Theme.of(context).colorScheme;
          return M3Dialog(
            title: '移除收藏版面',
            content: Text(
              '确定从我的收藏中移除「${forum.name}」吗？',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: isBusy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
                onPressed: isBusy
                    ? null
                    : () async {
                        try {
                          await notifier.delete(forum);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          AppToast.error(error);
                        }
                      },
                child: const Text('移除'),
              ),
            ],
          );
        },
      ),
    );
  }
}
