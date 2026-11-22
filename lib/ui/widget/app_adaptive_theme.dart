import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/providers/settings/theme_provider.dart';
import 'package:flutter_nga/utils/theme_builder.dart';

/// 按 [themeProvider] 当前主题色构建 [AdaptiveTheme]。
///
/// 注意：[AdaptiveTheme] 只在 initState 时读取 light/dark，之后传入新主题不会
/// 生效（它的 didUpdateWidget 不处理这两个参数），运行期切换主题色必须调用
/// `AdaptiveTheme.of(context).setTheme`（见 [ThemeNotifier.setSeedColor]）。
/// 因此冷启动时 [themeProvider] 必须在首帧前就持有已保存的主题色，
/// 由 `main()` 通过 [ThemeNotifier.loadSaved] 预读并注入。
class AppAdaptiveTheme extends ConsumerWidget {
  const AppAdaptiveTheme({super.key, this.initialMode, required this.builder});

  final AdaptiveThemeMode? initialMode;
  final AdaptiveThemeBuilder builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seedColor = ref.watch(themeProvider.select((s) => s.seedColor));
    final dynamicEnabled = ref.watch(
      themeProvider.select((s) => s.dynamicColor),
    );

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        // 取到系统调色板后写入 notifier 供设置页运行期切换使用。
        // 本 widget 通过 select 只订阅开关与主题色，写入不会引发重建循环。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (lightDynamic != null) {
            ref
                .read(themeProvider.notifier)
                .updateDynamicSchemes(
                  ThemeBuilder.fromFlutterScheme(lightDynamic),
                  darkDynamic == null
                      ? null
                      : ThemeBuilder.fromFlutterScheme(darkDynamic),
                );
          }
        });

        final useDynamic = dynamicEnabled && lightDynamic != null;
        if (dynamicEnabled && lightDynamic == null) {
          // 开关开启但系统调色板还没取到（首帧异步）：短暂等待一帧，
          // 避免 AdaptiveTheme 用种子色初始化后无法切到动态主题
          return ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const SizedBox.shrink(),
          );
        }

        return AdaptiveTheme(
          light: useDynamic
              ? ThemeBuilder.buildLightDynamicTheme(
                  ThemeBuilder.fromFlutterScheme(lightDynamic),
                )
              : ThemeBuilder.buildLightTheme(seedColor),
          dark: useDynamic && darkDynamic != null
              ? ThemeBuilder.buildDarkDynamicTheme(
                  ThemeBuilder.fromFlutterScheme(darkDynamic),
                )
              : ThemeBuilder.buildDarkTheme(seedColor),
          initial: initialMode ?? AdaptiveThemeMode.light,
          builder: builder,
        );
      },
    );
  }
}
