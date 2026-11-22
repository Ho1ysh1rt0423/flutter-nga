import 'package:cupertino_ui/cupertino_ui.dart';
// 类型桥接：dynamic_color 返回 Flutter 的 ColorScheme，而本文件的 ColorScheme
// 是 material_ui 复刻的独立类，必须引用 Flutter 侧类型做逐字段转换。
// material_ui 迁移标记弃用了 flutter/material 导入，但此类型无替代公共导出，
// 属于不可避免的桥接（不用于任何组件）。
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as flutter_scheme show ColorScheme;
import 'package:material_ui/material_ui.dart';

/// 主题构建工具类
class ThemeBuilder {
  ThemeBuilder._();

  // 经典暗金/琥珀色：与棕色 primary 完美协调，更贴近 NGA 的经典质感，同时提供足够的亮度。
  static const _secondarySeed = Color(0xFFDCA965);

  static Color getSecondaryForSeed(Color seed) {
    if (seed == Colors.brown) return const Color(0xFFDCA965);
    if (seed == Colors.blue) return Colors.lightBlue;
    if (seed == Colors.teal) return Colors.cyan;
    if (seed == Colors.green) return Colors.lightGreen;
    if (seed == Colors.purple) return Colors.deepPurpleAccent;
    if (seed == Colors.pink) return Colors.purpleAccent;
    if (seed == Colors.orange) return Colors.amber;
    if (seed == Colors.red) return Colors.deepOrange;
    if (seed == Colors.indigo) return Colors.blueAccent;
    if (seed == Colors.cyan) return Colors.lightBlueAccent;
    return _secondarySeed;
  }

  /// 从 ColorScheme 构建 ThemeData
  ///
  /// [refineSecondary] 为 false 时不覆盖辅色系——Material You 动态取色的
  /// 调色板自成体系，不应混入固定的琥珀辅色。
  static ThemeData buildTheme(
    ColorScheme baseColorScheme, [
    Color? secondarySeed,
    bool refineSecondary = true,
  ]) {
    final colorScheme = refineSecondary
        ? _withRefinedSecondary(baseColorScheme, secondarySeed)
        : baseColorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // M3 Expressive 页面过渡
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        },
      ),
      // AppBar 主题
      appBarTheme: AppBarTheme(
        centerTitle: true,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      // Card 主题
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: colorScheme.surfaceContainerLow,
      ),
      // FAB 主题
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // Divider 主题
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      // ListTile 主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // M3 Dialog Theme
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      // M3 Button Themes
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      // M3 Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      // M3 NavigationBar Theme
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
      ),
      // M3 NavigationRail Theme
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        selectedIconTheme: IconThemeData(
          color: colorScheme.onSecondaryContainer,
        ),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static ColorScheme _withRefinedSecondary(
    ColorScheme base, [
    Color? secondarySeed,
  ]) {
    final seed = secondarySeed ?? _secondarySeed;
    final accent = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: base.brightness,
    );
    return base.copyWith(
      secondary: accent.primary,
      onSecondary: accent.onPrimary,
      secondaryContainer: accent.primaryContainer,
      onSecondaryContainer: accent.onPrimaryContainer,
      secondaryFixed: accent.primaryFixed,
      secondaryFixedDim: accent.primaryFixedDim,
      onSecondaryFixed: accent.onPrimaryFixed,
      onSecondaryFixedVariant: accent.onPrimaryFixedVariant,
    );
  }

  /// 把 Flutter 的 ColorScheme 转成 material_ui fork 出来的同名类型。
  ///
  /// `dynamic_color` 包返回 Flutter 的 ColorScheme，而本文件的 ColorScheme
  /// 是 material_ui 复刻的独立类（同名不同类型），必须逐字段转换。
  /// （这里 import flutter/material 仅为桥接类型，不用于组件。）
  static ColorScheme fromFlutterScheme(flutter_scheme.ColorScheme s) {
    return ColorScheme(
      brightness: s.brightness,
      primary: s.primary,
      onPrimary: s.onPrimary,
      primaryContainer: s.primaryContainer,
      onPrimaryContainer: s.onPrimaryContainer,
      primaryFixed: s.primaryFixed,
      onPrimaryFixed: s.onPrimaryFixed,
      primaryFixedDim: s.primaryFixedDim,
      onPrimaryFixedVariant: s.onPrimaryFixedVariant,
      secondary: s.secondary,
      onSecondary: s.onSecondary,
      secondaryContainer: s.secondaryContainer,
      onSecondaryContainer: s.onSecondaryContainer,
      secondaryFixed: s.secondaryFixed,
      onSecondaryFixed: s.onSecondaryFixed,
      secondaryFixedDim: s.secondaryFixedDim,
      onSecondaryFixedVariant: s.onSecondaryFixedVariant,
      tertiary: s.tertiary,
      onTertiary: s.onTertiary,
      tertiaryContainer: s.tertiaryContainer,
      onTertiaryContainer: s.onTertiaryContainer,
      tertiaryFixed: s.tertiaryFixed,
      onTertiaryFixed: s.onTertiaryFixed,
      tertiaryFixedDim: s.tertiaryFixedDim,
      onTertiaryFixedVariant: s.onTertiaryFixedVariant,
      error: s.error,
      onError: s.onError,
      errorContainer: s.errorContainer,
      onErrorContainer: s.onErrorContainer,
      surface: s.surface,
      onSurface: s.onSurface,
      surfaceContainerLowest: s.surfaceContainerLowest,
      surfaceContainerLow: s.surfaceContainerLow,
      surfaceContainer: s.surfaceContainer,
      surfaceContainerHigh: s.surfaceContainerHigh,
      surfaceContainerHighest: s.surfaceContainerHighest,
      surfaceDim: s.surfaceDim,
      surfaceBright: s.surfaceBright,
      onSurfaceVariant: s.onSurfaceVariant,
      outline: s.outline,
      outlineVariant: s.outlineVariant,
      shadow: s.shadow,
      scrim: s.scrim,
      inverseSurface: s.inverseSurface,
      onInverseSurface: s.onInverseSurface,
      inversePrimary: s.inversePrimary,
      surfaceTint: s.surfaceTint,
    );
  }

  /// 动态取色直接构建（保留系统调色板的全部色板）
  static ThemeData buildLightDynamicTheme(ColorScheme dynamicScheme) =>
      buildTheme(dynamicScheme, null, false);

  static ThemeData buildDarkDynamicTheme(ColorScheme dynamicScheme) =>
      buildTheme(dynamicScheme, null, false);

  /// 从种子色构建亮色主题
  static ThemeData buildLightTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    return buildTheme(colorScheme, getSecondaryForSeed(seedColor));
  }

  /// 从种子色构建暗色主题
  static ThemeData buildDarkTheme(Color seedColor) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.dark,
    );
    return buildTheme(colorScheme, getSecondaryForSeed(seedColor));
  }
}
