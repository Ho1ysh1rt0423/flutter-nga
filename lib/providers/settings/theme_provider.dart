import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter_nga/data/core/app_preferences.dart';
import 'package:flutter_nga/utils/theme_builder.dart';

const String _keySeedColorValue = PrefsKeys.seedColorValue;

/// 预设主题色列表
class ThemeColors {
  static const List<Color> presets = [
    Colors.brown, // 默认 - 棕色
    Colors.blue, // 蓝色
    Colors.teal, // 青色
    Colors.green, // 绿色
    Colors.purple, // 紫色
    Colors.pink, // 粉色
    Colors.orange, // 橙色
    Colors.red, // 红色
    Colors.indigo, // 靛蓝
    Colors.cyan, // 青蓝
  ];

  static const List<String> names = [
    "棕色",
    "蓝色",
    "青色",
    "绿色",
    "紫色",
    "粉色",
    "橙色",
    "红色",
    "靛蓝",
    "青蓝",
  ];

  static Color get defaultColor => presets.first;
}

class ThemeState {
  final AdaptiveThemeMode? mode;
  final Color seedColor;

  /// Material You 动态取色开关（Android 12+ 壁纸强调色）。开启且系统提供
  /// 动态调色板时，主题色预设被忽略。
  final bool dynamicColor;

  /// 系统动态调色板（DynamicColorBuilder 取到后写入，亮/暗各一）。
  /// null 表示系统不支持或尚未取到。
  final ColorScheme? lightDynamicScheme;
  final ColorScheme? darkDynamicScheme;

  ThemeState({
    this.mode,
    Color? seedColor,
    this.dynamicColor = false,
    this.lightDynamicScheme,
    this.darkDynamicScheme,
  }) : seedColor = seedColor ?? ThemeColors.defaultColor;

  String get modeName {
    switch (mode) {
      case AdaptiveThemeMode.light:
        return "亮色主题";
      case AdaptiveThemeMode.dark:
        return "暗色主题";
      case AdaptiveThemeMode.system:
        return "跟随系统";
      default:
        return "亮色主题";
    }
  }

  String get seedColorName {
    final index = ThemeColors.presets.indexOf(seedColor);
    if (index >= 0 && index < ThemeColors.names.length) {
      return ThemeColors.names[index];
    }
    return "自定义";
  }

  ThemeState copyWith({
    AdaptiveThemeMode? mode,
    Color? seedColor,
    bool? dynamicColor,
    ColorScheme? lightDynamicScheme,
    ColorScheme? darkDynamicScheme,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      dynamicColor: dynamicColor ?? this.dynamicColor,
      lightDynamicScheme: lightDynamicScheme ?? this.lightDynamicScheme,
      darkDynamicScheme: darkDynamicScheme ?? this.darkDynamicScheme,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeState> {
  /// [initialState] 通常由 `main()` 在 `runApp` 前通过 [loadSaved] 预读后注入，
  /// 保证首帧就使用已保存的主题色，而不是先用默认色。
  ThemeNotifier([this._initialState]);

  final ThemeState? _initialState;

  @override
  ThemeState build() => _initialState ?? ThemeState();

  /// DynamicColorBuilder 取到系统调色板后写入（不通知界面，避免重建循环
  /// ——AppAdaptiveTheme 用 select 只订阅开关与主题色）。
  void updateDynamicSchemes(ColorScheme? light, ColorScheme? dark) {
    state = state.copyWith(lightDynamicScheme: light, darkDynamicScheme: dark);
  }

  /// 是否生效动态取色（开关开 + 系统给得出调色板）
  bool get _dynamicColorActive =>
      state.dynamicColor && state.lightDynamicScheme != null;

  /// 运行期应用动态取色主题（设置页切换开关时调用，需 context）
  Future<void> applyDynamicColor(BuildContext context, bool enabled) async {
    state = state.copyWith(dynamicColor: enabled);
    // AdaptiveTheme 引用要在 async gap（prefs 落盘）之前取好
    final adaptiveTheme = AdaptiveTheme.of(context);
    final prefs = await AppPreferences.instance();
    await prefs.setBool(PrefsKeys.themeDynamicColor, enabled);
    if (enabled && _dynamicColorActive) {
      adaptiveTheme.setTheme(
        light: ThemeBuilder.buildLightDynamicTheme(state.lightDynamicScheme!),
        dark: ThemeBuilder.buildDarkDynamicTheme(state.darkDynamicScheme!),
      );
    } else {
      adaptiveTheme.setTheme(
        light: ThemeBuilder.buildLightTheme(state.seedColor),
        dark: ThemeBuilder.buildDarkTheme(state.seedColor),
      );
    }
  }

  /// 读取已保存的主题模式与主题色，可在 `runApp` 前调用。
  static Future<ThemeState> loadSaved() async {
    // 先取 AppPreferences：它会等待旧版设置迁移完成（含 adaptive_theme 的
    // 亮/暗模式），再读主题模式才不会读到迁移前的空值。
    final prefs = await AppPreferences.instance();
    final mode = await AdaptiveTheme.getThemeMode();
    final seedColor = seedColorFromValue(prefs.getInt(_keySeedColorValue));
    final dynamicColor = prefs.getBool(PrefsKeys.themeDynamicColor) ?? false;
    return ThemeState(
      mode: mode,
      seedColor: seedColor,
      dynamicColor: dynamicColor,
    );
  }

  /// 把保存的 ARGB 值还原为颜色。
  ///
  /// 命中预设时返回预设里的 [MaterialColor] 实例：[Color] 的 `==` 会比较
  /// runtimeType，直接用 `Color(value)` 会导致预设匹配失败（主题色名称显示
  /// 为「自定义」、辅色回退为默认值）。
  @visibleForTesting
  static Color seedColorFromValue(int? value) {
    if (value == null) return ThemeColors.defaultColor;
    for (final preset in ThemeColors.presets) {
      if (preset.toARGB32() == value) return preset;
    }
    return Color(value);
  }

  Future<void> refresh() async {
    final saved = await loadSaved();
    state = state.copyWith(mode: saved.mode, seedColor: saved.seedColor);
  }

  void update(BuildContext context, AdaptiveThemeMode adaptiveThemeMode) {
    AdaptiveTheme.of(context).setThemeMode(adaptiveThemeMode);
    state = state.copyWith(mode: adaptiveThemeMode);
  }

  Future<void> setSeedColor(BuildContext context, Color color) async {
    // Get AdaptiveTheme reference before async gap
    final adaptiveTheme = AdaptiveTheme.of(context);

    final prefs = await AppPreferences.instance();
    await prefs.setInt(_keySeedColorValue, color.toARGB32());
    // 选了预设色即视为放弃动态取色，避免动态调色板把预设盖掉
    if (state.dynamicColor) {
      state = state.copyWith(dynamicColor: false);
      await prefs.setBool(PrefsKeys.themeDynamicColor, false);
    }
    state = state.copyWith(seedColor: color);

    // Apply theme using AdaptiveTheme API
    _applyThemeWithRef(adaptiveTheme, color);
  }

  void _applyThemeWithRef(
    AdaptiveThemeManager<ThemeData> adaptiveTheme,
    Color seedColor,
  ) {
    adaptiveTheme.setTheme(
      light: ThemeBuilder.buildLightTheme(seedColor),
      dark: ThemeBuilder.buildDarkTheme(seedColor),
    );
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeState>(
  ThemeNotifier.new,
);
