import 'dart:math';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nga/providers/forum/forum_category_list_provider.dart';
import 'package:flutter_nga/providers/home/home_provider.dart';
import 'package:flutter_nga/providers/settings/interface_settings_provider.dart';
import 'package:flutter_nga/ui/page/forum_group/favourite_forum_group_page.dart';
import 'package:flutter_nga/ui/widget/keep_alive_tab_view.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/dimen.dart';
import 'package:flutter_nga/utils/hooks/easy_refresh_hooks.dart';
import 'package:flutter_nga/utils/hooks/material_tab_controller_hook.dart';
import 'package:flutter_nga/utils/hooks/scroll_to_top.dart';

import 'forum_category_page.dart';

/// 社区首页（首页 Tab 的内容页）。
///
/// 两种布局，由接口设置里的「首页左侧分类栏」开关切换：
/// - 关（上游默认）：顶部横向 TabBar + TabBarView；
/// - 开（官方客户端样式）：左侧分类栏 + 右侧内容，`IndexedStack` 保持
///   各分类页状态。
class ForumGroupTabsPage extends HookConsumerWidget {
  const ForumGroupTabsPage({super.key, this.scrollToTop});

  /// 首页触发「回到顶部」时，滚动当前 Tab
  final ScrollToTopSignal? scrollToTop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    usePostFrameEffect(() {
      ref.read(forumCategoryListProvider.notifier).ensureLoaded();
    });

    final categoryState = ref.watch(forumCategoryListProvider);
    final categories = categoryState.categories;
    final useRail = ref.watch(
      interfaceSettingsProvider.select((s) => s.homeCategoryRail),
    );
    final tabSignals = useScrollToTopSignals(
      1 + (categories.isEmpty ? 1 : categories.length),
    );

    List<String> tabLabels = ["我的收藏"];
    List<Widget> tabBarViews = [
      KeepAliveTabView(
        child: FavouriteForumGroupPage(scrollToTop: tabSignals[0]),
      ),
    ];

    if (categories.isEmpty) {
      // 首次启动且无缓存时，用占位 Tab 展示加载中 / 失败重试
      tabLabels.add("版块");
      tabBarViews.add(const _ForumCategoryPlaceholder());
    } else {
      tabLabels.addAll(categories.map((category) => category.name));
      tabBarViews.addAll(
        categories.indexed.map(
          (e) => KeepAliveTabView(
            child: ForumCategoryPage(
              category: e.$2,
              scrollToTop: tabSignals[e.$1 + 1],
            ),
          ),
        ),
      );
    }

    // 分类数量变化时会重建 controller，尽量保留当前选中的 Tab（读取时钳制）
    final selectedIndex = useState(0);
    final tabController = useMaterialTabController(
      initialLength: tabLabels.length,
      initialIndex: min(selectedIndex.value, tabLabels.length - 1),
      keys: [tabLabels.length],
    );

    void updateIndex(int i) {
      selectedIndex.value = min(i, tabLabels.length - 1);
      // 更新 FAB 可见性：只有第一个 tab (我的收藏) 才显示
      ref
          .read(forumGroupFabVisibleProvider.notifier)
          .setVisible(tabController.index == 0);
    }

    useEffect(() {
      void listener() => updateIndex(tabController.index);
      tabController.addListener(listener);
      // 初始化状态
      Future.microtask(() => listener());
      return () => tabController.removeListener(listener);
    }, [tabController]);

    useEffect(() {
      final signal = scrollToTop;
      if (signal == null) return null;
      void listener() => tabSignals[tabController.index].fire();
      signal.addListener(listener);
      return () => signal.removeListener(listener);
    }, [scrollToTop, tabSignals, tabController]);

    if (useRail) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: SizedBox(
              width: 76,
              child: ListView.builder(
                itemCount: tabLabels.length,
                itemBuilder: (context, index) => _RailCategoryTile(
                  label: tabLabels[index],
                  selected: index == selectedIndex.value,
                  onTap: () {
                    tabController.index = index;
                    updateIndex(index);
                  },
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: selectedIndex.value,
              children: tabBarViews,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          bottom: TabBar(
            controller: tabController,
            isScrollable: true,
            tabs: [for (final label in tabLabels) Tab(text: label)],
          ),
        ),
      ),
      body: TabBarView(controller: tabController, children: tabBarViews),
    );
  }
}

/// 左侧分类栏的单个分类块：选中时左侧竖条 + 主色容器底，文字 2~3 行换行
class _RailCategoryTile extends StatelessWidget {
  const _RailCategoryTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? colorScheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          alignment: Alignment.center,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

class _ForumCategoryPlaceholder extends ConsumerWidget {
  const _ForumCategoryPlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(forumCategoryListProvider);
    final error = state.error;
    if (error == null || state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimen.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: Dimen.spacingL),
            FilledButton.tonal(
              onPressed: () => ref
                  .read(forumCategoryListProvider.notifier)
                  .refresh()
                  .catchError(AppToast.error),
              child: const Text("重试"),
            ),
          ],
        ),
      ),
    );
  }
}
