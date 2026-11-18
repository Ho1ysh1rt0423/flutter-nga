import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:community_material_icon/community_material_icon.dart';
import 'package:flutter/gestures.dart' show DeviceGestureSettings;
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_nga/providers/settings/theme_provider.dart';
import 'package:flutter_nga/providers/topic/topic_detail_provider.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_page_select_dialog.dart';
import 'package:flutter_nga/ui/page/topic_detail/topic_single_page.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/code_utils.dart' as code_utils;
import 'package:flutter_nga/utils/hooks/material_tab_controller_hook.dart';
import 'package:flutter_nga/utils/nga_links.dart';
import 'package:flutter_nga/utils/route.dart';

/// 帖子详情 AppBar 溢出菜单
enum TopicDetailMenuAction {
  copyLink('复制帖子链接'),
  openInBrowser('在浏览器中打开');

  const TopicDetailMenuAction(this.label);

  final String label;
}

/// 翻页起手的触摸斜率（逻辑像素）。默认 18px 太灵，斜着滑动容易误触；
/// 页面内的列表在 TopicSinglePage 里恢复默认斜率，斜滑会被列表优先赢走。
const double kPageFlipTouchSlop = 40;

class TopicDetailPage extends HookConsumerWidget {
  const TopicDetailPage(
    this.tid,
    this.fid, {
    super.key,
    this.subject,
    this.authorid,
  });

  final int? tid;
  final int? fid;
  final String? subject;
  final int? authorid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerKey = TopicDetailKey(tid: tid!);
    final state = ref.watch(topicDetailProvider(providerKey));
    final notifier = ref.read(topicDetailProvider(providerKey).notifier);

    final length = state.maxPage < 1 ? 1 : state.maxPage;
    final initialIndex = (state.currentPage - 1).clamp(0, length - 1);
    final tabController = useMaterialTabController(
      initialLength: length,
      initialIndex: initialIndex,
      keys: [length],
    );

    // Only mount TopicSinglePage for pages the user has actually opened.
    final visitedPages = useState(<int>{initialIndex});

    useEffect(() {
      // Drop indices that no longer exist after maxPage shrinks/grows rebuild.
      final valid = visitedPages.value.where((i) => i < length).toSet();
      if (!valid.contains(tabController.index)) {
        valid.add(tabController.index);
      }
      if (valid.length != visitedPages.value.length ||
          !valid.containsAll(visitedPages.value)) {
        visitedPages.value = valid;
      }
      return null;
    }, [length]);

    useEffect(() {
      void listener() {
        final index = tabController.index;
        // 整屏横滑时也要先把页挂上，否则连续快划会滑到没构建的
        // SizedBox.shrink 占位上，露出空白。
        if (!visitedPages.value.contains(index)) {
          visitedPages.value = {...visitedPages.value, index};
        }
        // 页码只在切换完成后更新，避免拖动过程中底部页码乱跳。
        if (tabController.indexIsChanging) return;
        notifier.setCurrentPage(index + 1);
      }

      tabController.addListener(listener);
      return () => tabController.removeListener(listener);
    }, [tabController]);

    void jumpToFloor(int lou) {
      if (lou <= 0) return;
      final target = (lou / 20 - 1)
          .ceil()
          .clamp(0, tabController.length - 1)
          .toInt();
      // Ensure the target page is built before animating to it.
      if (!visitedPages.value.contains(target)) {
        visitedPages.value = {...visitedPages.value, target};
      }
      tabController.animateTo(target);
    }

    // 手势翻页时，滑动过程中相邻页已经被 TabBarView 摆到视口里，
    // 因此除了用户访问过的页，当前页左右两页也要预先挂载，
    // 否则滑到一半会露出 SizedBox.shrink 的空白。
    final activeIndex = tabController.index;
    final mountedPages = <int>{
      ...visitedPages.value.where((i) => i >= 0 && i < length),
      if (activeIndex > 0) activeIndex - 1,
      if (activeIndex < length - 1) activeIndex + 1,
    };

    final widgets = <Widget>[
      for (var i = 0; i < length; i++)
        if (mountedPages.contains(i))
          TopicSinglePage(
            key: ValueKey('topic-$tid-page-${i + 1}'),
            tid: tid!,
            page: i + 1,
            authorid: authorid,
            onJumpToFloor: jumpToFloor,
          )
        else
          const SizedBox.shrink(),
    ];

