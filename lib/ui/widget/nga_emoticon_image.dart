import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/core/nga_dio_configurator.dart';
import 'package:flutter_nga/data/data.dart';
import 'package:flutter_nga/providers/settings/interface_settings_provider.dart';
import 'package:flutter_nga/utils/emoticon_visibility.dart';

/// NGA 表情图片。
///
/// 用项目自己的 Dio 下载图片字节再 `Image.memory` 渲染：Flutter 自带的
/// `Image.network` 在这套 NGA 图床上拿不到数据（失败时 errorBuilder 只会输出
/// 空文本，表现为表情位置完全空白）。Dio 这条链路与「保存图片到相册」一致，
/// 带 Cookie/UA 并跳过 GBK 拦截，已验证可用。
///
/// 深色主题下，AC娘 / 新AC娘 / 外域三人组等「纯黑线稿 + 透明背景」的表情会与
/// 背景融为一体，看起来像没加载出来。这里在解码后分析像素，若确实是深色透明
/// 线稿就把线条反相成白色（保留透明度，不垫白底，避免出现突兀的白块）；
/// 彩色表情保持原样。
class NgaEmoticonImage extends StatefulWidget {
  const NgaEmoticonImage({
    super.key,
    required this.url,
    this.size = InterfaceSettingsState.defaultEmoticonSize,
  });

  final String url;
  final double size;

  @override
  State<NgaEmoticonImage> createState() => _NgaEmoticonImageState();
}

class _NgaEmoticonImageState extends State<NgaEmoticonImage> {
  /// 进程内缓存，避免列表滚动 / 表情面板重开时重复下载
  static final Map<String, Uint8List> _bytesCache = {};

  /// 是否为深色透明线稿（需要在深色主题下反相）。与字节同生命周期，
  /// 避免每次重建都重新解码分析像素。
  static final Map<String, bool> _invertCache = {};

  /// 反相矩阵：RGB 各通道取反，alpha 保持不变。
  ///
  /// `ColorFilter.matrix` 处理的是**非预乘**颜色值，末行 alpha 用
  /// `[0,0,0,1,0]` 原样透传，所以透明背景不会被反成不透明。
  static const List<double> _invertMatrix = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  Uint8List? _bytes;
  bool _invertInDark = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bytes = _bytesCache[widget.url];
    _invertInDark = _invertCache[widget.url] ?? false;
    if (_bytes == null) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final response = await Data().dio.get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          extra: {NgaDioConfigurator.rawResponseKey: true},
        ),
      );
      final data = response.data;
      final bytes = data == null
          ? Uint8List(0)
          : (data is Uint8List ? data : Uint8List.fromList(data));
      if (bytes.isEmpty) {
        throw StateError('表情图片数据为空');
      }
      _bytesCache[widget.url] = bytes;
      final invert = await EmoticonVisibility.needsInvertInDarkForBytes(bytes);
      _invertCache[widget.url] = invert;
      if (mounted) {
        setState(() {
          _bytes = bytes;
          _invertInDark = invert;
        });
      }
    } catch (err) {
      debugPrint('[emoticon] 加载失败 ${widget.url} -> $err');
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    if (_bytes != null) {
      final image = Image.memory(
        _bytes!,
        width: size,
        height: size,
        // 表情外框是正方形，contain 让非正方形表情保持原始比例不拉伸
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
      // 只在深色主题 + 深色线稿时反相，浅色主题 / 彩色表情保持原样
      final isDark = Theme.of(context).brightness == Brightness.dark;
      if (!isDark || !_invertInDark) {
        return image;
      }
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(_invertMatrix),
        child: image,
      );
    }
    if (_failed) {
      // 与缺 src 一致回退为 [表情] 文字：沿用文字自身基线，行内对齐自然
      // （避免图标把 EmoticonBaseline 的下沉对齐带偏）
      return const Text('[表情]');
    }
    return SizedBox(width: size, height: size);
  }
}
