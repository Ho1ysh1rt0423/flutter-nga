import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/motion.dart';
import 'package:flutter_nga/utils/picture_utils.dart' as picture_utils;

/// 图片预览页：双指缩放 / 拖动 / 图组内左右滑动切换。
///
/// 视觉上采用沉浸式黑底：点按图片切换顶部 chrome（返回 + 标题/页码）显隐，
/// 与上游 #41 一致；但**不提供常驻下载按钮**——保存与复制统一走长按操作
/// 面板（用户明确要求移除右上角保存按钮，见 LOCAL_FEATURES 功能 19）。
///
/// [urls] 是图组内全部原图地址（贴内一组图片 / 列表缩略图组），
/// [initialIndex] 决定打开第几张；单图时 [urls] 长度为 1，不显示页码。
class PhotoPreviewPage extends HookConsumerWidget {
  const PhotoPreviewPage({
    super.key,
    this.urls,
    this.url,
    this.initialIndex = 0,
    this.screenWidth,
  });

  /// 图组内全部地址；为空时回退到单图 [url]
  final List<String>? urls;

  /// 单图调用点兼容
  final String? url;
  final int initialIndex;
  final double? screenWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gallery = useMemoized(() {
      final all = (urls ?? const <String>[])
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();
      if (all.isNotEmpty) return all;
      final single = url?.trim() ?? '';
      return single.isEmpty ? const <String>[] : <String>[single];
    }, [urls, url]);

    if (gallery.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("查看图片")),
        body: const Center(child: Text('图片地址为空')),
      );
    }

    final startIndex = initialIndex.clamp(0, gallery.length - 1);
    final pageController = useMemoized(
      () => PageController(initialPage: startIndex),
      [gallery, startIndex],
    );
    useEffect(() => pageController.dispose, [pageController]);
    final currentIndex = useState(startIndex);
    final showChrome = useState(true);

    final title = gallery.length > 1
        ? '查看图片 ${currentIndex.value + 1}/${gallery.length}'
        : '查看图片';
    final topPadding = MediaQuery.paddingOf(context).top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              // 长按弹操作面板。拖动 / 缩放由内层 PhotoView 接管，长按（无位移
              // 的持续按压）才会落到这里，两者手势仲裁不冲突。
              onLongPress: () =>
                  _showActions(context, gallery[currentIndex.value]),
              child: PhotoViewGallery.builder(
                pageController: pageController,
                itemCount: gallery.length,
                onPageChanged: (index) => currentIndex.value = index,
                builder: (context, index) => PhotoViewGalleryPageOptions(
                  imageProvider: CachedNetworkImageProvider(
                    picture_utils.getOriginalUrl(gallery[index]),
                  ),
                  // 与旧版一致：比屏幕宽时按屏宽铺满，否则保持 1:1
                  minScale: PhotoViewComputedScale.contained,
                  initialScale: PhotoViewComputedScale.contained,
                  // 点按切换顶部 chrome 显隐（上游 #41 的沉浸式交互）
                  onTapUp: (_, _, _) =>
                      showChrome.value = !showChrome.value,
                ),
                loadingBuilder: (context, event) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                // 单图禁掉左右滑，避免 PageView 抢走单图拖动
                scrollPhysics: gallery.length > 1
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
              ),
            ),
            // 顶部 chrome：返回 + 标题/页码。隐藏时不拦截手势，方便继续缩放拖动。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !showChrome.value,
                child: AnimatedOpacity(
                  opacity: showChrome.value ? 1.0 : 0.0,
                  duration: Motion.resolveDuration(
                    context,
                    Motion.durationShort4,
                  ),
                  curve: Motion.emphasized,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000)],
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.only(top: topPadding),
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            const BackButton(color: Colors.white),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            // 有意不放下载/保存按钮：保存与复制走长按操作面板。
                            const SizedBox(width: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, String imageUrl) async {
    final original = picture_utils.getOriginalUrl(imageUrl);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('保存到相册'),
              onTap: () => Navigator.of(context).pop('save'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('复制图片地址'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
          ],
        ),
      ),
    );
    if (action == 'save') {
      try {
        await Data().resourceRepository.saveImageToGallery(original);
        AppToast.success("保存到相册成功");
      } catch (e) {
        AppToast.error(e);
      }
    } else if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: original));
      AppToast.success("已复制图片地址");
    }
  }
}