    void goToPage(int target) {
      if (!visitedPages.value.contains(target)) {
        visitedPages.value = {...visitedPages.value, target};
      }
      tabController.animateTo(target);
    }

    final hasPrevious = state.currentPage > 1;
    final hasNext = state.currentPage < state.maxPage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favourited = state.favourite == FavouriteStatus.favourited;

    return Scaffold(
      appBar: AppBar(
        title: Text(code_utils.unescapeHtml(state.subject ?? subject ?? "")),
        actions: [
          PopupMenuButton<TopicDetailMenuAction>(
            tooltip: '更多',
            onSelected: (action) => _onMenuSelected(action),
            itemBuilder: (context) => [
              for (final action in TopicDetailMenuAction.values)
                PopupMenuItem(value: action, child: Text(action.label)),
            ],
          ),
        ],
      ),
      // 翻页手势防误触：默认 PageScrollPhysics 的横向识别器只要位移过
      // 18px 触摸斜率就接受手势，斜着滑动（竖向滚动带一点横向漂移）会
      // 误触翻页。这里保留 TabBarView 原生拖动（跟手、松手可弹回），只把
      // 起手斜率提高到 kPageFlipTouchSlop（40px）；页面内的列表通过
      // TopicSinglePage 里的 MediaQuery 恢复默认 18px —— 手势竞技场里
      // 列表的竖向识别器层次更深、斜率更小，斜滑会先被列表赢走，
      // 只有横向占比明显大的滑动才轮到翻页。
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          gestureSettings: DeviceGestureSettings(touchSlop: kPageFlipTouchSlop),
        ),
        child: TabBarView(controller: tabController, children: widgets),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页',
              icon: Icon(Icons.chevron_left),
              onPressed: hasPrevious
                  ? () => goToPage(tabController.index - 1)
                  : null,
            ),
            Tooltip(
              message: '跳转页码',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => TopicPageSelectDialog(
                      currentPage: state.currentPage,
                      maxPage: state.maxPage,
                      maxFloor: state.maxFloor,
                      pageSelectedCallback: (isPage, target) {
                        final index = isPage
                            ? target - 1
                            : (target / 20 - 1).ceil();
                        goToPage(
                          index.clamp(0, tabController.length - 1).toInt(),
                        );
                      },
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Text(
                    "${state.currentPage}/${state.maxPage}",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '下一页',
              icon: Icon(Icons.chevron_right),
              onPressed: hasNext
                  ? () => goToPage(tabController.index + 1)
                  : null,
            ),
            Spacer(flex: 1),
            // 按当前实际亮度在日间 / 夜间之间切换，图标与提示显示切换目标。
            IconButton(
              tooltip: isDark ? '切换到日间模式' : '切换到夜间模式',
              icon: Icon(
                isDark
                    ? CommunityMaterialIcons.weather_sunny
                    : CommunityMaterialIcons.weather_night,
              ),
              onPressed: () => ref
                  .read(themeProvider.notifier)
                  .update(
                    context,
                    isDark ? AdaptiveThemeMode.light : AdaptiveThemeMode.dark,
                  ),
            ),
            IconButton(
              tooltip: favourited ? '取消收藏' : '收藏',
              isSelected: favourited,
              icon: Icon(CommunityMaterialIcons.heart_outline),
              selectedIcon: Icon(CommunityMaterialIcons.heart),
              onPressed: state.favouriteBusy
                  ? null
                  : () {
                      notifier
                          .toggleFavourite()
                          .then((message) {
                            if (message != null) AppToast.success(message);
                          })
                          .catchError((e) {
                            AppToast.error(e);
                          });
                    },
            ),
            IconButton(
              tooltip: '回复',
              icon: Icon(CommunityMaterialIcons.comment_outline),
              onPressed: () {
                if (fid == null && state.topic == null) return;
                Routes.navigateTo(
                  context,
                  "${Routes.TOPIC_PUBLISH}?tid=$tid&fid=${fid ?? state.topic!.fid}",
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _onMenuSelected(TopicDetailMenuAction action) {
    final url = topicWebUrl(tid!);
    switch (action) {
      case TopicDetailMenuAction.copyLink:
        Clipboard.setData(ClipboardData(text: url))
            .then((_) => AppToast.success('已复制帖子链接'));
      case TopicDetailMenuAction.openInBrowser:
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).then((
          opened,
        ) {
          if (!opened) AppToast.error('无法打开浏览器');
        }, onError: (Object e) => AppToast.error('无法打开浏览器'));
    }
  }
}
