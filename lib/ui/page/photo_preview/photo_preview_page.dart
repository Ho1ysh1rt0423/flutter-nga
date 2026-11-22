import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/utils/app_toast.dart';
import 'package:flutter_nga/utils/picture_utils.dart' as picture_utils;

/// 图片预览页：双指缩放 / 拖动 / 图组内左右滑动切换。
///
/// 长按图片弹出操作面板（保存到相册 / 复制图片地址），替代原先的右上角
/// 保存按钮（已按用户要求移除）。
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          gallery.length > 1
              ? '查看图片 ${currentIndex.value + 1}/${gallery.length}'
              : '查看图片',
        ),
      ),
      body: GestureDetector(
        // 长按弹操作面板。拖动 / 缩放由内层 PhotoView 接管，长按（无位移的
        // 持续按压）才会落到这里，两者手势仲裁不冲突。
        onLongPress: () => _showActions(context, gallery[currentIndex.value]),
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
          ),
          loadingBuilder: (context, event) =>
              const Center(child: CircularProgressIndicator()),
          backgroundDecoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
          // 单图禁掉左右滑，避免 PageView 抢走单图拖动
          scrollPhysics: gallery.length > 1
              ? const PageScrollPhysics()
              : const NeverScrollableScrollPhysics(),
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
